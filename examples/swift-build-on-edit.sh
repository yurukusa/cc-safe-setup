#!/bin/bash
# ================================================================
# swift-build-on-edit.sh — Run swift build check after editing Swift files
#
# Uses swift build --skip-update for fast compilation check.
# Warns on build errors but doesn't block.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "if": "Edit(*.swift) || Write(*.swift)",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/swift-build-on-edit.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != *.swift ]] && exit 0

# Check if swift is available and we're in a Swift package
if command -v swift &>/dev/null && [[ -f "Package.swift" ]]; then
    RESULT=$(swift build 2>&1 | tail -5)
    if [[ $? -ne 0 ]]; then
        echo "Swift build error after editing $(basename "$FILE"):" >&2
        echo "$RESULT" | head -5 >&2
    fi
fi

exit 0
