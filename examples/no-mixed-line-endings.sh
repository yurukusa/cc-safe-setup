#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
# 元は grep -qP "\r\n" で CRLF を探していたが、grep は行単位で読んで行末の改行を
# パターンに渡さないので、この式は -P があっても一度も一致しない（GNU grep で実測）。
# 行の終わりに \r があるかどうかを行ごとに数える形へ変える。
MIXED=$(printf '%s' "$CONTENT" | awk '
    /\r$/ { crlf++; next }
    { lf++ }
    END { print (crlf > 0 && lf > 0) ? "yes" : "no" }')
if [ "$MIXED" = "yes" ]; then echo "NOTE: Mixed line endings (CRLF + LF)" >&2; fi
exit 0
