#!/bin/bash
# auto-approve-build.sh — Auto-approve build and test commands
#
# Solves: Permission prompts for npm/yarn/pnpm build/test/lint commands
#         that slow down autonomous workflows
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/auto-approve-build.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Approve only when EVERY command position qualifies.
#
# The patterns below were anchored at `^\s*` and matched against the whole
# command string, so only the first command position was examined and the
# approval was then handed to the entire line: `npm test && sudo rm -rf app` was
# approved on the strength of its first word. Measured 2026-08-03 against the
# shipped copy. Same defect as PR #937 (allowlist.sh) and PR #940
# (cd-git-allow.sh), here on the approving side, where the decision is an
# explicit approval rather than a missed block.
#
# Splitting on the separator characters is approximate — quotes are not parsed —
# so anything that can hide a command from a string-level read (command
# substitution, backticks) disqualifies the line outright. A line that does not
# qualify gets no decision, which leaves it to the normal permission flow. This
# hook only ever adds approval; it never blocks.
#
# The gate uses the union of the three patterns, so a chain of different
# approved kinds (`npm ci && npm test`) still passes; the if-chain below only
# picks which branch reports the approval.
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

BUILD_SAFE_RE='^\s*(npm|yarn|pnpm|bun|npx)\s+(run\s+)?(build|test|lint|check|typecheck|format|dev|start|ci)'
BUILD_SAFE_RE="$BUILD_SAFE_RE"'|^\s*(cargo\s+(build|test|check|clippy|fmt)|go\s+(build|test|vet|fmt)|make\s+(build|test|check|lint))'
BUILD_SAFE_RE="$BUILD_SAFE_RE"'|^\s*(python|python3)\s+(-m\s+)?(pytest|unittest|mypy|ruff|black|isort|flake8)'

cc_every_segment_matches "$BUILD_SAFE_RE" "$CMD" || exit 0

# Auto-approve safe build/test/lint commands
if echo "$CMD" | grep -qE '^\s*(npm|yarn|pnpm|bun|npx)\s+(run\s+)?(build|test|lint|check|typecheck|format|dev|start|ci)'; then
    echo '{"decision":"approve"}'
    exit 0
fi

# Auto-approve cargo/go/make build commands
if echo "$CMD" | grep -qE '^\s*(cargo\s+(build|test|check|clippy|fmt)|go\s+(build|test|vet|fmt)|make\s+(build|test|check|lint))'; then
    echo '{"decision":"approve"}'
    exit 0
fi

# Auto-approve python test/lint
if echo "$CMD" | grep -qE '^\s*(python|python3)\s+(-m\s+)?(pytest|unittest|mypy|ruff|black|isort|flake8)'; then
    echo '{"decision":"approve"}'
    exit 0
fi

exit 0
