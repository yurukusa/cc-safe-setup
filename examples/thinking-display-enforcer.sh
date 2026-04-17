#!/bin/bash
# thinking-display-enforcer.sh — Opus 4.7 thinking summaries消失を検知
# Why: Opus 4.7でthinking displayのデフォルトがsummarized→omittedに変更された(#49268, 17👍)
# セッション開始時にモデルを確認し、Opus 4.7でthinkingが非表示の場合に警告する
# Event: Notification (セッション開始時に確認)
# Fix: claude --thinking-display summarized

# チェック頻度制御（100回に1回）
COUNTER_FILE="/tmp/thinking-display-check-counter"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
[ $((COUNT % 100)) -ne 1 ] && exit 0

# settings.jsonにthinking display設定があるか確認
SETTINGS_FILE="${HOME}/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    HAS_THINKING=$(grep -c "showThinkingSummaries\|thinkingDisplay" "$SETTINGS_FILE" 2>/dev/null || echo "0")
    if [ "$HAS_THINKING" -eq 0 ]; then
        echo "INFO: Opus 4.7ではthinking summariesがデフォルトで非表示です。" >&2
        echo "修正: claude --thinking-display summarized で起動するか、settings.jsonに設定を追加してください。" >&2
        echo "詳細: https://github.com/anthropics/claude-code/issues/49268" >&2
    fi
fi
exit 0
