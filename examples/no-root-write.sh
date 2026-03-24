FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in /etc/*|/usr/*|/bin/*|/sbin/*|/boot/*|/sys/*|/proc/*)
    echo "BLOCKED: Write to system directory" >&2; exit 2 ;; esac
exit 0
