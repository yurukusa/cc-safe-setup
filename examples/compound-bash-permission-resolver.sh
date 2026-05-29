#!/bin/bash
# compound-bash-permission-resolver.sh — Per-component allow-rule check for compound bash
#
# Solves: Cluster 6 Axis 1 — wildcard rules like Bash(git status:*) match
#         a bare `git status` but not `cd repo && git status`, even though
#         the rule should logically cover the second. The operator who
#         configured the rule sees a permission prompt with no way to tell
#         whether their rule "should have" covered.
#
# Issues addressed: #28240 (180 reactions), #32985 (24 reactions),
#         meta-issue #30519 Axis 1.
#
# How it works: PreToolUse hook on Bash. When the command contains a
#   compound separator (&&, ||, ;, |), the hook splits it into components
#   and checks each component against the Bash() patterns configured in
#   permissions.allow across the four standard settings locations.
#
#   The advisory tells the operator one of two things:
#     - all N components match an existing pattern individually, so the
#       prompt is the Axis 1 false positive — safe to approve, but
#       "Always Allow" will save the verbatim compound, not the patterns
#     - K of N components match, the remainder do not — the prompt is
#       firing on a genuinely new tool surface
#
#   This hook NEVER blocks. It always exits 0. It only reads settings.
#
# Heuristic limitations: the splitter does not understand shell quoting,
#   heredocs, or subshell expansions ($(...)). Compounds embedded in
#   quoted arguments may be misparsed. The advisory is conservative:
#   when ambiguous, it counts an unmatched segment as uncovered, which
#   nudges the operator toward inspection rather than blind approval.
#
# Environment variables:
#   CC_COMPOUND_RESOLVER_DISABLE=1 — disable the advisory entirely
#   CC_COMPOUND_RESOLVER_VERBOSE=1 — print resolver breakdown
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -uo pipefail

INPUT=$(cat)

# Fail-open on missing input or jq parse errors.
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

[ "${CC_COMPOUND_RESOLVER_DISABLE:-0}" = "1" ] && exit 0

# Detect compound separator. Order matters: check && and || before single |.
IS_COMPOUND=0
case "$COMMAND" in
    *"&&"*|*"||"*|*";"*) IS_COMPOUND=1 ;;
esac
# Single pipe (not part of ||): look for "|" with no adjacent "|".
if [ "$IS_COMPOUND" = "0" ] && \
   printf '%s' "$COMMAND" | grep -qE '([^|]\|[^|]|^\|[^|]|[^|]\|$)'; then
    IS_COMPOUND=1
fi
[ "$IS_COMPOUND" = "0" ] && exit 0

# Collect Bash() allow patterns from all four standard settings locations.
PATTERNS_FILE=$(mktemp)
trap 'rm -f "$PATTERNS_FILE"' EXIT
for CFG in \
    "${HOME}/.claude/settings.json" \
    "${HOME}/.claude/settings.local.json" \
    "./.claude/settings.json" \
    "./.claude/settings.local.json"; do
    [ -f "$CFG" ] || continue
    jq -r '.permissions.allow // [] | .[] | select(type == "string" and startswith("Bash("))' \
        "$CFG" 2>/dev/null >> "$PATTERNS_FILE" || true
done

# If no Bash() patterns are configured, the resolver has nothing to say.
[ ! -s "$PATTERNS_FILE" ] && exit 0

# Split COMMAND on compound separators (&& || ; |) into one-per-line segments.
# Order: collapse && and || to newlines first so single | doesn't get
# erroneously split inside ||.
SEGMENTS=$(printf '%s' "$COMMAND" \
    | sed -E 's/&&/\n/g; s/\|\|/\n/g; s/;/\n/g' \
    | sed 's/|/\n/g')

COVERED_COUNT=0
TOTAL=0
UNCOVERED_LIST=""

while IFS= read -r SEG; do
    SEG=$(printf '%s' "$SEG" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [ -z "$SEG" ] && continue

    # Strip leading env-var assignments (FOO=bar BAZ=qux cmd ...).
    WORK="$SEG"
    while printf '%s' "$WORK" | grep -qE '^[A-Z_][A-Z0-9_]*=[^[:space:]]+[[:space:]]+'; do
        WORK=$(printf '%s' "$WORK" | sed -E 's/^[A-Z_][A-Z0-9_]*=[^[:space:]]+[[:space:]]+//')
    done

    read -r BIN ARG1 _ <<< "$WORK"
    [ -z "${BIN:-}" ] && continue

    TOTAL=$((TOTAL+1))
    BIN_BASE=$(basename "$BIN")

    MATCHED=0
    # Subcommand-level pattern: Bash(<bin> <arg1>:*)
    if [ -n "${ARG1:-}" ] && printf '%s' "$ARG1" | grep -qE '^[a-zA-Z][a-zA-Z0-9_-]*$'; then
        if grep -Fxq "Bash($BIN_BASE $ARG1:*)" "$PATTERNS_FILE"; then
            MATCHED=1
        fi
    fi
    # Binary-level pattern fallback: Bash(<bin>:*)
    if [ "$MATCHED" = "0" ] && grep -Fxq "Bash($BIN_BASE:*)" "$PATTERNS_FILE"; then
        MATCHED=1
    fi

    if [ "$MATCHED" = "1" ]; then
        COVERED_COUNT=$((COVERED_COUNT+1))
    else
        UNCOVERED_LIST="${UNCOVERED_LIST}${BIN_BASE} "
    fi
done <<< "$SEGMENTS"

# A "compound" with one or zero meaningful segments isn't worth flagging.
[ "$TOTAL" -lt 2 ] && exit 0

{
    echo "[compound-bash-permission-resolver] Compound bash detected (${TOTAL} components)."
    echo ""
    if [ "$COVERED_COUNT" = "$TOTAL" ]; then
        echo "All ${TOTAL} components match an existing Bash() allow pattern when evaluated"
        echo "individually. The permission prompt is likely Cluster 6 Axis 1 — the matching"
        echo "engine does not recompose compound bash against allow rules per-component."
        echo "(meta-issue #30519 Axis 1; #28240 with 180 reactions)"
        echo ""
        echo "Safe to approve: each component is already covered standalone."
        echo "Note: \"Always Allow\" will save the verbatim compound string,"
        echo "not the per-component patterns — variants of this compound will re-prompt."
    else
        UNCOVERED_TRIMMED=$(printf '%s' "$UNCOVERED_LIST" | sed -E 's/[[:space:]]+$//')
        echo "Coverage: ${COVERED_COUNT} of ${TOTAL} components match an allow pattern."
        echo "Uncovered components (binary names): ${UNCOVERED_TRIMMED}"
        echo ""
        echo "The prompt is firing on the uncovered component(s) above, not on the"
        echo "compound shape itself. Add Bash(<bin>:*) patterns for the uncovered"
        echo "binaries to permissions.allow if you want to skip future prompts."
    fi
    if [ "${CC_COMPOUND_RESOLVER_VERBOSE:-0}" = "1" ]; then
        PCOUNT=$(wc -l < "$PATTERNS_FILE")
        echo ""
        echo "(resolver breakdown: total=${TOTAL} covered=${COVERED_COUNT} patterns_loaded=${PCOUNT})"
    fi
} >&2

# Always exit 0 — this hook never blocks.
exit 0
