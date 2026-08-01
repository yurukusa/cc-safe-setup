#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-npm-publish-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [npm-publish-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*(npm\s+publish|npx\s+npm\s+publish)' && ! echo "$COMMAND" | grep -qE '\-\-dry-run'; then
    if [ -f "package.json" ]; then
        VER=$(python3 -c "import json; print(json.load(open('package.json')).get('version','?'))" 2>/dev/null)
        echo "BLOCKED: npm publish of version $VER requires manual confirmation." >&2
    else
        echo "BLOCKED: npm publish requires manual confirmation." >&2
    fi
    exit 2
fi
exit 0
