#!/bin/bash
# dotenv-validate.sh — Validate .env syntax after edits
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in *.env|*.env.*) ;; *) exit 0 ;; esac
[ ! -f "$FILE" ] && exit 0
# Check for common .env syntax errors
ERRORS=0
while IFS= read -r line; do
    [ -z "$line" ] || [[ "$line" =~ ^# ]] && continue
    if ! echo "$line" | grep -qE '^[A-Z_][A-Z0-9_]*='; then
        echo "WARNING: Invalid .env line: $line" >&2
        ERRORS=$((ERRORS+1))
    fi
done < "$FILE"
[ "$ERRORS" -gt 0 ] && echo "$ERRORS syntax error(s) in $FILE" >&2
exit 0
