#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
# -P は GNU 拡張。BSD grep では、秘密情報が引数に出ていても警告が黙って消える。
# \s → [[:space:]]、\S → [^[:space:]] で -E に置き換えられる。
if echo "$COMMAND" | grep -qE '(--(password|token|secret|api-key|auth)[[:space:]]*=?[[:space:]]*[^[:space:]]{8,})|(-p[[:space:]]+[^[:space:]]{8,})'; then
    echo "WARNING: Possible secret in command arguments." >&2
    echo "Secrets in CLI args are visible in process listings and shell history." >&2
    echo "Use environment variables or stdin instead." >&2
fi
exit 0
