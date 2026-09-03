#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
# -P は GNU 拡張で、macOS の BSD grep では grep 自体がエラーになり警告が黙って消える。
# 内容は POSIX の拡張正規表現で書けるので -E にする（\s → [[:space:]]）。
if grep -qE "origin:[[:space:]]*['\"]?\*['\"]?|Access-Control-Allow-Origin.*\*|cors\(\)" "$FILE" 2>/dev/null; then
    echo "WARNING: Wildcard CORS origin in $(basename "$FILE")." >&2
    echo "cors(*) allows any website to call your API." >&2
    echo "Specify allowed origins explicitly." >&2
fi
exit 0
