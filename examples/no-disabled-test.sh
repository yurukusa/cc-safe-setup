CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "\.(skip|only)\(|xit\(|xdescribe\(" && echo "WARNING: Disabled/focused test detected" >&2
exit 0
