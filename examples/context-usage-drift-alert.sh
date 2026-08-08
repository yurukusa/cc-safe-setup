#!/bin/bash
# context-usage-drift-alert.sh — コンテキスト使用率の急増を検知
# Why: 1Mコンテキストモデルで実際124%使用中にUI上60%と表示される問題 (#50204)。
#      予告なくauto-compactが発火してコンテキストが消失する。
#      ツール呼び出し回数でコンテキスト消費を推定し、警告する。
# Event: PostToolUse  MATCHER: ""
# Action: セッション内のツール呼び出し回数が閾値を超えたら警告
#
# 2026-08-09 修正: カウンターがセッション単位で分かれていなかった。
#   旧実装は "/tmp/cc-context-usage-counter-$$" を先に見ていたが、$$ は
#   このスクリプト自身のPIDで**呼び出しごとに変わる**ため、そのファイルは
#   決して存在せず、常に日付単位のフォールバックへ落ちていた。
#   結果、カウンターはその日の全セッションで共有され、しかも判定が -eq の
#   完全一致だったので、150を一度超えると**その日はもう二度と鳴らなかった**。
#   実測(隔離HOME): 160回呼ぶと 50/100/150 で3回発火するが、続けて別セッション
#   相当の160回を呼ぶと発火は0回(カウンターは160→320と進むだけ)。
#   自律運用では1日に何本もセッションが立つので、2本目以降は無警告だった。
#   修正: hookの入力JSONの session_id でカウンターを分ける。閾値の判定は
#   「跨いだ回だけ鳴らす」形にして、-eq の取りこぼしも塞ぐ。

INPUT=$(cat 2>/dev/null)
SESSION_ID=""
if [ -n "$INPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // .sessionId // empty' 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    SESSION_ID=$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("session_id") or d.get("sessionId") or "")' 2>/dev/null)
  fi
fi

# session_id が取れない場合だけ日付へ落ちる。落ちたことが分かるよう接尾辞を分ける
# (旧実装はここが既定になっていて、しかも黙っていた)
if [ -n "$SESSION_ID" ]; then
  KEY=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)
else
  KEY="nosession-$(date +%Y%m%d)"
fi
COUNTER_FILE="/tmp/cc-context-usage-counter-$KEY"

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
PREV=$COUNT
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# 閾値を「跨いだ」回だけ鳴らす。PostToolUse が数を飛ばしても取りこぼさない
crossed() { [ "$PREV" -lt "$1" ] && [ "$COUNT" -ge "$1" ]; }

if crossed 150; then
  echo "🚨 VERY HIGH CONTEXT: $COUNT tool calls. Auto-compact likely imminent." >&2
  echo "Save important state to files NOW. Run /compact manually to control what's kept." >&2
elif crossed 100; then
  echo "⚠ HIGH CONTEXT USAGE: $COUNT tool calls this session." >&2
  echo "UI may show ~50% when actual usage is near 100%. Consider /compact." >&2
  echo "Unexpected auto-compact can erase your working context. See: #50204" >&2
elif crossed 50; then
  echo "📊 Session checkpoint: $COUNT tool calls. Context may be growing large." >&2
  echo "Run /cost to check actual usage. UI display may undercount by 2x (#50204)." >&2
fi

exit 0
