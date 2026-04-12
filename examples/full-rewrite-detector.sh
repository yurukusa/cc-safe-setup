#!/bin/bash
# ================================================================
# full-rewrite-detector.sh — Warn on full-file rewrites
# ================================================================
# PURPOSE:
#   Claude Code sometimes rewrites entire files when a small edit
#   would suffice. AMD's analysis of 6,852 sessions found this
#   pattern increasing over time — a sign of quality degradation.
#   This hook detects when >80% of a file's lines were changed
#   and warns the user.
#
# TRIGGER: PostToolUse
# MATCHER: "Write"
#
# HOW IT WORKS:
#   After a Write operation, checks git diff for the target file.
#   If the ratio of changed lines to total lines exceeds the
#   threshold (default 80%), emits a warning.
#
# CONFIGURATION:
#   CC_REWRITE_THRESHOLD=80  — percentage threshold (default 80)
#
# NOTE: Only works in git repositories. No-op outside git repos.
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Skip if no file path
[ -z "$FILE" ] && exit 0

# Skip if not in a git repo
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# Skip if file doesn't exist (new file creation is fine)
[ -f "$FILE" ] || exit 0

# Get change stats from git
STATS=$(git diff --numstat -- "$FILE" 2>/dev/null)
[ -z "$STATS" ] && exit 0

ADDED=$(echo "$STATS" | awk '{print $1}')
DELETED=$(echo "$STATS" | awk '{print $2}')

# Handle binary files (git outputs "-" for binary)
[ "$ADDED" = "-" ] && exit 0

CHANGED=$((ADDED + DELETED))
TOTAL=$(wc -l < "$FILE" 2>/dev/null || echo 0)

# Avoid division by zero; skip very small files
[ "$TOTAL" -lt 5 ] && exit 0

RATIO=$((CHANGED * 100 / TOTAL))
THRESHOLD=${CC_REWRITE_THRESHOLD:-80}

if [ "$RATIO" -gt "$THRESHOLD" ]; then
    echo "WARNING: Full rewrite detected on $(basename "$FILE")" >&2
    echo "  ${RATIO}% of lines changed (${CHANGED} lines changed / ${TOTAL} total)" >&2
    echo "  Consider: was a partial edit sufficient?" >&2
fi

exit 0
