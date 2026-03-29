#!/bin/bash
# ================================================================
# test-after-edit.sh — Remind to run tests after editing test files
#
# Solves: Claude editing test files but not running them to verify
# they still pass. Common pattern: modify a test assertion, don't
# run the test suite, move on to next task.
#
# Uses the v2.1.85+ "if" field for efficient matching — only fires
# when test files are edited, not on every Edit/Write.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "if": "Edit(*.test.*) || Edit(*.spec.*) || Write(*.test.*) || Write(*.spec.*)",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/test-after-edit.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0

# Check if this is a test file
if echo "$FILE" | grep -qE '\.(test|spec)\.(ts|tsx|js|jsx|py|rb|go)$|__tests__/|/tests?/.*\.(ts|tsx|js|jsx|py|rb|go)$'; then
    echo "NOTE: Test file modified: $(basename "$FILE")" >&2
    echo "Remember to run the test suite to verify changes." >&2

    # Suggest appropriate test command based on project
    if [[ -f "package.json" ]]; then
        echo "Suggested: npm test" >&2
    elif [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
        echo "Suggested: pytest $(basename "$FILE")" >&2
    elif [[ -f "Cargo.toml" ]]; then
        echo "Suggested: cargo test" >&2
    elif [[ -f "go.mod" ]]; then
        echo "Suggested: go test ./..." >&2
    fi
fi

exit 0
