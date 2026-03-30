#!/bin/bash
# ================================================================
# git-operations-require-approval.sh — Block git write operations
# ================================================================
# PURPOSE:
#   Claude Code sometimes ignores CLAUDE.md rules about git commit,
#   push, and branch creation — performing these operations without
#   user approval. This hook enforces the restriction at process level.
#
# Blocks:
#   git commit, git push (including --force), git checkout -b,
#   git switch -c, git branch <name>
#
# Does NOT block:
#   git status, git log, git diff, git show, git branch (list),
#   git fetch, git stash, git add
#
# Handles compound commands (&&, ;, ||) by checking each segment.
#
# See: https://github.com/anthropics/claude-code/issues/40695
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Skip if the command is inside echo/printf (not actual execution)
echo "$COMMAND" | grep -qE '^\s*(echo|printf)\s' && exit 0

# Check each segment of compound commands
check_segment() {
    local seg="$1"
    # Trim whitespace
    seg=$(echo "$seg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$seg" ] && return 0

    # git commit
    if echo "$seg" | grep -qE '\bgit\s+commit\b'; then
        echo "BLOCKED: git commit requires explicit user approval." >&2
        echo "Command: $seg" >&2
        echo "" >&2
        echo "See: https://github.com/anthropics/claude-code/issues/40695" >&2
        return 1
    fi

    # git push (including force variants)
    if echo "$seg" | grep -qE '\bgit\s+push\b'; then
        echo "BLOCKED: git push requires explicit user approval." >&2
        echo "Command: $seg" >&2
        echo "" >&2
        echo "See: https://github.com/anthropics/claude-code/issues/40695" >&2
        return 1
    fi

    # git checkout -b (branch creation)
    if echo "$seg" | grep -qE '\bgit\s+checkout\s+(-b|--branch)\b'; then
        echo "BLOCKED: git branch creation requires explicit user approval." >&2
        echo "Command: $seg" >&2
        return 1
    fi

    # git switch -c / --create (branch creation)
    if echo "$seg" | grep -qE '\bgit\s+switch\s+(-c|--create)\b'; then
        echo "BLOCKED: git branch creation requires explicit user approval." >&2
        echo "Command: $seg" >&2
        return 1
    fi

    # git branch <name> (creation, not listing)
    # git branch without flags or with only -a/-r/-l/--list is listing
    if echo "$seg" | grep -qE '\bgit\s+branch\s'; then
        # Allow listing flags
        if echo "$seg" | grep -qE '\bgit\s+branch\s+(-[arl]|--list|--merged|--no-merged|--contains|-v|--verbose|-d|--delete|-D)\b'; then
            return 0
        fi
        # If it has a name argument after "git branch", it's creation
        local args
        args=$(echo "$seg" | sed 's/.*\bgit\s\+branch\s\+//')
        if [ -n "$args" ] && ! echo "$args" | grep -qE '^\s*$'; then
            echo "BLOCKED: git branch creation requires explicit user approval." >&2
            echo "Command: $seg" >&2
            return 1
        fi
    fi

    return 0
}

# Split on && ; || and check each part
while IFS= read -r segment; do
    if ! check_segment "$segment"; then
        exit 2
    fi
done < <(echo "$COMMAND" | sed 's/&&/\n/g; s/;/\n/g; s/||/\n/g')

exit 0
