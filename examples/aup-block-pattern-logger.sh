#!/bin/bash
# aup-block-pattern-logger.sh — Persist Usage Policy classifier blocks across sessions
#
# Background:
#   Starting 2026-05-18, the Anthropic server-side Usage Policy classifier began
#   over-triggering on benign Claude Code prompts. The block surfaces as one of two
#   stock error strings in tool output:
#     "API Error: Claude Code is unable to respond to this request, which appears to
#      violate our Usage Policy (...). This request triggered cyber-related safeguards."
#   or:
#     "This request triggered safety guardrails. Rephrase your prompt or rewind to continue."
#
#   The classifier is non-deterministic and shifts over time. 25+ open issues filed
#   between 2026-05-18 and 2026-05-27 across English, Russian, Polish, and Spanish
#   input. The operator has no first-class way to:
#     - reconstruct which sessions hit the block and on what model,
#     - build evidence for a CVP application showing block frequency,
#     - notice when the classifier shifts (drop in block rate / rise after an update).
#
#   The partner hook aup-false-positive-helper.sh surfaces the four operator-side
#   workarounds at SessionStart. This logger pairs with it by recording each block
#   event PostToolUse, so the operator can review block history later.
#
#   Reference: https://gist.github.com/yurukusa/4fa4751044be45bd83345601ee79c2db
#
# What this hook does:
#   On PostToolUse, scan tool output for AUP-block patterns. When a block is
#   detected, append one line to a persistent log:
#     TIMESTAMP|MODEL|TOOL|PATTERN_KIND|EXCERPT
#   Default log path: ~/.claude/aup-block-history.log
#
#   Pattern kinds emitted:
#     cyber-safeguards   — "triggered cyber-related safeguards"
#     usage-policy       — "violate our Usage Policy"
#     safety-guardrails  — "triggered safety guardrails"
#     rephrase-rewind    — "Rephrase your prompt or rewind to continue"
#     usage-policy-api   — "API Error: ... unable to respond"  (fallback)
#
#   By default, a one-line stderr advisory prints the running block count for the
#   current ANTHROPIC_MODEL (or "default-routing" when unset). Silent when no
#   block is detected.
#
# When this hook does NOT log or warn:
#   - CC_AUP_BLOCK_LOGGER_DISABLE=1
#   - tool output is empty or unparseable
#   - no AUP block pattern matched
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/aup-block-pattern-logger.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_AUP_BLOCK_LOGGER_DISABLE=1        — never log, never warn
#   CC_AUP_BLOCK_LOGGER_QUIET=1          — log silently (no stderr advisory)
#   CC_AUP_BLOCK_LOG_PATH=<path>         — override default log path
#   CC_AUP_BLOCK_LOGGER_MAX_LINES=<n>    — log rotation threshold (default 500)
#
# Output schema (one line per block):
#   ISO8601_UTC | ANTHROPIC_MODEL or "default-routing" | TOOL_NAME | PATTERN_KIND | up-to-120-char excerpt
#
# Privacy: only the pattern kind and a short excerpt are recorded. No prompt content,
# no tool input, no file paths beyond the tool name. The excerpt is the matched line.
#
# The registration was missing from this header. The installer reads TRIGGER
# and MATCHER from here and falls back to PreToolUse / Bash when both are
# absent, so this hook was being registered at a moment where the field it
# reads is always empty: it installed, it appeared in the settings, and it
# did nothing. Measured 2026-08-04 across examples/: 14 files were like this.
# TRIGGER: PostToolUse
# MATCHER: ""

set -u

# Disable path
if [ "${CC_AUP_BLOCK_LOGGER_DISABLE:-0}" = "1" ]; then
  exit 0
fi

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# Extract tool name and output; fall back to grep if jq is missing.
if command -v jq >/dev/null 2>&1; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
  OUTPUT=$(printf '%s' "$INPUT" | jq -r '.tool_output // .tool_response // empty' 2>/dev/null || echo "")
else
  TOOL=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
  OUTPUT="$INPUT"
fi

[ -z "$OUTPUT" ] && exit 0
[ -z "$TOOL" ] && TOOL="unknown-tool"

# Match patterns in priority order. The first match wins so the recorded kind is
# the most specific signal available.
PATTERN_KIND=""
EXCERPT=""
match_pattern() {
  local label="$1"
  local regex="$2"
  local line
  line=$(printf '%s' "$OUTPUT" | grep -iE "$regex" | head -1)
  if [ -n "$line" ]; then
    PATTERN_KIND="$label"
    EXCERPT=$(printf '%s' "$line" | tr -d '|\n\r' | head -c 120)
    return 0
  fi
  return 1
}

match_pattern "cyber-safeguards"  "triggered cyber-related safeguards" \
  || match_pattern "safety-guardrails" "triggered safety guardrails" \
  || match_pattern "rephrase-rewind"   "Rephrase your prompt or rewind to continue" \
  || match_pattern "usage-policy"      "violate our Usage Policy" \
  || match_pattern "usage-policy-api"  "API Error.*unable to respond to this request"

# No match → silent exit (the overwhelming common case).
[ -z "$PATTERN_KIND" ] && exit 0

LOG_PATH="${CC_AUP_BLOCK_LOG_PATH:-$HOME/.claude/aup-block-history.log}"
LOG_DIR=$(dirname "$LOG_PATH")
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

MODEL="${ANTHROPIC_MODEL:-default-routing}"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Append; never block on log failure.
printf '%s|%s|%s|%s|%s\n' "$TIMESTAMP" "$MODEL" "$TOOL" "$PATTERN_KIND" "$EXCERPT" >> "$LOG_PATH" 2>/dev/null || true

# Rotate when the log exceeds the configured threshold. Keep the most recent half.
MAX_LINES="${CC_AUP_BLOCK_LOGGER_MAX_LINES:-500}"
if [ -f "$LOG_PATH" ]; then
  CURRENT_LINES=$(wc -l < "$LOG_PATH" 2>/dev/null || echo 0)
  if [ "$CURRENT_LINES" -gt "$MAX_LINES" ] 2>/dev/null; then
    KEEP=$((MAX_LINES / 2))
    [ "$KEEP" -lt 1 ] && KEEP=1
    tail -n "$KEEP" "$LOG_PATH" > "${LOG_PATH}.tmp" 2>/dev/null && mv "${LOG_PATH}.tmp" "$LOG_PATH" 2>/dev/null || true
  fi
fi

# Stderr advisory unless explicitly silenced. Show the running count for the
# current model so the operator notices when frequency rises.
if [ "${CC_AUP_BLOCK_LOGGER_QUIET:-0}" != "1" ]; then
  MODEL_COUNT=$(grep -c "|${MODEL}|" "$LOG_PATH" 2>/dev/null || echo 0)
  cat >&2 <<EOF
[aup-block-pattern-logger] Usage Policy block detected (kind=$PATTERN_KIND, tool=$TOOL).
  Model: $MODEL    Cumulative blocks logged for this model: $MODEL_COUNT
  Log: $LOG_PATH
  Workarounds: enable CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 with aup-false-positive-helper.sh,
    or swap to a Sonnet variant (export ANTHROPIC_MODEL=claude-sonnet-4-7) for sensitive prompts.
  Silence this advisory: export CC_AUP_BLOCK_LOGGER_QUIET=1
EOF
fi

exit 0
