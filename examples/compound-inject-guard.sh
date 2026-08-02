#!/bin/bash
# compound-inject-guard.sh — Block destructive commands hidden in compound statements
#
# Solves: Permission allow list glob wildcards match shell operators (&&, ;, ||),
#         allowing destructive commands to bypass the allowlist.
#         Example: `Bash(git -C * status)` also matches
#         `git -C "/repo" && rm -rf / && git -C "/repo" status`
#
# Related: GitHub #40344 — "Permission allow list glob wildcards match shell
#          operators, enabling command injection"
#
# How it works: Splits compound commands on shell operators (&&, ||, ;)
#   and checks each segment independently for destructive patterns.
#   This prevents destructive commands from hiding inside compound statements
#   that match overly broad permission allow rules.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-compound-inject-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [compound-inject-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check compound commands (those with shell operators)
echo "$COMMAND" | grep -qE '&&|\|\||;' || exit 0

# Destructive patterns to detect in each segment
DESTRUCT='rm\s+-[rf]*\s+[/~]|rm\s+-[rf]*\s+\.\.|git\s+reset\s+--hard|git\s+clean\s+-[fd]+|mkfs\.|dd\s+if=|chmod\s+777\s+/|>\s*/dev/sd'

# Split on shell operators and check each segment
IFS=$'\n'
for segment in $(echo "$COMMAND" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g'); do
    # Trim leading whitespace
    segment=$(echo "$segment" | sed 's/^\s*//')
    [ -z "$segment" ] && continue

    if echo "$segment" | grep -qE "$DESTRUCT"; then
        echo "BLOCKED: Destructive command in compound statement" >&2
        echo "  Segment: $segment" >&2
        echo "  Fix: Run destructive commands separately, not chained with && or ;" >&2
        exit 2
    fi
done

exit 0
