LOGFILE="${HOME}/.claude/worktree-audit.log"
INFO=$(cat)
BRANCH=$(echo "$INFO" | jq -r '.branch // "unknown"' 2>/dev/null)
PATH_WT=$(echo "$INFO" | jq -r '.path // "unknown"' 2>/dev/null)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] CREATE branch=$BRANCH path=$PATH_WT" >> "$LOGFILE"
exit 0
