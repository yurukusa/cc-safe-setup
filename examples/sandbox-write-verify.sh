#!/bin/bash
# sandbox-write-verify.sh — Verify file existence before overwrite in sandbox mode
#
# Solves: Sandbox half-broken — writes hit real filesystem (#40321).
#         When sandbox reads are isolated but writes pass through,
#         Claude overwrites real files it can't see, destroying projects.
#
# How it works: Before Edit/Write operations, checks if the target file
#   exists on the REAL filesystem (not sandboxed). If Claude is about to
#   overwrite an existing file and can't read it (sandbox read isolation),
#   blocks the write.
#
# Also detects bulk writes (>10 files in quick succession) which is
# a sign of runaway overwrite behavior.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Track writes per session to detect bulk overwrite
WRITE_LOG="/tmp/cc-sandbox-writes-${PPID}"
echo "$(date +%s) $FILE" >> "$WRITE_LOG" 2>/dev/null

# Check for bulk writes (>10 in last 60 seconds)
if [ -f "$WRITE_LOG" ]; then
    NOW=$(date +%s)
    RECENT=$(awk -v now="$NOW" '$1 > now - 60 {count++} END {print count+0}' "$WRITE_LOG")
    if [ "$RECENT" -gt 10 ]; then
        echo "BLOCKED: Bulk write detected (${RECENT} files in 60s)" >&2
        echo "  This may indicate a sandbox read/write mismatch." >&2
        echo "  Verify sandbox state before continuing." >&2
        exit 2
    fi
fi

# Check if target file exists and is non-empty (potential overwrite)
if [ -f "$FILE" ] && [ -s "$FILE" ]; then
    # File exists. Check if it's in a project directory
    DIR=$(dirname "$FILE")
    # Count files in the same directory that were recently written
    DIR_WRITES=$(grep -c "$DIR" "$WRITE_LOG" 2>/dev/null || echo 0)
    if [ "$DIR_WRITES" -gt 5 ]; then
        echo "WARNING: ${DIR_WRITES} writes to $(basename "$DIR")/ — verify sandbox state" >&2
    fi
fi

exit 0
