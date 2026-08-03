#!/bin/bash
# auto-approve-python.sh — Auto-approve Python development commands
#
# Solves: Permission prompts for pytest, mypy, ruff, black, isort
#         that slow down autonomous Python development
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/auto-approve-python.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PermissionRequest  MATCHER: ""

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Approve only when EVERY command position qualifies.
#
# The patterns below were anchored at `^\s*` and matched against the whole
# command string, so only the first command position was examined and the
# approval was then handed to the entire line: `pytest && sudo rm -rf app` was
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
# The gate uses the union of the four patterns, so a chain of different approved
# kinds (`ruff check . && pytest`) still passes; the if-chain below only picks
# which reason to report.
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

PY_SAFE_RE='^\s*(pytest|python\s+-m\s+pytest|python\s+-m\s+unittest)(\s|$)'
PY_SAFE_RE="$PY_SAFE_RE"'|^\s*(ruff\s+(check|format)|black\s|isort\s|flake8\s|pylint\s|mypy\s|pyright\s)'
PY_SAFE_RE="$PY_SAFE_RE"'|^\s*(pip\s+list|pip\s+show|pip\s+freeze|pipdeptree)(\s|$)'
PY_SAFE_RE="$PY_SAFE_RE"'|^\s*python3?\s+-m\s+py_compile\s'

cc_every_segment_matches "$PY_SAFE_RE" "$COMMAND" || exit 0

# Python test runners
if echo "$COMMAND" | grep -qE '^\s*(pytest|python\s+-m\s+pytest|python\s+-m\s+unittest)(\s|$)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Python test auto-approved"}}'
    exit 0
fi

# Linters and formatters
if echo "$COMMAND" | grep -qE '^\s*(ruff\s+(check|format)|black\s|isort\s|flake8\s|pylint\s|mypy\s|pyright\s)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Python lint/format auto-approved"}}'
    exit 0
fi

# Package management (read-only)
if echo "$COMMAND" | grep -qE '^\s*(pip\s+list|pip\s+show|pip\s+freeze|pipdeptree)(\s|$)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"pip read-only auto-approved"}}'
    exit 0
fi

# Python syntax check
if echo "$COMMAND" | grep -qE '^\s*python3?\s+-m\s+py_compile\s'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Python compile check auto-approved"}}'
    exit 0
fi

exit 0
