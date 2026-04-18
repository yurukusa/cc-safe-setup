#!/bin/bash
# model-version-change-alert.sh — モデルバージョン変更を検知して警告
# Why: Opus 4.6がモデルピッカーから突然削除された (#49689, 14👍)。
#      ユーザーが意図せず別モデルに切り替えられるケースが多発。
#      モデルが変わるとhookの挙動・トークン消費・品質が全て変わる。
# Event: Notification  MATCHER: ""
# Action: 前回のモデルと現在のモデルを比較し、変更時に警告

MODEL_HISTORY="/tmp/cc-model-version-history"
CURRENT_MODEL="${CLAUDE_MODEL:-unknown}"

# Notificationイベントのbodyからモデル情報を取得試行
if [ -n "$1" ]; then
  BODY_MODEL=$(echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('model',''))" 2>/dev/null)
  [ -n "$BODY_MODEL" ] && CURRENT_MODEL="$BODY_MODEL"
fi

# 前回のモデルを読み取り
PREV_MODEL=$(cat "$MODEL_HISTORY" 2>/dev/null || echo "")

if [ -n "$PREV_MODEL" ] && [ "$PREV_MODEL" != "$CURRENT_MODEL" ] && [ "$CURRENT_MODEL" != "unknown" ]; then
  echo "⚠ MODEL CHANGED: $PREV_MODEL → $CURRENT_MODEL" >&2
  echo "Your model was switched. This affects token consumption, quality, and hook behavior." >&2
  echo "If unintended, check your settings: claude --model $PREV_MODEL" >&2
  echo "Known issue: Opus 4.6 was removed from the Desktop picker (#49689)" >&2
fi

# 現在のモデルを記録
[ "$CURRENT_MODEL" != "unknown" ] && echo "$CURRENT_MODEL" > "$MODEL_HISTORY"

exit 0
