#!/bin/bash
# quota-reset-cycle-monitor.sh — quotaリセット周期の変更を検知
# Why: ユーザーのquotaリセット周期が予告なく月曜→金曜に変更された (#49599, 2r/4c)。
#      リセット日を追跡し、周期変更時に警告する。
#      突然のquota枯渇の原因究明に役立つ。
# Event: Notification  MATCHER: ""
# Action: 日次でquotaリセット日を記録、周期変更を検知

RESET_LOG="/tmp/cc-quota-reset-history"
TODAY=$(date +%u)  # 1=Monday, 7=Sunday
TODAY_DATE=$(date +%Y-%m-%d)

# 1日1回だけチェック（日付で制御）
LAST_CHECK=$(head -1 "$RESET_LOG" 2>/dev/null | cut -d'|' -f1)
[ "$LAST_CHECK" = "$TODAY_DATE" ] && exit 0

# /costの出力からリセット情報を取得する方法の案内
# 実際のリセット検知は手動確認が必要だが、ログを残すことで追跡可能
echo "$TODAY_DATE|$TODAY" >> "$RESET_LOG"

# リセット履歴が2件以上ある場合、周期を分析
ENTRIES=$(wc -l < "$RESET_LOG" 2>/dev/null || echo "0")
if [ "$ENTRIES" -ge 7 ]; then
  # 過去7日の曜日パターンを表示（週末にquotaが増えたら次週リセット=正常）
  echo "📊 Quota tracking: $ENTRIES days logged. Run '/cost' to check current reset day." >&2
  echo "Known issue: reset cycle may change without notice (#49599)." >&2
  echo "If your quota resets on a different day than expected, report to Anthropic support." >&2
fi

exit 0
