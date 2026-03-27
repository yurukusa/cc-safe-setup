#!/bin/bash
# typescript-lint-on-edit.sh — Run TypeScript type check after editing .ts/.tsx files
#
# TRIGGER: PostToolUse
# MATCHER: Edit
#
# Best with v2.1.85 "if" field:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit",
#       "hooks": [{
#         "type": "command",
#         "if": "Edit(*.ts)",
#         "command": "~/.claude/hooks/typescript-lint-on-edit.sh"
#       }]
#     }]
#   }
# }
#
# Without "if", the hook checks file extension internally.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Skip non-TypeScript files
case "$FILE" in
    *.ts|*.tsx) ;;
    *) exit 0 ;;
esac

[ ! -f "$FILE" ] && exit 0

# Find tsconfig.json in parent directories
DIR=$(dirname "$FILE")
TSCONFIG=""
while [ "$DIR" != "/" ]; do
    if [ -f "$DIR/tsconfig.json" ]; then
        TSCONFIG="$DIR/tsconfig.json"
        break
    fi
    DIR=$(dirname "$DIR")
done

# No tsconfig = no type checking possible
[ -z "$TSCONFIG" ] && exit 0

# Run tsc --noEmit on the specific file
PROJECT_DIR=$(dirname "$TSCONFIG")
ISSUES=$(cd "$PROJECT_DIR" && npx tsc --noEmit --pretty false 2>&1 | grep "$(basename "$FILE")" | head -10)

if [ -n "$ISSUES" ]; then
    COUNT=$(echo "$ISSUES" | wc -l)
    echo "⚠ TypeScript: $COUNT error(s) in $(basename "$FILE")" >&2
    echo "$ISSUES" | head -5 >&2
    if [ "$COUNT" -gt 5 ]; then
        echo "  ... and $((COUNT - 5)) more" >&2
    fi
fi

exit 0
