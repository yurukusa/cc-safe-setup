#!/bin/bash
# ================================================================
# dotenv-example-sync.sh — Warn when .env changes but .env.example doesn't
# ================================================================
# PURPOSE:
#   When Claude edits .env (adding/removing variables), .env.example
#   should be updated to match. This hook warns if .env was modified
#   but .env.example still has different keys, preventing deployment
#   failures when team members don't have the new variables.
#
# TRIGGER: PostToolUse
# MATCHER: "Edit|Write"
#
# DECISION: Advisory only (exit 0). Warns via stderr.
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only trigger when .env is edited (not .env.example itself)
case "$(basename "$FILE")" in
    .env|.env.local|.env.development|.env.production) ;;
    *) exit 0 ;;
esac

# Find corresponding .env.example
DIR=$(dirname "$FILE")
EXAMPLE=""
for candidate in "$DIR/.env.example" "$DIR/.env.sample" "$DIR/.env.template"; do
    if [ -f "$candidate" ]; then
        EXAMPLE="$candidate"
        break
    fi
done

[ -z "$EXAMPLE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Extract variable names (lines with KEY=)
ENV_KEYS=$(grep -oE '^[A-Z_][A-Z0-9_]*=' "$FILE" 2>/dev/null | sort -u)
EXAMPLE_KEYS=$(grep -oE '^[A-Z_][A-Z0-9_]*=' "$EXAMPLE" 2>/dev/null | sort -u)

# Find keys in .env but not in .env.example
MISSING=$(comm -23 <(echo "$ENV_KEYS") <(echo "$EXAMPLE_KEYS"))

if [ -n "$MISSING" ]; then
    echo "⚠ .env has variables not in $(basename "$EXAMPLE"):" >&2
    echo "$MISSING" | sed 's/=$//' | while read key; do
        echo "  + $key" >&2
    done
    echo "  Update $(basename "$EXAMPLE") so teammates have the full variable list." >&2
fi

exit 0
