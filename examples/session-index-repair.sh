#!/bin/bash
# ================================================================
# session-index-repair.sh — Rebuild sessions-index.json on exit
# ================================================================
# PURPOSE:
#   Fixes stale/missing sessions-index.json files that cause
#   `claude --resume` to show old or missing sessions. Runs on
#   session Stop to rebuild the index from actual JSONL files.
#
# TRIGGER: Stop
# MATCHER: (none — Stop has no matcher)
#
# WHY THIS MATTERS:
#   Claude Code writes session data to JSONL files but sometimes
#   fails to update sessions-index.json. Without the index,
#   `claude --resume` can't find recent sessions. This hook
#   scans for JSONL files and rebuilds the index.
#
# OUTPUT:
#   Updated sessions-index.json in the current project directory.
#   Status message to stderr.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/25032
# ================================================================

set -u

# Find the project sessions directory
PROJECT_DIR="${HOME}/.claude/projects"

if [ ! -d "$PROJECT_DIR" ]; then
    exit 0
fi

# Get current working directory's project hash
# Claude Code uses the cwd path (with slashes replaced by dashes) as the project dir name
CWD=$(pwd)
# Convert path to Claude's project directory naming scheme
PROJECT_NAME=$(printf '%s' "$CWD" | sed 's|/|-|g; s|^-||')
SESSION_DIR="${PROJECT_DIR}/${PROJECT_NAME}"

if [ ! -d "$SESSION_DIR" ]; then
    exit 0
fi

INDEX_FILE="${SESSION_DIR}/sessions-index.json"

# Build index from JSONL files
ENTRIES="["
FIRST=true

for jsonl in "${SESSION_DIR}"/*.jsonl; do
    [ -f "$jsonl" ] || continue

    # Extract session info from the JSONL filename and content
    BASENAME=$(basename "$jsonl")
    MTIME=$(stat -c '%Y' "$jsonl" 2>/dev/null || stat -f '%m' "$jsonl" 2>/dev/null)

    # Try to get the session title from custom-title entries
    TITLE=$(grep -o '"type":"custom-title","title":"[^"]*"' "$jsonl" 2>/dev/null | tail -1 | sed 's/.*"title":"//; s/"//')
    if [ -z "$TITLE" ]; then
        # Fallback: use first user message as title
        TITLE=$(head -20 "$jsonl" | grep -o '"role":"user"' -m1 >/dev/null && head -20 "$jsonl" | jq -r 'select(.message.role == "user") | .message.content | .[0:60]' 2>/dev/null | head -1)
    fi
    [ -z "$TITLE" ] && TITLE="(untitled)"

    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        ENTRIES="${ENTRIES},"
    fi

    ENTRIES="${ENTRIES}{\"file\":\"${BASENAME}\",\"title\":\"${TITLE}\",\"mtime\":${MTIME:-0}}"
done

ENTRIES="${ENTRIES}]"

# Write the index
printf '%s' "$ENTRIES" | jq '.' > "$INDEX_FILE" 2>/dev/null

if [ -f "$INDEX_FILE" ]; then
    COUNT=$(printf '%s' "$ENTRIES" | jq 'length' 2>/dev/null)
    printf 'sessions-index.json rebuilt: %s sessions indexed\n' "${COUNT:-0}" >&2
fi

exit 0
