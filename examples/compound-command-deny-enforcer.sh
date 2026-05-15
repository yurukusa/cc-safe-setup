#!/bin/bash
# ================================================================
# compound-command-deny-enforcer.sh — Enforce deny rules across compound commands
# ================================================================
# PURPOSE:
#   Claude Code's permission system does not catch compound commands.
#   `Bash(git push:*)` in `ask`/`deny` does not match `cd /path && git push`.
#
#   The harness strips idempotent `cd` prefixes (when cd target == cwd),
#   but `cd /different/path && <denied-cmd>` is NOT stripped, and the
#   permission system evaluates the pre-split string starting with `cd`,
#   matching no deny/ask rule.
#
#   Reported repeatedly since December 2025:
#     #13371, #28784, #29491, #20085, #37621, and #59498 (May 2026).
#
#   This hook enforces deny rules at the component level: it splits
#   compound commands and blocks if ANY component matches the deny list.
#
#   Operator-side fix while the upstream issue remains unresolved.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# HOW IT WORKS:
#   1. Splits command on &&, ||, ;
#   2. Strips leading cd <path> tokens from each component
#   3. Checks each remaining component against the deny patterns
#   4. If ANY component matches any pattern → exit 2 (block)
#   5. Otherwise → exit 0 (no opinion, defer to next hook)
#
# CONFIGURATION:
#   Default patterns cover the most common irreversible operations.
#   To add patterns, edit DEFAULT_DENY array below or read from a config file.
#
# WHAT THIS HOOK DOES NOT DO:
#   - Replace settings.json deny rules — it complements them by catching
#     the cd-prefixed compound bypass that settings.json misses.
#   - Block all compound commands — only those where a component matches
#     the deny list.
#   - Approve safe commands — that is compound-command-approver.sh's job.
#
# RELATED:
#   - compound-command-approver.sh (auto-approves safe compound chains)
#   - banned-command-guard.sh (blocks single banned commands)
#   - GitHub issues #13371, #28784, #29491, #20085, #37621, #59498
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

[ -z "$COMMAND" ] && exit 0

# Default deny patterns — irreversible operations the operator should
# always be prompted about, even when reached via cd-prefixed compound.
# Each entry is a POSIX ERE matched against each component after cd-stripping.
DEFAULT_DENY=(
    'git[[:space:]]+push([[:space:]]|$)'
    'git[[:space:]]+reset[[:space:]]+--hard'
    'git[[:space:]]+clean[[:space:]]+-[a-z]*f'
    'git[[:space:]]+filter-(repo|branch)'
    'rm[[:space:]]+-[a-z]*r[a-z]*f'
    'dd[[:space:]]+if=.*of='
    'mkfs(\.|[[:space:]])'
    '>[[:space:]]*/dev/sd[a-z]'
)

# Split on &&, ||, ;
SPLIT=$(echo "$COMMAND" | sed -E 's/(&&|\|\||;)/\n/g')

# Strip leading "cd <path>" from a component
strip_cd() {
    echo "$1" | sed -E 's/^[[:space:]]*cd[[:space:]]+([^[:space:]&|;]+|"[^"]*"|'\''[^'\'']*'\'')[[:space:]]*//'
}

# Iterate components and check each against deny patterns.
# Use a here-string + for loop so exit 2 propagates (subshell pipe loses it).
EXIT_CODE=0
while IFS= read -r component; do
    [ -z "$component" ] && continue

    stripped=$(strip_cd "$component")
    [ -z "$stripped" ] && continue

    for pattern in "${DEFAULT_DENY[@]}"; do
        if echo "$stripped" | grep -qE "$pattern"; then
            cat >&2 <<EOF
BLOCKED: Compound-command deny enforcer matched a denied operation.

Full command:  $COMMAND
Component:     $stripped
Matched rule:  $pattern

This hook catches the cd-prefixed compound bypass documented in
https://github.com/anthropics/claude-code/issues/59498 (and historical
#13371, #28784, #29491, #20085, #37621). Settings.json deny rules do
not match cd-prefixed compounds because the harness does not strip
cd <path> when path differs from cwd; the permission system then
evaluates the pre-split string starting with cd and matches no rule.

To unblock for one command, run the components separately:
  cd /path
  <denied-command>
EOF
            EXIT_CODE=2
            break 2
        fi
    done
done <<< "$SPLIT"

exit "$EXIT_CODE"
