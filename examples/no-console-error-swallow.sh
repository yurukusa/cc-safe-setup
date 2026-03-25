#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
if echo "$CONTENT" | grep -qE "catch\s*\([^)]*\)\s*\{[\s\n]*\}|except:[\s\n]*pass"; then echo "WARNING: Empty catch/except block swallows errors" >&2; fi
exit 0
