#!/bin/bash
# allowlist.sh — Only allow explicitly approved commands
#
# Inverts the default permission model: everything is blocked
# unless it matches an approved pattern. This is the opposite
# of cc-safe-setup's destructive-guard (which blocks specific
# dangerous commands).
#
# Use case: Highly sensitive environments where you want to
# enumerate exactly what Claude Code can do.
#
# Born from GitHub Issue #37471 (Immutable session manifest)
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/allowlist.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PermissionRequest  MATCHER: ""

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-allowlist-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [allowlist]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only gate Bash commands
[[ "$TOOL" != "Bash" ]] && exit 0
[[ -z "$COMMAND" ]] && exit 0

# ========================================
# ALLOWLIST — add your approved patterns
# ========================================
ALLOWED=(
    # Git (read-only + commit, but not push/reset/clean)
    "^\s*git (add|commit|diff|log|status|branch|show|stash|rev-parse|tag)"
    # Package managers (install + read-only)
    "^\s*npm (test|run|install|ci|ls|outdated)"
    "^\s*pip (install|list|show|freeze)"
    # Build/test/lint
    "^\s*pytest"
    "^\s*python3? -m (pytest|py_compile|unittest)"
    "^\s*node --check"
    "^\s*(ruff|black|isort|flake8|pylint|mypy|eslint|prettier)"
    # Safe read-only commands
    "^\s*(cat|head|tail|wc|sort|grep|find|ls|pwd|echo|date|which|whoami)"
    "^\s*(curl -s|wget -q)"
    # Directory navigation
    "^\s*(cd|mkdir|touch)"
)

for pattern in "${ALLOWED[@]}"; do
    if echo "$COMMAND" | grep -qE "$pattern"; then
        exit 0  # Approved
    fi
done

# Not in allowlist — block
echo "BLOCKED: Command not in allowlist" >&2
echo "Command: $COMMAND" >&2
echo "To approve, add a pattern to ~/.claude/hooks/allowlist.sh" >&2
exit 2
