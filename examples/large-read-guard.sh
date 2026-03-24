#!/bin/bash
# ================================================================
# large-read-guard.sh — Warn before reading large files
# ================================================================
# PURPOSE:
#   Claude sometimes cats entire log files, database dumps, or
#   minified bundles into context, wasting tokens and accelerating
#   context exhaustion. This hook warns before reading files larger
#   than a threshold.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIG:
#   CC_MAX_READ_KB=100  (warn above 100KB)
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

MAX_KB="${CC_MAX_READ_KB:-100}"

# Detect file-reading commands
FILE=""
if echo "$COMMAND" | grep -qE '^\s*cat\s+'; then
    FILE=$(echo "$COMMAND" | grep -oE 'cat\s+([^ |>]+)' | awk '{print $2}')
elif echo "$COMMAND" | grep -qE '^\s*less\s+|^\s*more\s+'; then
    FILE=$(echo "$COMMAND" | awk '{print $2}')
fi

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Check file size
SIZE_KB=$(du -k "$FILE" 2>/dev/null | cut -f1)
[ -z "$SIZE_KB" ] && exit 0

if [ "$SIZE_KB" -gt "$MAX_KB" ]; then
    LINES=$(wc -l < "$FILE" 2>/dev/null || echo "?")
    echo "WARNING: $FILE is ${SIZE_KB}KB ($LINES lines)." >&2
    echo "Reading large files wastes context tokens." >&2
    echo "Consider: head -100 $FILE, grep pattern $FILE, or tail -50 $FILE" >&2
fi

exit 0
