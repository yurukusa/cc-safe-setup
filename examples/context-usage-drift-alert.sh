#!/bin/bash
# context-usage-drift-alert.sh — コンテキスト使用率の急増を検知
# Why: 1Mコンテキストモデルで実際124%使用中にUI上60%と表示される問題 (#50204)。
#      予告なくauto-compactが発火してコンテキストが消失する。
#      ツール呼び出し回数でコンテキスト消費を推定し、警告する。
# Event: PostToolUse  MATCHER: ""
# Action: セッション内のツール呼び出し回数が閾値を超えたら警告

COUNTER_FILE="/tmp/cc-context-usage-counter-$$"
# セッションPIDが変わると新しいカウンターになる
# フォールバック: 親PIDでグループ化
if [ ! -f "$COUNTER_FILE" ]; then
  COUNTER_FILE="/tmp/cc-context-usage-counter-$(date +%Y%m%d)"
fi

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# 50回: 注意喚起、100回: 強い警告、150回: compact推奨
if [ "$COUNT" -eq 50 ]; then
  echo "📊 Session checkpoint: $COUNT tool calls. Context may be growing large." >&2
  echo "Run /cost to check actual usage. UI display may undercount by 2x (#50204)." >&2
elif [ "$COUNT" -eq 100 ]; then
  echo "⚠ HIGH CONTEXT USAGE: $COUNT tool calls this session." >&2
  echo "UI may show ~50% when actual usage is near 100%. Consider /compact." >&2
  echo "Unexpected auto-compact can erase your working context. See: #50204" >&2
elif [ "$COUNT" -eq 150 ]; then
  echo "🚨 VERY HIGH CONTEXT: $COUNT tool calls. Auto-compact likely imminent." >&2
  echo "Save important state to files NOW. Run /compact manually to control what's kept." >&2
fi

exit 0
