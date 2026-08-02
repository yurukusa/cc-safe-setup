#!/bin/bash
# go-vet-after-edit.sh — Run go vet after editing Go files
#
# Prevents: Common Go mistakes that compile but fail at runtime.
#           go vet catches: printf format mismatches, unreachable code,
#           struct tag errors, and more.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-go-vet-after-edit-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [go-vet-after-edit]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
