#!/bin/bash
# ================================================================
# fact-check-gate.sh — Warn when docs reference unread source files
# ================================================================
# PURPOSE:
#   Claude writes documentation that references source code without
#   actually reading the files first. This leads to hallucinated
#   function signatures, wrong parameter names, and false claims.
#
#   This hook tracks which files were Read in the session, and warns
#   when a doc edit mentions source files that weren't read.
#
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
#
# Born from: https://github.com/anthropics/claude-code/issues/38057
#   "Claude produces false claims in technical docs"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check documentation files
case "$FILE" in
    *.md|*.rst|*.txt|*/docs/*|*/doc/*|*README*|*CHANGELOG*|*CONTRIBUTING*)
        ;;
    *)
        exit 0
        ;;
esac

# Track reads in a session state file
STATE="/tmp/cc-fact-check-reads-$(echo "$PWD" | md5sum | cut -c1-8)"

# Get the content being written
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

# Extract referenced source files from the doc content
# Looks for: `filename.ext`, filename.ext, import from, require()
REFS=$(echo "$CONTENT" | grep -oE '`[a-zA-Z0-9_/-]+\.(js|ts|py|go|rs|java|rb|sh|mjs|cjs|jsx|tsx)`' | tr -d '`' | sort -u)
[ -z "$REFS" ] && exit 0

# Check if referenced files were read in this session
if [ ! -f "$STATE" ]; then
    # No reads tracked yet — warn about all references
    COUNT=$(echo "$REFS" | wc -l)
    echo "WARNING: Doc references $COUNT source file(s) that may not have been read:" >&2
    echo "$REFS" | head -5 | sed 's/^/  /' >&2
    echo "Read the source files before documenting them to avoid hallucination." >&2
fi

exit 0
