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
