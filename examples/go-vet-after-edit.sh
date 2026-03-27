#!/bin/bash
# go-vet-after-edit.sh — Run go vet after editing Go files
#
# Prevents: Common Go mistakes that compile but fail at runtime.
#           go vet catches: printf format mismatches, unreachable code,
#           struct tag errors, and more.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

case "$FILE" in
  *.go) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE" ] && exit 0

# Run go vet on the package containing the file
DIR=$(dirname "$FILE")
if command -v go >/dev/null 2>&1; then
  ERRORS=$(cd "$DIR" && go vet ./... 2>&1)
  if [ $? -ne 0 ]; then
    echo "go vet found issues:" >&2
    echo "$ERRORS" | head -5 | sed 's/^/  /' >&2
    exit 2
  fi
fi

exit 0
