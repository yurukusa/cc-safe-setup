#!/bin/bash
# aup-retry-loop-guard.sh — Detect retry-loop pattern during Cluster 9 blocks and recommend exit
#
# Background:
#   Cluster 9 (Usage Policy classifier over-trigger) has a secondary failure mode that the
#   first three defense hooks do not address: even when an operator has been blocked and is
#   actively retrying the same input (the non-deterministic classifier sometimes passes on
#   retry — see #60366, #62190), each retry burns transcript context. For paying users on
#   Pro / Max quota, the retry loop drains the daily quota faster than the productive work
#   would have, leading to the "session quota MAX reached early" symptom.
#
#   Direct evidence from issue #61664 (Japanese paid user, 2026-05-23):
#     "ブロック発生時も context/credit は消費される"
#     "ブロック→巻き戻し→同じ処理の再実行 で context を浪費"
#     "昨日まで丸 1 日使っても使用量上限に達しなかったが、本日は早々に MAX に到達"
#
#   The first three hooks address awareness (helper), evidence collection (logger), and
#   session-start swap recommendations (suggester). None of them break a retry loop that
#   is already in progress within a single session.
#
#   Reference: ~/ops/customer-pain-cluster-9-secondary-pains-2026-05-30.md (axis 1)
#
# What this hook does:
#   On PostToolUse, read the aup-block-history.log (written by aup-block-pattern-logger.sh)
#   and check whether the last N blocks within a short window (default 5 minutes) all
#   targeted the same tool. When that pattern is detected, emit a non-blocking stderr
#   advisory recommending one of two cycle-breaking actions:
#     - `/exit` to end the session before more context is burned, then restart with Sonnet
#     - immediate `export ANTHROPIC_MODEL=claude-sonnet-4-7` for the current session
#
#   Distinct from model-swap-suggester (SessionStart, 60-min window): retry-loop-guard
#   runs PostToolUse, looks at a 5-min window, and addresses the intra-session retry
#   cycle that burns context — not the cross-session model selection decision.
#
# When this hook does NOT emit anything:
#   - CC_AUP_RETRY_LOOP_GUARD_DISABLE=1
#   - CC_AUP_RETRY_LOOP_GUARD_QUIET=1
#   - aup-block log missing, empty, or unreadable
#   - Fewer than threshold blocks in the configured window
#   - Blocks in window span multiple tools (single-tool retry loop is the diagnostic signal)
#   - The current advisory has already fired within the same session (one-shot per session)
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/aup-retry-loop-guard.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_AUP_RETRY_LOOP_GUARD_DISABLE=1         — never emit
#   CC_AUP_RETRY_LOOP_GUARD_QUIET=1           — silent
#   CC_AUP_RETRY_LOOP_GUARD_THRESHOLD=<n>     — block count threshold (default 3)
#   CC_AUP_RETRY_LOOP_GUARD_WINDOW_MIN=<n>    — lookback window in minutes (default 5)
#   CC_AUP_RETRY_LOOP_GUARD_TARGET=<model>    — target Sonnet model (default claude-sonnet-4-7)
#   CC_AUP_RETRY_LOOP_GUARD_STATE_DIR=<path>  — one-shot state directory (default $HOME/.claude)
#   CC_AUP_RETRY_LOOP_GUARD_SESSION_ID=<id>   — session identifier override for one-shot logic
#   CC_AUP_BLOCK_LOG_PATH=<path>              — log path (shared with logger; default $HOME/.claude/aup-block-history.log)
#
# Design notes:
#   - Single-tool restriction: the diagnostic for a retry loop is "same tool, same kind, in
#     a short window." A burst of blocks across different tools is more consistent with a
#     general session sensitivity than a retry cycle, and breaking the session for the
#     latter is more disruptive than helpful.
#   - One-shot per session: the advisory fires at most once per session. The state file
#     lives in $CC_AUP_RETRY_LOOP_GUARD_STATE_DIR/aup-retry-loop-guard.lock with the
#     session PID. Subsequent invocations from the same session see the lock and stay
#     silent so the advisory doesn't become its own noise loop.
#   - Never blocks. All failure paths exit 0 — a corrupt log or missing date utility
#     cannot break the tool call cycle.

set -u

# Disable path
if [ "${CC_AUP_RETRY_LOOP_GUARD_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Quiet path
if [ "${CC_AUP_RETRY_LOOP_GUARD_QUIET:-0}" = "1" ]; then
  exit 0
fi

LOG_PATH="${CC_AUP_BLOCK_LOG_PATH:-$HOME/.claude/aup-block-history.log}"
[ -f "$LOG_PATH" ] || exit 0
[ -r "$LOG_PATH" ] || exit 0
[ -s "$LOG_PATH" ] || exit 0

THRESHOLD="${CC_AUP_RETRY_LOOP_GUARD_THRESHOLD:-3}"
WINDOW_MIN="${CC_AUP_RETRY_LOOP_GUARD_WINDOW_MIN:-5}"
TARGET="${CC_AUP_RETRY_LOOP_GUARD_TARGET:-claude-sonnet-4-7}"
STATE_DIR="${CC_AUP_RETRY_LOOP_GUARD_STATE_DIR:-$HOME/.claude}"

case "$THRESHOLD" in
  ''|*[!0-9]*) THRESHOLD=3 ;;
esac
case "$WINDOW_MIN" in
  ''|*[!0-9]*) WINDOW_MIN=5 ;;
esac

NOW=$(date -u '+%s' 2>/dev/null) || exit 0
CUTOFF=$((NOW - WINDOW_MIN * 60))

ts_to_epoch() {
  local ts="$1"
  date -u -d "$ts" '+%s' 2>/dev/null \
    || date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null
}

# Collect blocks in window. The log schema is:
#   ISO8601_UTC | MODEL | TOOL | PATTERN_KIND | EXCERPT
# We track the tools that fired in the window. If all in-window blocks targeted the same
# tool and there are at least THRESHOLD of them, the pattern is a retry loop.
COUNT=0
UNIQUE_TOOLS=""
LAST_TOOL=""
LAST_KIND=""
while IFS='|' read -r LOG_TS _LOG_MODEL LOG_TOOL LOG_KIND _LOG_EXCERPT; do
  [ -z "$LOG_TS" ] && continue
  [ -z "$LOG_TOOL" ] && continue
  LOG_EPOCH=$(ts_to_epoch "$LOG_TS")
  [ -z "$LOG_EPOCH" ] && continue
  case "$LOG_EPOCH" in
    *[!0-9]*) continue ;;
  esac
  if [ "$LOG_EPOCH" -ge "$CUTOFF" ] 2>/dev/null; then
    COUNT=$((COUNT + 1))
    LAST_TOOL="$LOG_TOOL"
    LAST_KIND="$LOG_KIND"
    case "$UNIQUE_TOOLS" in
      *"|$LOG_TOOL|"*) : ;;
      *) UNIQUE_TOOLS="${UNIQUE_TOOLS}|${LOG_TOOL}|" ;;
    esac
  fi
done < "$LOG_PATH"

if [ "$COUNT" -lt "$THRESHOLD" ] 2>/dev/null; then
  exit 0
fi

# Count unique tools. Multi-tool bursts are not retry loops.
TOOL_COUNT=$(printf '%s' "$UNIQUE_TOOLS" | tr -cd '|' | wc -c)
TOOL_COUNT=$((TOOL_COUNT / 2))
if [ "$TOOL_COUNT" -ne 1 ] 2>/dev/null; then
  exit 0
fi

# One-shot per session. Session identifier resolution, in order of preference:
#   1. CC_AUP_RETRY_LOOP_GUARD_SESSION_ID env var (explicit override; tests, automation)
#   2. CLAUDECODE_SESSION_ID env var (Claude Code may export this in the future)
#   3. Controlling tty path (stable across child shells in an interactive session)
#   4. PPID fallback (last resort; less stable across subshell hops)
SESSION_ID="${CC_AUP_RETRY_LOOP_GUARD_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="${CLAUDECODE_SESSION_ID:-}"
fi
if [ -z "$SESSION_ID" ] && command -v tty >/dev/null 2>&1; then
  TTY_PATH=$(tty 2>/dev/null)
  if [ -n "$TTY_PATH" ] && [ "$TTY_PATH" != "not a tty" ]; then
    SESSION_ID=$(printf '%s' "$TTY_PATH" | tr '/' '_')
  fi
fi
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="ppid-${PPID:-0}"
fi

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="$STATE_DIR/aup-retry-loop-guard.lock"

if [ -f "$STATE_FILE" ]; then
  PRIOR=$(cat "$STATE_FILE" 2>/dev/null | head -1)
  if [ "$PRIOR" = "$SESSION_ID" ]; then
    exit 0
  fi
fi

# Trim stale entries: keep only the most recent 10 session IDs to bound the file.
if [ -f "$STATE_FILE" ]; then
  tail -n 10 "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null \
    && mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
fi
printf '%s\n' "$SESSION_ID" >> "$STATE_FILE" 2>/dev/null || true

# Emit the advisory. The recommendation tier is:
#   1. `/exit` immediately to stop burning context, then restart fresh with Sonnet pinned.
#   2. If you must continue this session, swap the model in-place; the same prompt may
#      pass on Sonnet without retry.
cat >&2 <<EOF
[aup-retry-loop-guard] Retry-loop pattern detected: $COUNT Usage Policy block(s) on
tool "$LAST_TOOL" within the last $WINDOW_MIN minute(s). Pattern kind: $LAST_KIND.

This shape — same tool, same block, repeated within a short window — is the retry-loop
signature reported in issue #61664: each retry consumes session context, even when the
attempt itself blocks. Pro / Max quota holders report hitting their daily quota MAX in
hours instead of a full day during this loop.

Recommended cycle-breaker (pick one):

  Option A — exit and restart fresh (safest for quota)
    1. /exit
    2. export ANTHROPIC_MODEL=$TARGET
    3. claude  # new session, no inherited context, Sonnet path

  Option B — swap in-place (continues current session)
    export ANTHROPIC_MODEL=$TARGET
    # the next prompt may pass; Sonnet is unaffected by the Cluster 9 signature

The Cluster 9 classifier is non-deterministic, so retrying identical input on the same
Opus pin sometimes works — but the context cost per retry typically exceeds the value
of the eventual successful turn. Breaking the cycle now preserves more daily quota for
productive work.

Related hooks (already active in this defense suite):
  aup-false-positive-helper.sh — generic awareness at session start
  aup-block-pattern-logger.sh  — evidence shape recorded at $LOG_PATH
  model-swap-suggester.sh      — session-start swap recommendation (60-min window)

To silence this advisory for the current session only:
  export CC_AUP_RETRY_LOOP_GUARD_QUIET=1

GitHub references:
  https://github.com/anthropics/claude-code/issues/60366  (cluster anchor)
  https://github.com/anthropics/claude-code/issues/61664  (retry-loop quota burn)
EOF

exit 0
