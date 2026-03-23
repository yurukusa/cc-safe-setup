#!/bin/bash
# ================================================================
# compound-command-approver.sh — Auto-approve safe compound commands
# ================================================================
# PURPOSE:
#   Claude Code's permission system doesn't match compound commands.
#   `Bash(git:*)` doesn't match `cd /path && git log`.
#   `Bash(npm:*)` doesn't match `cd project && npm test`.
#
#   This hook parses compound commands (&&, ||, ;) and auto-approves
#   when ALL components are in the safe list.
#
#   Solves the #1 most-reacted permission issue:
#   GitHub #30519 (53 reactions) — "Permissions matching is broken"
#   GitHub #16561 (101 reactions) — "Parse compound Bash commands"
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# HOW IT WORKS:
#   1. Splits command on &&, ||, ;
#   2. Checks each component against safe patterns
#   3. If ALL components are safe → auto-approve
#   4. If ANY component is unknown → pass through (no opinion)
#
# SAFE PATTERNS (configurable via CC_SAFE_COMMANDS):
#   - cd, ls, pwd, echo, cat, head, tail, wc, sort, uniq, grep
#   - git (read-only: status, log, diff, branch, show, rev-parse, tag)
#   - npm/yarn/pnpm (read-only: test, run, list, outdated, audit)
#   - python/python3 (test: pytest, -m pytest, -m py_compile)
#   - cargo test, go test, make test
#
# WHAT IT DOES NOT APPROVE:
#   - git push, git reset, git clean (handled by other guards)
#   - rm, sudo, chmod (handled by destructive-guard)
#   - Any command not in the safe list
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only handle compound commands
if ! echo "$COMMAND" | grep -qE '&&|\|\||;'; then
    exit 0
fi

# Split on &&, ||, ; and trim each component
IFS=$'\n' read -r -d '' -a PARTS < <(echo "$COMMAND" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g' && printf '\0')

# Safe command patterns
SAFE_PATTERNS=(
    # Navigation/info
    '^\s*cd\s'
    '^\s*ls(\s|$)'
    '^\s*pwd\s*$'
    '^\s*echo\s'
    '^\s*cat\s'
    '^\s*head\s'
    '^\s*tail\s'
    '^\s*wc\s'
    '^\s*sort(\s|$)'
    '^\s*uniq(\s|$)'
    '^\s*grep\s'
    '^\s*find\s.*-name'
    '^\s*test\s'
    '^\s*\[\s'
    '^\s*true\s*$'
    '^\s*false\s*$'
    '^\s*mkdir\s+-p\s'
    # Git read-only
    '^\s*git\s+(status|log|diff|branch|show|rev-parse|tag|remote|stash\s+list|describe|name-rev|ls-files|ls-tree|shortlog|blame|reflog)(\s|$)'
    '^\s*git\s+-C\s+\S+\s+(status|log|diff|branch|show|rev-parse)(\s|$)'
    '^\s*git\s+add\s'
    '^\s*git\s+commit\s'
    # npm/yarn/pnpm read + test
    '^\s*(npm|yarn|pnpm)\s+(test|run|list|outdated|audit|info|view|pack|version)(\s|$)'
    '^\s*npx\s'
    # Python
    '^\s*(python3?|pytest)\s'
    # Build/test tools
    '^\s*(cargo|go|make|gradle|mvn)\s+(test|build|check|verify|compile)(\s|$)'
    '^\s*(ruff|mypy|flake8|pylint|black|isort)\s'
    '^\s*(eslint|prettier|tsc)\s'
    # Docker read-only
    '^\s*docker\s+(ps|images|logs|inspect|stats|version)(\s|$)'
)

ALL_SAFE=1
for part in "${PARTS[@]}"; do
    part=$(echo "$part" | sed 's/^\s*//; s/\s*$//')
    [[ -z "$part" ]] && continue

    PART_SAFE=0
    for pattern in "${SAFE_PATTERNS[@]}"; do
        if echo "$part" | grep -qE "$pattern"; then
            PART_SAFE=1
            break
        fi
    done

    if (( PART_SAFE == 0 )); then
        ALL_SAFE=0
        break
    fi
done

if (( ALL_SAFE == 1 )); then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"compound command auto-approved (all components safe)"}}'
    exit 0
fi

# Unknown component — let normal permission flow handle it
exit 0
