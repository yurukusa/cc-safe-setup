CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
DEPTH=$(echo "$CONTENT" | awk "{n=0; for(i=1;i<=length;i++) if(substr(\$0,i,1)==\"{\") n++; if(n>m) m=n} END{print m}"); [ "$DEPTH" -gt 4 ] && echo "NOTE: Deep nesting ($DEPTH levels)" >&2
exit 0
