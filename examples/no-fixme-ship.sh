#!/bin/bash
# no-fixme-ship.sh — Block git push when FIXME/HACK comments exist
#
# Prevents: Shipping code with known issues. FIXME and HACK comments
#           indicate unfinished work that should be resolved before push.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/no-fixme-ship.sh" }]
#     }]
#   }
# }

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-fixme-ship-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-fixme-ship]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check on git push
echo "$COMMAND" | grep -qE '^\s*git\s+push' || exit 0

# Search staged/committed files for FIXME/HACK
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
UPSTREAM=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "origin/main")

FIXMES=$(git diff "$UPSTREAM"...HEAD 2>/dev/null | grep -E '^\+.*(FIXME|HACK|XXX)\b' | head -5)

if [ -n "$FIXMES" ]; then
  COUNT=$(echo "$FIXMES" | wc -l)
  echo "WARNING: $COUNT FIXME/HACK/XXX comments in unpushed changes:" >&2
  echo "$FIXMES" | head -3 | sed 's/^/  /' >&2
  echo "  Resolve these before pushing." >&2
  # Warning only. Change exit 0 to exit 2 to block.
fi

exit 0
