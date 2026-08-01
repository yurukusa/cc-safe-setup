#!/bin/bash
# user-account-guard.sh — Block user/group account modifications
#
# Solves: Claude Code creating, deleting, or modifying system user
#         accounts which can create security backdoors or lock out
#         legitimate users.
#
# Detects:
#   useradd / adduser        (create user)
#   userdel / deluser        (delete user)
#   usermod                  (modify user)
#   passwd                   (change password)
#   groupadd / groupdel      (group management)
#   visudo / sudoers editing  (privilege escalation)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-user-account-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [user-account-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

if echo "$COMMAND" | grep -qE '\b(useradd|adduser|userdel|deluser|usermod|groupadd|groupdel|groupmod)\b'; then
    echo "BLOCKED: User/group account modification detected." >&2
    echo "  Creating or modifying system accounts requires administrator oversight." >&2
    exit 2
fi

if echo "$COMMAND" | grep -qE '\bpasswd\b'; then
    echo "BLOCKED: Password change detected." >&2
    exit 2
fi

if echo "$COMMAND" | grep -qE '\bvisudo\b|/etc/sudoers'; then
    echo "BLOCKED: Sudoers modification (privilege escalation risk)." >&2
    exit 2
fi

exit 0
