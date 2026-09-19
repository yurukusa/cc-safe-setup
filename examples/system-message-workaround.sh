#!/bin/bash
# system-message-workaround.sh — Get a non-blocking hook warning in front of the user
#
# Solves: PreToolUse/PostToolUse systemMessage silently dropped (#40380).
#         A hook that returns only systemMessage warns nobody.
#
# How it works: stderr, which the user sees in the terminal. That part works.
#
# MEASURED 2026-09-19, Claude Code 2.1.278, PreToolUse / matcher Bash, disposable
# HOME, verdict = whether a unique token in the message appears in the model's
# reply when asked to quote anything it was shown:
#
#   nothing printed (control)                                     not delivered
#   hookSpecificOutput{decision:"allow", systemMessage}           not delivered
#   top-level {"systemMessage": ...}                              not delivered
#   hookSpecificOutput{permissionDecision:"allow", ...Reason}     not delivered
#   stderr + exit 2 (positive control)                            DELIVERED
#
# So on this version there is no JSON shape that puts an *allow-path* message in
# front of the model. Three were tried; all three were dropped. This file used to
# claim the first of them worked - it does not, and the claim is removed rather
# than replaced, because nothing measured here earns a replacement.
#
# If the model must see it, the message has to ride on a refusal: stderr + exit 2,
# or hookSpecificOutput.permissionDecision "deny" with permissionDecisionReason.
# Both were measured to reach the model the same night. Neither is non-blocking.
#
# Not measured: PostToolUse, permissionDecision "ask", interactive sessions, and
# any version other than 2.1.278.
#
# Usage: Copy the stderr line for your custom warn hooks. Copy the JSON only if
#   you have checked, on your own version, that it arrives - the check is one run
#   with a unique token in the message and one control.
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

    # Method 2 used to live here: a hookSpecificOutput body carrying systemMessage,
    # described as the way to reach the model. Measured on 2.1.278 it is dropped,
    # as are the two other shapes listed in the header, so emitting it only made
    # the file look like it was doing something. Removed rather than rewritten.
    #
    # If you need the model to see this, it cannot be non-blocking on this
    # version. Turn the branch above into a refusal:
    #
    #     echo "BLOCKED: $WARNING" >&2
    #     exit 2
fi

exit 0
