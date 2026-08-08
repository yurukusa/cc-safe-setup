#!/bin/bash
# ================================================================
# api-rate-limit-guard.sh — Throttle rapid API calls to prevent rate limiting
# ================================================================
# PURPOSE:
#   Claude often makes rapid successive curl/API calls that trigger
#   rate limits (429 Too Many Requests). This hook tracks the last
#   call time and enforces a minimum interval between API requests.
#
#   Default: 1 second between curl/wget/httpie calls.
#   Customize MIN_INTERVAL_MS for your API's rate limit.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(curl *)",
#         "command": "~/.claude/hooks/api-rate-limit-guard.sh"
#       }]
#     }]
#   }
# }
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-api-rate-limit-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [api-rate-limit-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
__CC_HOOK_INPUT="$INPUT"
# --- セッション識別子でファイルを分ける (2026-08-09 修正) ---
# 旧実装は "$$" を使っていたが、$$ はこのスクリプト自身のPIDで呼び出しごとに変わるため、
# 状態が一度も持続しなかった(実測: 200回呼ぶとファイルが200個でき、中身は全部 1)。
__CC_SID=""
if [ -n "${__CC_HOOK_INPUT:-}" ]; then
  if command -v jq >/dev/null 2>&1; then
    __CC_SID=$(printf '%s' "$__CC_HOOK_INPUT" | jq -r '.session_id // .sessionId // empty' 2>/dev/null)
  fi
  if [ -z "$__CC_SID" ] && command -v python3 >/dev/null 2>&1; then
    __CC_SID=$(printf '%s' "$__CC_HOOK_INPUT" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("session_id") or d.get("sessionId") or "")
except Exception: print("")' 2>/dev/null)
  fi
fi
if [ -n "$__CC_SID" ]; then
  __CC_KEY=$(printf '%s' "$__CC_SID" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)
else
  __CC_KEY="nosession-$(date +%Y%m%d)"
fi
# --- ここまで ---

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check HTTP client commands
echo "$COMMAND" | grep -qE '^\s*(curl|wget|http|https)\s' || exit 0

# Configurable minimum interval (milliseconds)
MIN_INTERVAL_MS="${CC_API_RATE_LIMIT_MS:-1000}"

TIMESTAMP_FILE="/tmp/.cc-api-rate-limit-$__CC_KEY"
NOW_MS=$(date +%s%N | cut -b1-13 2>/dev/null || date +%s)

if [ -f "$TIMESTAMP_FILE" ]; then
    LAST_MS=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "0")
    DIFF=$((NOW_MS - LAST_MS))
    if [ "$DIFF" -lt "$MIN_INTERVAL_MS" ] 2>/dev/null; then
        WAIT=$((MIN_INTERVAL_MS - DIFF))
        echo "⚠ Rate limit guard: ${WAIT}ms cooldown remaining." >&2
        echo "  Set CC_API_RATE_LIMIT_MS to adjust (current: ${MIN_INTERVAL_MS}ms)." >&2
        # Note: exit 0 = warn only. Change to exit 2 to hard-block.
    fi
fi

echo "$NOW_MS" > "$TIMESTAMP_FILE"
exit 0
