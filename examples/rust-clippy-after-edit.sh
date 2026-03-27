#!/bin/bash
# rust-clippy-after-edit.sh — Run cargo clippy after editing Rust files
#
# Prevents: Common Rust anti-patterns and potential bugs.
#           Clippy catches: needless borrows, inefficient patterns,
#           suspicious operations.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

case "$FILE" in
  *.rs) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE" ] && exit 0

# Find Cargo.toml
DIR=$(dirname "$FILE")
while [ "$DIR" != "/" ]; do
  [ -f "$DIR/Cargo.toml" ] && break
  DIR=$(dirname "$DIR")
done

if [ -f "$DIR/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
  WARNINGS=$(cd "$DIR" && cargo clippy --quiet 2>&1 | grep "^warning" | head -3)
  if [ -n "$WARNINGS" ]; then
    echo "Clippy warnings:" >&2
    echo "$WARNINGS" | sed 's/^/  /' >&2
  fi
fi

exit 0
