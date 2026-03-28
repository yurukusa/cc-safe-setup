#!/bin/bash
# unicode-corruption-check.sh — Detect Unicode corruption after Edit/Write
#
# Solves: Claude Code's Edit tool corrupting non-ASCII Unicode characters
#         (typographic quotes, em dashes, accented characters) in string literals.
#         Real incident: #38765 — Edit tool replaced Unicode quotes with
#         escaped sequences, breaking string comparisons.
#
# How it works: After Edit/Write, checks if the file contains common
# corruption patterns (replacement characters, broken UTF-8 sequences).
#
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Skip binary files
file "$FILE" 2>/dev/null | grep -q "text" || exit 0

# Check for Unicode replacement character (U+FFFD) — sign of broken encoding
if grep -Pq '\xef\xbf\xbd' "$FILE" 2>/dev/null; then
    echo "⚠ Unicode corruption detected in $FILE" >&2
    echo "  Found U+FFFD replacement characters (broken encoding)." >&2
    echo "  Review the edit — non-ASCII characters may have been corrupted." >&2
fi

# Check for common corruption: escaped Unicode in places it shouldn't be
# e.g., \u2018 appearing in plain text files (not JSON/JS)
if ! echo "$FILE" | grep -qE '\.(json|js|ts|jsx|tsx)$'; then
    if grep -qE '\\u[0-9a-fA-F]{4}' "$FILE" 2>/dev/null; then
        echo "⚠ Possible Unicode escape in non-JS file: $FILE" >&2
        echo "  Found \\uXXXX sequences that may be corrupted characters." >&2
    fi
fi

exit 0
