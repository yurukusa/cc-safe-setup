#!/bin/bash
# worktree-branch-pollution-detector.sh — worktreeが親ブランチを汚染していないか検知
# Why: サブエージェントのworktree操作が親リポを予期しないブランチに移動させ、
#      意図しないcommit-to-mainが発生する。1週間で3回の事故報告あり (#50207)
# Event: PostToolUse  MATCHER: Bash
# Action: 現在のブランチが期待値と異なる場合に警告

INPUT=$(cat)

# 期待ブランチ（セッション開始時に記録）
EXPECTED_BRANCH_FILE="/tmp/cc-expected-branch-$(pwd | md5sum | cut -c1-8)"

# git管理下でなければスキップ
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
[ -z "$CURRENT_BRANCH" ] && exit 0

# 初回実行時はブランチを記録
if [ ! -f "$EXPECTED_BRANCH_FILE" ]; then
  echo "$CURRENT_BRANCH" > "$EXPECTED_BRANCH_FILE"
  exit 0
fi

EXPECTED_BRANCH=$(cat "$EXPECTED_BRANCH_FILE" 2>/dev/null)

if [ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]; then
  echo "⚠ BRANCH CHANGED: Expected '$EXPECTED_BRANCH' but now on '$CURRENT_BRANCH'" >&2
  echo "This may be caused by a worktree or subagent switching your branch." >&2
  echo "Run 'git checkout $EXPECTED_BRANCH' to return. See: #50207" >&2
  # 新しいブランチを記録（意図的な切替かもしれない）
  echo "$CURRENT_BRANCH" > "$EXPECTED_BRANCH_FILE"
fi

exit 0
