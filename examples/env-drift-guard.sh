#!/bin/bash
# ================================================================
# env-drift-guard.sh — Detect .env vs .env.example drift
# ================================================================
# PURPOSE:
#   When Claude edits .env.example (adding new required vars),
#   warn if .env is missing those variables. Prevents deploy
#   failures from missing environment configuration.
#
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
# ================================================================

FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only trigger when .env.example or .env is edited
case "$FILE" in
    *.env.example|*.env.sample|*.env.template) ;;
    *) exit 0 ;;
esac

# Compare keys in .env.example vs .env
EXAMPLE="$FILE"
ENV_FILE="$(dirname "$FILE")/.env"
[ -f "$EXAMPLE" ] || exit 0
[ -f "$ENV_FILE" ] || { echo "WARNING: $ENV_FILE does not exist but $EXAMPLE was updated." >&2; exit 0; }

# Extract variable names (KEY=... lines, skip comments)
EXAMPLE_KEYS=$(grep -E '^[A-Z_]+=' "$EXAMPLE" 2>/dev/null | cut -d= -f1 | sort)
ENV_KEYS=$(grep -E '^[A-Z_]+=' "$ENV_FILE" 2>/dev/null | cut -d= -f1 | sort)

MISSING=$(comm -23 <(echo "$EXAMPLE_KEYS") <(echo "$ENV_KEYS"))
if [ -n "$MISSING" ]; then
    COUNT=$(echo "$MISSING" | wc -l)
    echo "WARNING: $COUNT variable(s) in $EXAMPLE missing from .env:" >&2
    echo "$MISSING" | head -5 | sed 's/^/  /' >&2
    echo "Update .env to match $EXAMPLE." >&2
fi

exit 0
