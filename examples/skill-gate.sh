#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL" != "Skill" ]] && exit 0
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
[ -z "$SKILL" ] && exit 0
case "$SKILL" in
    update-config|keybindings-help|simplify|statusline-setup)
        jq -n --arg s "$SKILL" '{
            "decision": "block",
            "reason": ("Built-in skill " + $s + " modifies files without showing changes. Use Edit tool directly for visibility.")
        }'
        exit 0
        ;;
esac
exit 0
