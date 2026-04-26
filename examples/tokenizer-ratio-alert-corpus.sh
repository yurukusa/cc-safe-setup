#!/bin/bash
# tokenizer-ratio-alert-corpus.sh — 個人 corpus の input_tokens/character_count 比率 drift を検知 (PostToolUse rolling baseline 方式)
# 関連: examples/tokenizer-ratio-alert.sh は同名異設計の PreToolUse + Anthropic API count_tokens 経由版 (Postmortems Incident 5)
# Why: Anthropic がトークナイザーを silent に変更 (#46829 関連、Opus 4.7 で 1.35-1.46× インフレ実測 Simon Willison 2026-04-20)。
#      個人の corpus に対し input_tokens / character_count を 7日 rolling baseline と比較、
#      1.25× threshold を 3 連続 session で超えたら alert。
#      Migration Playbook Chapter 4 (Path A Stay-and-Fortify) Hook 6 specification 実装。
# Event: PostToolUse  MATCHER: ""
# Action: 各 turn の input_tokens を log、baseline drift 検知時に stderr alert (non-blocking)

HISTORY="/tmp/cc-tokenizer-ratio-history"
SESSION_FLAG="/tmp/cc-tokenizer-ratio-session"
TODAY=$(date +%Y-%m-%d)

# stdin から JSON を取得 (Claude Code PostToolUse hook input)
INPUT=$(cat 2>/dev/null || echo "{}")

# tool_input から approximate character count を計算 (text-like fields の長さ合計)
CHARS=$(echo "$INPUT" | jq -r '
  .tool_input // {} |
  [.. | strings] |
  map(length) |
  add // 0
' 2>/dev/null)

# tool_response から input_tokens を取得 (利用可能な場合)
TOKENS=$(echo "$INPUT" | jq -r '
  .tool_response // {} |
  .usage.input_tokens //
  .input_tokens //
  0
' 2>/dev/null)

# どちらかが 0 なら処理中断 (signal 不足、log 汚染防止)
[ -z "$CHARS" ] || [ "$CHARS" = "0" ] && exit 0
[ -z "$TOKENS" ] || [ "$TOKENS" = "0" ] && exit 0

# 比率計算 (tokens / chars)
RATIO=$(awk "BEGIN { printf \"%.4f\", $TOKENS / $CHARS }")

# log: timestamp|date|tokens|chars|ratio
echo "$(date +%s)|$TODAY|$TOKENS|$CHARS|$RATIO" >> "$HISTORY"

# 7日 rolling baseline 計算 (8日以上前は除外、POSIX awk safe で mean 採用)
SEVEN_DAYS_AGO=$(date -d "7 days ago" +%s 2>/dev/null || date -v-7d +%s 2>/dev/null)
[ -z "$SEVEN_DAYS_AGO" ] && exit 0

BASELINE=$(awk -F'|' -v cutoff="$SEVEN_DAYS_AGO" '
  $1 >= cutoff { sum += $5; n++ }
  END {
    if (n < 50) exit 1  # baseline 未確立 (50 turn 未満)
    print sum / n
  }
' "$HISTORY" 2>/dev/null)

# baseline 未確立時は exit (50 turn 蓄積待ち、blocking なし)
[ -z "$BASELINE" ] && exit 0

# 1.25× threshold チェック
THRESHOLD=$(awk "BEGIN { printf \"%.4f\", $BASELINE * 1.25 }")
EXCEEDS=$(awk "BEGIN { print ($RATIO > $THRESHOLD) ? 1 : 0 }")

# 3 連続 session 超過判定
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
LAST_SESSION=$(head -1 "$SESSION_FLAG" 2>/dev/null | cut -d'|' -f1)
EXCEED_COUNT=$(head -1 "$SESSION_FLAG" 2>/dev/null | cut -d'|' -f2)
EXCEED_COUNT=${EXCEED_COUNT:-0}

if [ "$EXCEEDS" = "1" ]; then
  if [ "$LAST_SESSION" != "$SESSION_ID" ]; then
    EXCEED_COUNT=$((EXCEED_COUNT + 1))
    echo "$SESSION_ID|$EXCEED_COUNT" > "$SESSION_FLAG"
  fi
  if [ "$EXCEED_COUNT" -ge 3 ]; then
    echo "[tokenizer-ratio-alert-corpus] tokens/chars ratio ${RATIO} exceeds 1.25x baseline (${BASELINE}) for ${EXCEED_COUNT} consecutive sessions. Tokenizer may have shifted (Issue #46829 / Opus 4.7 inflation pattern). Review your /usage --json output." >&2
  fi
else
  # 比率正常 = 連続カウンタ reset
  echo "$SESSION_ID|0" > "$SESSION_FLAG"
fi

exit 0
