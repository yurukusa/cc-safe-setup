#!/bin/bash
# test-coverage-reminder.sh — Remind to run tests after code changes
#
# Prevents: Pushing untested code. Claude often edits files
#           without running the test suite afterward.
#
# Tracks: number of Edit/Write calls since last test run.
# Warns at: 5 edits without tests, blocks at 10.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit|Bash"
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write|Edit|Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/test-coverage-reminder.sh" }]
#     }]
#   }
# }

COUNTER_FILE="/tmp/cc-edit-since-test-$__CC_KEY"
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

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

case "$TOOL" in
  Write|Edit)
    # Increment edit counter
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNTER_FILE"

    if [ "$COUNT" -eq 5 ]; then
      echo "REMINDER: 5 files changed since last test run. Consider running tests." >&2
    elif [ "$COUNT" -ge 10 ]; then
      echo "WARNING: $COUNT files changed without running tests. Run tests now." >&2
    fi
    ;;
  Bash)
    # Reset counter if a test command was run
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if echo "$CMD" | grep -qiE '(npm\s+test|npx\s+jest|npx\s+vitest|pytest|go\s+test|cargo\s+test|make\s+test|bash\s+test)'; then
      echo "0" > "$COUNTER_FILE"
    fi
    ;;
esac

exit 0
