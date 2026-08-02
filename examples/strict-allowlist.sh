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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-strict-allowlist-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [strict-allowlist]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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

# One line can chain several commands. The shipped patterns are anchored with
# "^", so matching them against the whole line only ever inspects the first
# word: an approved command followed by "&&" and anything at all was approved.
# For a denylist that is a gap; for an allowlist it means the list stops
# enforcing after the first segment, which is the whole feature. Claude Code
# closed the same class of hole in its own permission checking (2.1.216,
# "Fixed Bash permission checking for compound statements").
#
# So: split on the operators that begin a new command and require EVERY segment
# to match a pattern. One unapproved segment blocks the line.
SEGMENTS=$(printf '%s' "$COMMAND" | sed -E 's/(\|\||&&|[;|&])/\n/g')

# Command substitution executes text that never appears as a segment, so
# splitting cannot vet it. Refuse rather than guess.
if printf '%s' "$COMMAND" | grep -qE '\$\(|`'; then
    echo "BLOCKED: command substitution is not allowed by the allowlist." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

while IFS= read -r SEGMENT; do
    # sed leaves an empty field where a two-character operator was split
    [[ -z "${SEGMENT//[[:space:]]/}" ]] && continue

    # "ls; pwd" splits into "ls" and " pwd". The shipped patterns are anchored
    # with "^" and no leading \s*, so the space would make the second segment
    # fail to match and block a perfectly approved chain. Trim before matching.
    SEGMENT=$(printf '%s' "$SEGMENT" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')

    ALLOWED=0
    while IFS= read -r pattern; do
        # Skip comments and empty lines
        [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$pattern" ]] && continue

        if printf '%s' "$SEGMENT" | grep -qE "$pattern"; then
            ALLOWED=1
            break
        fi
    done < "$ALLOWLIST"

    if [ "$ALLOWED" -eq 0 ]; then
        echo "BLOCKED: Command not in allowlist." >&2
        echo "Command: $COMMAND" >&2
        echo "Unapproved segment: $SEGMENT" >&2
        echo "Add a matching pattern to $ALLOWLIST to permit." >&2
        exit 2
    fi
done <<< "$SEGMENTS"

exit 0
