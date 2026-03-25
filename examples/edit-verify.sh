INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]] && exit 0
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && { echo "WARNING: File does not exist after edit: $FILE" >&2; exit 0; }
SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
if [ "$SIZE" -eq 0 ]; then
    echo "WARNING: File is empty after edit: $FILE (possible truncation)" >&2
    exit 0
fi
if [ "$TOOL" = "Edit" ]; then
    NEW_STR=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
    if [ -n "$NEW_STR" ]; then
        FIRST_LINE=$(echo "$NEW_STR" | head -1)
        if [ -n "$FIRST_LINE" ] && ! grep -qF "$FIRST_LINE" "$FILE" 2>/dev/null; then
            echo "WARNING: Edit may not have applied — new_string not found in $FILE" >&2
        fi
    fi
fi
if grep -qE '^(<<<<<<<|=======|>>>>>>>)' "$FILE" 2>/dev/null; then
    echo "WARNING: Merge conflict markers detected in $FILE after edit" >&2
fi
if [ "$SIZE" -lt 10 ]; then
    case "$FILE" in
        *.json|*.yaml|*.yml|*.toml) ;; # Config files can be small
        *) echo "WARNING: File suspiciously small ($SIZE bytes) after edit: $FILE" >&2 ;;
    esac
fi
exit 0
