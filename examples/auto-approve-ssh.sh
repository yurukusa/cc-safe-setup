#!/bin/bash
# auto-approve-ssh.sh — Auto-approve safe SSH commands
#
# Solves: Trailing wildcard in Bash(ssh * cmd *) doesn't match
# when cmd has no arguments.
#
# GitHub Issue: #36873
#
# Usage: Add to settings.json as a PreToolUse hook on "Bash"
# Customize SAFE_COMMANDS for your use case.
#
# TRIGGER: PermissionRequest  MATCHER: ""

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Safe remote commands (customize this list)
SAFE_COMMANDS="uptime|w|whoami|hostname|uname|date|df|free|cat /etc/os-release"

# Approve only when EVERY command position qualifies.
#
# The pattern below was anchored at `^\s*` and matched against the whole command
# string, so only the first command position was examined and the approval was
# then handed to the entire line: `ssh host uptime && sudo rm -rf app` was
# approved on the strength of its first word. Measured 2026-08-03. Same defect
# as PR #937 / #940 / #941, on the approving side, where the decision is an
# explicit approval rather than a missed block.
#
# Splitting on the separator characters is approximate — quotes are not parsed —
# so a quoted remote payload that carries a separator (`ssh host "uptime; df"`)
# stops qualifying too. That is the conservative direction: it gets no decision
# and lands in the normal permission flow. Command substitution and backticks
# disqualify the line outright. This hook only ever adds approval; it never
# blocks.
cc_every_segment_matches() {
    local pat="$1" cmd="$2" seg
    case "$cmd" in *'$('*|*'`'*) return 1 ;; esac
    while IFS= read -r seg; do
        seg="${seg#"${seg%%[![:space:]]*}"}"
        seg="${seg%"${seg##*[![:space:]]}"}"
        [ -z "$seg" ] && continue
        printf '%s' "$seg" | grep -qE "$pat" || return 1
    done <<EOF
$(printf '%s' "$cmd" | tr ';&|' '\n\n\n')
EOF
    return 0
}

if cc_every_segment_matches "^\s*ssh\s+\S+\s+($SAFE_COMMANDS)(\s|\$)" "$COMMAND"; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "safe SSH command auto-approved"
      }
    }'
    exit 0
fi

exit 0
