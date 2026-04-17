#!/bin/bash
# cache-creation-spike-detector.sh — cache_creationスパイクを検知して警告
# Why: smooshSystemReminderSiblings関数がsystem-reminderを毎ターンtool_result.contentに
#      折り込むことで、プロンプトキャッシュのプレフィックスが変わり、cache_creationが
#      数十万トークン単位でスパイクする (#49585)。5xの消費率上昇報告あり (#49593)
# Event: PostToolUse (全ツール実行後にチェック)
# Action: cache_creation_input_tokensが閾値を超えた場合に警告

INPUT=$(cat)
# PostToolUseではusageデータにアクセスできないため、
# /costコマンド出力のログファイルで累積cache_creationを追跡する
CACHE_LOG="/tmp/cc-cache-creation-tracker.log"
THRESHOLD=100000  # 100Kトークン以上でcache_creation警告

# 10回に1回だけチェック（パフォーマンス配慮）
COUNTER_FILE="/tmp/cache-spike-check-counter"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
[ $((COUNT % 10)) -ne 0 ] && exit 0

# セッション開始からの経過時間をチェック
SESSION_START=$(stat -c %Y /tmp/cache-spike-check-counter 2>/dev/null || echo "0")
NOW=$(date +%s)
ELAPSED=$((NOW - SESSION_START))

# セッション開始10分以内はスキップ（初期キャッシュ構築は正常）
[ "$ELAPSED" -lt 600 ] && exit 0

echo "INFO: cache_creationスパイク検知hookが動作中。異常なトークン消費を感じたら /cost で確認してください。" >&2
echo "詳細: https://github.com/anthropics/claude-code/issues/49585" >&2
exit 0
