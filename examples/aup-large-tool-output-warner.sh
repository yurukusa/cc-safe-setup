#!/bin/bash
# aup-large-tool-output-warner.sh — Warn before Bash commands that may produce large
# sensitive-looking outputs that can trigger the Cluster 9 Usage Policy classifier
#
# Background:
#   Cluster 9 (Usage Policy classifier over-trigger) has a known trigger surface that
#   the first four defense hooks do not address: a single tool result containing a
#   large volume of security-shaped content (IP blocklists, firewall rules, packet
#   captures, kernel log dumps) can flip the classifier even when the surrounding
#   conversation is unambiguously benign.
#
#   Direct evidence from issue #61185 (filipghoulin, 2026-05-23):
#     "What triggered it: A lab-review skill dispatched a sub-agent that ran
#      `cat /etc/banip/banip.blocklist` on an OpenWRT router. The blocklist has
#      ~17,000 entries. That volume of content in a single tool result, combined
#      with the security shape of the content, appears to have flipped the
#      classifier into a permanent block state for the whole session."
#
#   Reference: ~/ops/customer-pain-cluster-9-secondary-pains-2026-05-30.md (axis 4)
#
#   The first three hooks address awareness, evidence collection, and session-start
#   model swap. The fourth hook (aup-retry-loop-guard.sh) breaks intra-session retry
#   cycles. None of them act *before* the offending tool call: by the time the
#   classifier has fired on the large output, the session is already wedged and
#   compact / clear may themselves block (see #61185 k33bs report). The only place
#   to address this trigger surface is the PreToolUse boundary.
#
# What this hook does:
#   On PreToolUse for the Bash tool, parse the proposed command. When the command
#   shape matches one of the five well-known large-output patterns AND the path or
#   command target carries a security-shaped sentinel (blocklist, firewall, iptables,
#   denylist, allowlist, banlist, ipset, etc. — or sits under a known security path
#   like /etc/banip/, /var/log/, /proc/net/), emit a non-blocking stderr advisory
#   recommending a narrower variant.
#
#   The hook never blocks the command. Exit is always 0. The advisory is informational
#   — the operator can ignore it and continue. The point is to put the recommendation
#   in front of the operator BEFORE the large output exists, not after the session is
#   already wedged.
#
# Detection categories (intentionally narrow to keep false-positive rate low):
#   A) `cat <path>` where path is under /etc/banip/, /var/log/, or ends in .blocklist
#      / .denylist / .allowlist / .banlist / .iplist / .firewall / iptables-save
#   B) `find <broad_path>` without `head`, `tail`, `-print -quit`, or `-quit`
#      (broad recursion on security-shaped paths)
#   C) `journalctl` without `-n`, `--lines`, or `--since` (full system log dump)
#   D) `dmesg` without a pipe to head/tail/wc/grep with a follow-up size cap
#   E) `grep -r` / `grep -R` on a security-shaped path without a pipe to head/tail
#
#   Plus a separate strong-signal path: ANY command (Bash or otherwise) whose
#   argument string contains a sentinel substring from a curated security-content
#   wordlist gets a sentinel-only advisory, on top of the category match.
#
# When this hook does NOT emit anything:
#   - CC_AUP_LARGE_OUTPUT_WARNER_DISABLE=1
#   - CC_AUP_LARGE_OUTPUT_WARNER_QUIET=1
#   - tool_name is not "Bash" (other tools are not parsed by this hook)
#   - command is missing, empty, or unreadable
#   - command already includes a size-cap pipe (head, tail, -n NNN, etc.)
#   - the same command pattern already fired an advisory in this session
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/aup-large-tool-output-warner.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_AUP_LARGE_OUTPUT_WARNER_DISABLE=1     — never emit
#   CC_AUP_LARGE_OUTPUT_WARNER_QUIET=1       — silent
#   CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR=<p> — one-shot state dir (default $HOME/.claude)
#   CC_AUP_LARGE_OUTPUT_WARNER_SESSION_ID=<id> — session id override (tests / automation)
#
# Design notes:
#   - PreToolUse only. The classifier fires on the *output* of the tool call, so by
#     the time PostToolUse runs the damage is done. The advisory has to land before
#     the command executes.
#   - Never blocks. The hook recommends a narrower variant but the operator may have
#     a legitimate reason for the full output (audit, evidence collection, etc.).
#   - One-shot per (session, pattern_hash). If the operator runs `cat
#     /etc/banip/banip.blocklist` three times in a session, only the first call
#     triggers the advisory. This prevents the hook from becoming its own noise loop.
#   - Conservative category set. Five patterns rather than fifteen. A false positive
#     here doesn't break anything (the command still runs), but it does add cognitive
#     load. The set covers #61185's pattern plus the four closest neighbors from
#     #60366's comment chain.
#   - Sentinel wordlist is the high-confidence path. When the command target itself
#     contains "blocklist" / "iptables-save" / etc., the advisory fires even if the
#     command shape isn't on the five-category list — because the sentinel itself
#     carries the cluster-9 trigger signature regardless of how the file is read.

set -u

# Disable path
if [ "${CC_AUP_LARGE_OUTPUT_WARNER_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Quiet path
if [ "${CC_AUP_LARGE_OUTPUT_WARNER_QUIET:-0}" = "1" ]; then
  exit 0
fi

# Read PreToolUse JSON payload from stdin
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

# Parse tool_name and command via jq when available; fall back to grep heuristics.
TOOL_NAME=""
COMMAND=""
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
else
  # Best-effort fallback when jq is unavailable. Match "tool_name": "Bash" and
  # "command": "..." in the JSON payload. This is intentionally lenient — the
  # detection categories below double-check the command shape.
  TOOL_NAME=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  COMMAND=$(printf '%s' "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
fi

# Only act on Bash
[ "$TOOL_NAME" = "Bash" ] || exit 0
[ -n "$COMMAND" ] || exit 0

# Skip if the command already has a size-cap somewhere in the pipeline.
# Common cap shapes: `| head -N`, `| tail -N`, `head -N <file>`, `tail -N <file>`,
# `find ... -print -quit`, `find ... -quit`, `journalctl -n N`, `journalctl --lines N`,
# `journalctl --since ...`, `grep ... | head`, `dmesg | head`, `wc -l`.
if printf '%s' "$COMMAND" | grep -qE '(\|[[:space:]]*head\b|\|[[:space:]]*tail\b|head[[:space:]]+-n[[:space:]]+[0-9]+|tail[[:space:]]+-n[[:space:]]+[0-9]+|head[[:space:]]+-[0-9]+|tail[[:space:]]+-[0-9]+|-print[[:space:]]+-quit\b|[[:space:]]-quit\b|--lines[[:space:]]+[0-9]+|[[:space:]]-n[[:space:]]+[0-9]+|--since\b|\|[[:space:]]*wc\b|^[[:space:]]*wc\b|^[[:space:]]*grep[[:space:]]+-c\b)'; then
  exit 0
fi

# Sentinel wordlist for security-shaped content. Case-insensitive substring match
# against the full command string. These are the substrings that, by themselves,
# strongly indicate the classifier will see the output as "security-shaped."
SENTINEL=""
case " $(printf '%s' "$COMMAND" | tr '[:upper:]' '[:lower:]') " in
  *blocklist*)   SENTINEL="blocklist" ;;
  *denylist*)    SENTINEL="denylist" ;;
  *banlist*)     SENTINEL="banlist" ;;
  *iplist*)      SENTINEL="iplist" ;;
  *iptables-save*) SENTINEL="iptables-save" ;;
  *ipset[[:space:]]save*) SENTINEL="ipset save" ;;
  */etc/banip/*) SENTINEL="/etc/banip/" ;;
  */etc/fail2ban/*) SENTINEL="/etc/fail2ban/" ;;
  */var/log/auth*) SENTINEL="/var/log/auth*" ;;
  */var/log/secure*) SENTINEL="/var/log/secure*" ;;
  *firewall.conf*) SENTINEL="firewall.conf" ;;
esac

# Category match. Even without a sentinel, the following shapes are likely to
# produce large outputs that look security-shaped to the classifier.
CATEGORY=""
CATEGORY_DESC=""
if printf '%s' "$COMMAND" | grep -qE '^[[:space:]]*cat[[:space:]]+(/etc/banip/|/var/log/|/proc/net/)'; then
  CATEGORY="A"
  CATEGORY_DESC="cat on a security-shaped system path"
elif printf '%s' "$COMMAND" | grep -qE '^[[:space:]]*cat[[:space:]]+[^|]*\.(blocklist|denylist|allowlist|banlist|iplist|firewall)([[:space:]]|$)'; then
  CATEGORY="A"
  CATEGORY_DESC="cat on a security-shaped file extension"
elif printf '%s' "$COMMAND" | grep -qE '(^|[[:space:];&|])find[[:space:]]+(/etc/banip/|/var/log/|/proc/net/|/etc/fail2ban/)'; then
  CATEGORY="B"
  CATEGORY_DESC="find recursing under a security-shaped path"
elif printf '%s' "$COMMAND" | grep -qE '(^|[[:space:];&|])journalctl([[:space:]]|$)'; then
  CATEGORY="C"
  CATEGORY_DESC="journalctl without a line/since cap"
elif printf '%s' "$COMMAND" | grep -qE '(^|[[:space:];&|])dmesg([[:space:]]|$)'; then
  CATEGORY="D"
  CATEGORY_DESC="dmesg without a size cap"
elif printf '%s' "$COMMAND" | grep -qE '(^|[[:space:];&|])grep[[:space:]]+(-r|-R|--recursive)[[:space:]]+(.*)(/etc/banip/|/var/log/|/proc/net/|/etc/fail2ban/)'; then
  CATEGORY="E"
  CATEGORY_DESC="grep -r/-R on a security-shaped path"
fi

# If neither a sentinel nor a category match, the command is out of scope.
if [ -z "$SENTINEL" ] && [ -z "$CATEGORY" ]; then
  exit 0
fi

# One-shot per (session, pattern_hash). Pattern hash = first 40 chars of command
# stripped of timestamps and whitespace runs. This keeps the same pattern from
# firing twice in a row (e.g. operator runs the same cat three times) while still
# allowing a different pattern (cat foo.blocklist vs cat bar.denylist) to fire.
STATE_DIR="${CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR:-$HOME/.claude}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="$STATE_DIR/aup-large-tool-output-warner.fired"

SESSION_ID="${CC_AUP_LARGE_OUTPUT_WARNER_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="${CLAUDECODE_SESSION_ID:-}"
fi
if [ -z "$SESSION_ID" ] && command -v tty >/dev/null 2>&1; then
  TTY_PATH=$(tty 2>/dev/null)
  if [ -n "$TTY_PATH" ] && [ "$TTY_PATH" != "not a tty" ]; then
    SESSION_ID=$(printf '%s' "$TTY_PATH" | tr '/' '_')
  fi
fi
[ -n "$SESSION_ID" ] || SESSION_ID="ppid-${PPID:-0}"

# Pattern hash: collapse whitespace, take first 60 chars.
PATTERN_HASH=$(printf '%s' "$COMMAND" | tr -s '[:space:]' ' ' | cut -c1-60 | tr ' /' '__')
FIRED_KEY="${SESSION_ID}::${PATTERN_HASH}"

if [ -f "$STATE_FILE" ] && grep -Fq -- "$FIRED_KEY" "$STATE_FILE" 2>/dev/null; then
  exit 0
fi

# Bound the state file to ~100 lines to avoid unbounded growth.
if [ -f "$STATE_FILE" ]; then
  tail -n 100 "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null \
    && mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
fi
printf '%s\n' "$FIRED_KEY" >> "$STATE_FILE" 2>/dev/null || true

# Compose the advisory.
ADVISORY_REASON=""
if [ -n "$SENTINEL" ] && [ -n "$CATEGORY" ]; then
  ADVISORY_REASON="security-content sentinel \"$SENTINEL\" + $CATEGORY_DESC"
elif [ -n "$SENTINEL" ]; then
  ADVISORY_REASON="security-content sentinel \"$SENTINEL\" in the command"
else
  ADVISORY_REASON="$CATEGORY_DESC"
fi

# Trim command excerpt for the advisory (avoid dumping a 500-char one-liner).
CMD_EXCERPT=$(printf '%s' "$COMMAND" | cut -c1-120)
if [ "${#COMMAND}" -gt 120 ]; then
  CMD_EXCERPT="${CMD_EXCERPT}..."
fi

cat >&2 <<EOF
[aup-large-tool-output-warner] About to run a Bash command that may produce a
large security-shaped output. Trigger: $ADVISORY_REASON.

Command excerpt:
  $CMD_EXCERPT

Why this matters:
  Cluster 9 (Usage Policy classifier over-trigger) has fired on tool results
  carrying high-volume security-shaped content even when the surrounding
  conversation is benign. Issue #61185 documents a session-wedging block
  triggered by a single \`cat /etc/banip/banip.blocklist\` returning ~17,000
  IP entries — after which /compact and /clear also blocked, leaving no
  recovery path within the session.

The command is NOT being blocked. This is an advisory only — the operator may
have a legitimate reason for the full output (audit trail, evidence package,
forensics). If a summary is sufficient, narrower variants reduce the trigger
surface without losing the answer:

  Line count only:    wc -l <path>
  First N lines:      head -200 <path>
  Last N lines:       tail -200 <path>
  Matching subset:    grep -c <pattern> <path>     (count only)
                      grep -E <pattern> <path> | head -200
  journalctl:         journalctl --since "1 hour ago" -n 200
  find:               find <path> -type f | head -200
  dmesg:              dmesg | tail -200

For multi-thousand-entry blocklists, prefer the count + a sampled head/tail
over the full dump.

To silence this advisory for the current session only:
  export CC_AUP_LARGE_OUTPUT_WARNER_QUIET=1

Related hooks (already active in this defense suite):
  aup-false-positive-helper.sh — SessionStart awareness, 4 operator-side options
  aup-block-pattern-logger.sh  — PostToolUse evidence collection
  aup-retry-loop-guard.sh      — PostToolUse intra-session retry breaker
  model-swap-suggester.sh      — SessionStart cross-session swap recommendation

GitHub references:
  https://github.com/anthropics/claude-code/issues/60366  (cluster anchor)
  https://github.com/anthropics/claude-code/issues/61185  (large-output trigger)
EOF

exit 0
