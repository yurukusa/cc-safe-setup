#!/bin/bash
# ================================================================
# session-duration-guard.sh — Warn on long-running sessions
# ================================================================
# PURPOSE:
#   Model quality degrades in very long sessions due to context
#   accumulation, compaction artifacts, and attention dilution.
#   This hook warns at configurable thresholds and suggests
#   saving state + starting fresh.
#
#   Based on 700+ hours of autonomous operation experience.
#
# TRIGGER: PostToolUse
# MATCHER: ""  (all tools)
#
# CONFIG:
#   CC_SESSION_WARN_HOURS=2  (warn after 2 hours, default)
#   CC_SESSION_CRITICAL_HOURS=4  (critical after 4 hours, default)
# ================================================================

__CC_HOOK_INPUT=$(cat 2>/dev/null)
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

MARKER="/tmp/cc-session-start-$__CC_KEY"
WARN_HOURS="${CC_SESSION_WARN_HOURS:-2}"
CRITICAL_HOURS="${CC_SESSION_CRITICAL_HOURS:-4}"

# Create marker on first run
if [ ! -f "$MARKER" ]; then
    date +%s > "$MARKER"
    exit 0
fi

# Check every 50 tool calls (not every call)
COUNTER="/tmp/cc-duration-counter-$__CC_KEY"
COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER"
[ $((COUNT % 50)) -ne 0 ] && exit 0

START=$(cat "$MARKER" 2>/dev/null || echo 0)
NOW=$(date +%s)
ELAPSED=$(( (NOW - START) / 3600 ))
ELAPSED_MIN=$(( (NOW - START) / 60 ))

if [ "$ELAPSED" -ge "$CRITICAL_HOURS" ]; then
    echo "⚠ CRITICAL: Session running for ${ELAPSED_MIN} minutes (${ELAPSED}+ hours)." >&2
    echo "  Model quality typically degrades after ${CRITICAL_HOURS} hours." >&2
    echo "  Save your state and start a new session: /compact then resume later." >&2
elif [ "$ELAPSED" -ge "$WARN_HOURS" ]; then
    echo "NOTE: Session running for ${ELAPSED_MIN} minutes. Consider saving state." >&2
fi

exit 0
