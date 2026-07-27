#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in
    */src/*|*/test*/*|*/lib/*|*/app/*|*.md|*.json|*.yml|*.yaml|*.toml) exit 0 ;;
    */.claude/*|*/.github/*) exit 0 ;;
    *) echo "NOTE: Writing outside standard directories: $FILE" >&2 ;;
esac
exit 0
