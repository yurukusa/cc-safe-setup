#!/bin/bash
# system-message-workaround.sh — Ensure hook warnings reach both user and model
#
# Solves: PreToolUse/PostToolUse systemMessage silently dropped (#40380).
#         When a hook returns only systemMessage (without hookSpecificOutput),
#         the warning is invisible to both user and model.
#
# How it works: Template hook that demonstrates the correct pattern for
#   sending warnings that are visible. Uses stderr for user visibility
#   AND hookSpecificOutput.systemMessage for model context injection.
#
# Usage: Copy and adapt this pattern for your custom warn hooks.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Example: warn on dangerous-looking but not blocked commands
WARNING=""

if echo "$COMMAND" | grep -qE 'DROP\s+TABLE|TRUNCATE\s+TABLE'; then
    WARNING="Database destructive operation detected: $COMMAND"
elif echo "$COMMAND" | grep -qE 'curl.*-X\s*(DELETE|PUT|PATCH)'; then
    WARNING="Destructive HTTP method detected: $COMMAND"
fi

if [ -n "$WARNING" ]; then
    # Method 1: stderr — always visible to the user in terminal
    echo "⚠ WARNING: $WARNING" >&2

    # Method 2: hookSpecificOutput with systemMessage — visible to model
    # This is the workaround for #40380: include hookSpecificOutput
    # to ensure the systemMessage is actually processed
    cat << ENDJSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","decision":"allow","systemMessage":"WARNING: $WARNING. Proceed with caution."}}
ENDJSON
fi

exit 0
