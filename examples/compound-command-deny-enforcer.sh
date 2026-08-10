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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-compound-command-deny-enforcer-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [compound-command-deny-enforcer]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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

# The rm rule above matches `rm -rf <anything>`, so it also denied the most
# ordinary cleanup a developer types: `rm -rf node_modules`, `rm -rf dist`,
# `rm -rf build`, `rm -rf .next`. Measured 2026-08-10: all four exited 2 here,
# while rm-safety-net and auto-mode-safety-enforcer let the same commands
# through. A guard that blocks `rm -rf node_modules` does not get tightened by
# the user — it gets removed, and the cd-prefixed bypass this hook exists for
# comes back with it.
#
# The safe-target list and the match form are taken verbatim from
# rm-safety-net.sh rather than invented here, so the two hooks cannot drift
# into disagreeing about what "safe" means.
SAFE_RM_TARGETS="node_modules|dist|build|__pycache__|\.cache|\.pytest_cache|coverage|\.nyc_output|\.next|\.nuxt|tmp|temp"

# Returns 0 only when the component is an rm whose operands are ALL safe.
# Every operand is inspected, not just the last one: rm-safety-net documents
# that checking only `awk '{print $NF}'` lets `rm -rf /home/user/data node_modules`
# pass on its safe last argument. Path traversal disqualifies the whole
# component, and an rm with no operand at all is never treated as safe.
rm_targets_all_safe() {
    local comp="$1" arg seen=0
    case "$comp" in *'..'*) return 1 ;; esac
    set -f
    for arg in $(echo "$comp" | sed -E 's/^[[:space:]]*(sudo[[:space:]]+)?rm[[:space:]]+//'); do
        case "$arg" in
            -*) continue ;;                       # flags
        esac
        seen=1
        if ! echo "$arg" | grep -qE "^(\./)?(${SAFE_RM_TARGETS})/?$"; then
            set +f
            return 1
        fi
    done
    set +f
    [ "$seen" -eq 1 ]
}

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
            # Only the rm rule has a safe-target exemption. The other rules
            # (git push, reset --hard, dd, mkfs, …) have no benign form that
            # this hook should silently allow.
            if [ "$pattern" = 'rm[[:space:]]+-[a-z]*r[a-z]*f' ] && rm_targets_all_safe "$stripped"; then
                continue
            fi
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
