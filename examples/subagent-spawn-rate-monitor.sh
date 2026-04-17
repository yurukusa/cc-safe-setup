#!/bin/bash
# subagent-spawn-rate-monitor.sh — サブエージェントの過剰spawn検知
# Why: サブエージェントは毎回spawnされるたびに~4.7Kトークンがcache_creation
#      (1.25xコスト)として課金される。spawn-heavyなワークフローでは線形に増大し、
#      ユーザーが気づかないうちにquotaを消耗する (#50213, #46968)
# Event: PreToolUse  MATCHER: Agent
# Action: 短時間に多数のAgent spawnがあれば警告

COUNTER_FILE="/tmp/cc-subagent-spawn-counter"
WINDOW_FILE="/tmp/cc-subagent-spawn-window"
THRESHOLD=5      # この回数を超えたら警告
WINDOW_SECS=300  # 5分間のウィンドウ

NOW=$(date +%s)
WINDOW_START=$(cat "$WINDOW_FILE" 2>/dev/null || echo "$NOW")
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")

# ウィンドウ期限切れならリセット
ELAPSED=$((NOW - WINDOW_START))
if [ "$ELAPSED" -gt "$WINDOW_SECS" ]; then
  COUNT=0
  echo "$NOW" > "$WINDOW_FILE"
fi

COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

if [ "$COUNT" -gt "$THRESHOLD" ]; then
  echo "⚠ HIGH SUBAGENT SPAWN RATE: $COUNT agents spawned in ${ELAPSED}s" >&2
  echo "Each spawn costs ~4.7K tokens at 1.25x rate (no cache_control)." >&2
  echo "Consider batching tasks or using fewer parallel agents. See: #50213" >&2
fi

exit 0
