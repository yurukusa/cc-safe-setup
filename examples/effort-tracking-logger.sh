#!/bin/bash
# effort-tracking-logger.sh — ツール使用ごとのエフォートログを記録
# Why: OTEL互換のエフォート追跡への要望が急増 (#49893, 18👍)。
#      公式対応を待たずに、hookでツール呼び出しごとのログを残す。
#      コスト分析・セッション振り返り・ボトルネック特定に使える。
# Event: PostToolUse  MATCHER: ""
# Output: ~/.claude/effort-log/YYYY-MM-DD.jsonl

LOG_DIR="${HOME}/.claude/effort-log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"

# stdinからツール情報を取得
TOOL_INPUT=$(cat)
TOOL_NAME=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null)
TOOL_STATUS=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('was_error','false'))" 2>/dev/null)

# JSONLログに追記
python3 -c "
import json, datetime
entry = {
    'timestamp': datetime.datetime.now().isoformat(),
    'tool': '$TOOL_NAME',
    'error': '$TOOL_STATUS' == 'true',
    'session_pid': $(echo $$)
}
print(json.dumps(entry))
" >> "$LOG_FILE"

exit 0
