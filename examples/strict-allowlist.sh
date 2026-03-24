#!/bin/bash
# ================================================================
# strict-allowlist.sh — Only allow explicitly permitted commands
# ================================================================
# PURPOSE:
#   Instead of blocking known-bad commands (denylist), this hook
#   only allows known-good commands (allowlist). Every command not
#   on the list requires explicit approval.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIG:
#   CC_ALLOWLIST_FILE=~/.claude/allowlist.txt
#   One pattern per line, regex supported.
#   Empty file = block everything.
#
# Born from: https://github.com/anthropics/claude-code/issues/37471
#   "Immutable session manifest with allowlist-only enforcement"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

ALLOWLIST="${CC_ALLOWLIST_FILE:-$HOME/.claude/allowlist.txt}"

# If no allowlist file exists, create a default one
if [ ! -f "$ALLOWLIST" ]; then
    mkdir -p "$(dirname "$ALLOWLIST")"
    cat > "$ALLOWLIST" <<'DEFAULT'
# Claude Code Strict Allowlist
# One regex pattern per line. Commands matching any pattern are allowed.
# Lines starting with # are comments.
# Empty = block all Bash commands.

# Read-only operations
^ls\b
^cat\b
^head\b
^tail\b
^wc\b
^grep\b
^find\b
^which\b
^echo\b
^pwd$
^date$

# Git read
^git\s+(status|log|diff|show|branch|remote|tag\s+-l)
^git\s+add\b
^git\s+commit\b

# Build/test
^npm\s+(test|run\s+(build|lint|check|format))
^pytest\b
^cargo\s+(build|test|check|clippy)
^go\s+(build|test|vet|fmt)
^make\s*(build|test|lint|check|all)?$

# Package info
^npm\s+(ls|list|info|view|outdated)
^pip\s+(list|show|freeze)
DEFAULT
    echo "NOTE: Created default allowlist at $ALLOWLIST" >&2
    echo "Edit it to customize permitted commands." >&2
fi

# Check command against allowlist
ALLOWED=0
while IFS= read -r pattern; do
    # Skip comments and empty lines
    [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$pattern" ]] && continue

    if echo "$COMMAND" | grep -qE "$pattern"; then
        ALLOWED=1
        break
    fi
done < "$ALLOWLIST"

if [ "$ALLOWED" -eq 0 ]; then
    echo "BLOCKED: Command not in allowlist." >&2
    echo "Command: $COMMAND" >&2
    echo "Add a matching pattern to $ALLOWLIST to permit." >&2
    exit 2
fi

exit 0
