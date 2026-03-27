#!/bin/bash
# python-ruff-on-edit.sh — Run ruff lint after editing Python files
#
# TRIGGER: PostToolUse
# MATCHER: Edit
#
# Best with the v2.1.85 "if" field to avoid running on non-Python edits:
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit",
#       "hooks": [{
#         "type": "command",
#         "if": "Edit(*.py)",
#         "command": "~/.claude/hooks/python-ruff-on-edit.sh"
#       }]
#     }]
#   }
# }
#
# Without "if", the hook runs after every Edit and checks internally.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Skip non-Python files (redundant with "if" field, kept for backward compat)
[[ "$FILE" != *.py ]] && exit 0
[ ! -f "$FILE" ] && exit 0

# Prefer ruff, fall back to flake8, then pylint
if command -v ruff &>/dev/null; then
    ISSUES=$(ruff check "$FILE" --quiet 2>/dev/null)
elif command -v flake8 &>/dev/null; then
    ISSUES=$(flake8 "$FILE" --max-line-length=120 2>/dev/null)
elif command -v pylint &>/dev/null; then
    ISSUES=$(pylint "$FILE" --errors-only --score=no 2>/dev/null)
else
    exit 0  # No linter available
fi

if [ -n "$ISSUES" ]; then
    COUNT=$(echo "$ISSUES" | wc -l)
    echo "⚠ Lint: $COUNT issue(s) in $(basename "$FILE")" >&2
    echo "$ISSUES" | head -5 >&2
    if [ "$COUNT" -gt 5 ]; then
        echo "  ... and $((COUNT - 5)) more" >&2
    fi
fi

exit 0
