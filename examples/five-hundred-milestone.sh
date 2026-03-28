INPUT=$(cat)
SETTINGS="$HOME/.claude/settings.local.json"
[[ ! -f "$SETTINGS" ]] && exit 0
HOOK_COUNT=$(grep -c '"command"' "$SETTINGS" 2>/dev/null)
if [[ "$HOOK_COUNT" -gt 0 ]]; then
    echo "🛡 $HOOK_COUNT hooks active. Session protected." >&2
fi
exit 0
