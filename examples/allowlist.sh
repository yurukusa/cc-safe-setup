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
# Known limits — read these before trusting it as your only layer:
#   * Redirection is not inspected. An approved command word can still write
#     anywhere ("echo evil > ~/.bashrc"). Enumerating safe write targets is a
#     different job than enumerating command names; pair this with a hook that
#     judges the destination.
#   * Approval is per command name, not per argument. "git commit" is approved
#     regardless of its flags.
#   * Patterns are yours to own. Everything not listed is blocked, so an
#     incomplete list fails closed (annoying) rather than open (dangerous).
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
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# This line used to say PermissionRequest, contradicting the settings.json
# example above. PreToolUse is the correct one: the reference states it fires
# "Before a tool call executes", while PermissionRequest fires only "When a
# tool call needs a permission decision" — which never happens under auto mode
# or bypassed permissions. A guard registered on PermissionRequest would sit
# silent in exactly the sessions that need it most.

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

# A single line can chain several commands. Every pattern above is anchored with
# "^", so matching them against the whole string only ever inspects the first
# word: "echo hi && rm -rf /" matched "^\s*echo" and was approved. For a hook
# whose stated purpose is to enumerate exactly what Claude Code may do, that is
# not a gap — it is the allowlist enforcing nothing past the first segment.
# Claude Code closed the same class of hole in its own permission checking
# (2.1.216, "Fixed Bash permission checking for compound statements").
#
# So: split on the operators that begin a new command, and require EVERY segment
# to be approved. One unapproved segment blocks the line.
SEGMENTS=$(printf '%s' "$COMMAND" | sed -E 's/(\|\||&&|[;|&])/\n/g')

# Command substitution executes text that never shows up as a segment, so no
# amount of splitting can vet it. Refuse instead of guessing.
if printf '%s' "$COMMAND" | grep -qE '\$\(|`'; then
    echo "BLOCKED: command substitution is not allowed by the allowlist" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

while IFS= read -r SEGMENT; do
    # sed leaves an empty field where a two-character operator was split
    [[ -z "${SEGMENT//[[:space:]]/}" ]] && continue

    APPROVED=0
    for pattern in "${ALLOWED[@]}"; do
        if printf '%s' "$SEGMENT" | grep -qE "$pattern"; then
            APPROVED=1
            break
        fi
    done

    if [[ $APPROVED -eq 0 ]]; then
        echo "BLOCKED: Command not in allowlist" >&2
        echo "Command: $COMMAND" >&2
        echo "Unapproved segment: $SEGMENT" >&2
        echo "To approve, add a pattern to ~/.claude/hooks/allowlist.sh" >&2
        exit 2
    fi
done <<< "$SEGMENTS"

exit 0
