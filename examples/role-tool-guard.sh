#!/bin/bash
# role-tool-guard.sh — Restrict tools based on current agent role
#
# Solves: Agent team workflows where PM writes code instead of delegating (#40425).
#         When using structured team roles (PM → Architect → Developer),
#         each role should only access tools appropriate to its function.
#         CLAUDE.md rules are advisory and get ignored under context pressure.
#
# How it works: Reads current role from a scope file, then blocks tools
#   that don't match the role's allowed tool set.
#
# Setup:
#   echo "pm" > .claude/current-role.txt
#   Roles: pm, architect, developer, reviewer (customizable)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|Edit|Write|NotebookEdit|Agent"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-role-tool-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [role-tool-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

# Read current role
ROLE_FILE=".claude/current-role.txt"
[ -f "$ROLE_FILE" ] || exit 0

ROLE=$(head -1 "$ROLE_FILE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
[ -z "$ROLE" ] && exit 0

# Define allowed tools per role (customizable via env)
case "$ROLE" in
  pm|"product-manager"|"project-manager")
    # PM can read, search, and delegate — not write code
    BLOCKED_TOOLS="Edit|Write|Bash|NotebookEdit"
    ROLE_DESC="PM (read/delegate only)"
    ;;
  architect|"system-architect")
    # Architect can read and write docs, not execute
    BLOCKED_TOOLS="Bash|NotebookEdit"
    ROLE_DESC="Architect (design only, no execution)"
    ;;
  reviewer|"code-reviewer")
    # Reviewer can read and comment, not modify
    BLOCKED_TOOLS="Edit|Write|NotebookEdit"
    ROLE_DESC="Reviewer (read-only)"
    ;;
  developer|"dev")
    # Developer has full access
    exit 0
    ;;
  *)
    # Unknown role — allow by default
    exit 0
    ;;
esac

# Check if current tool is blocked for this role
if echo "$TOOL" | grep -qE "^($BLOCKED_TOOLS)$"; then
  echo "BLOCKED: Role '$ROLE' cannot use $TOOL." >&2
  echo "Current role: $ROLE_DESC" >&2
  echo "" >&2
  echo "To change role: echo 'developer' > .claude/current-role.txt" >&2
  echo "Or delegate this task to the appropriate agent." >&2
  exit 2
fi

exit 0
