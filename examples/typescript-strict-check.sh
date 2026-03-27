#!/bin/bash
# typescript-strict-check.sh — Warn when TypeScript strict mode is disabled
#
# Prevents: Claude silently setting "strict": false in tsconfig.json
#           to bypass type errors instead of fixing them.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

BASENAME=$(basename "$FILE")
[ "$BASENAME" != "tsconfig.json" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Check if strict is explicitly set to false
if python3 -c "
import json
with open('$FILE') as f:
    config = json.load(f)
opts = config.get('compilerOptions', {})
if opts.get('strict') == False:
    exit(1)
if opts.get('noImplicitAny') == False:
    exit(1)
" 2>/dev/null; then
  : # OK
else
  echo "WARNING: TypeScript strict mode is disabled in $FILE." >&2
  echo "  Consider enabling 'strict: true' for better type safety." >&2
fi

exit 0
