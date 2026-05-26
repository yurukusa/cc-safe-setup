#!/bin/bash
# always-allow-pattern-suggester.sh — Suggest wildcard patterns instead of verbatim "Always Allow" rules
#
# Solves: Cluster 6 Axis 2 — "Always Allow" saves the verbatim command string
#         (commit message, exact filename, exact URL) instead of a wildcard
#         pattern. Over a working week, settings.local.json accumulates
#         hundreds of one-off dead rules while wildcard patterns the user
#         originally configured sit unused.
#
# Issues addressed: #6850 (45 reactions), #11380 (64 reactions, closed
#         without fix), #29187 (regression, no staff response), and the
#         meta-issue #30519 Axis 2 articulation.
#
# How it works: PreToolUse hook on Bash. When a command would trigger a
#   permission prompt, the hook computes the canonical wildcard pattern
#   the operator probably wants (e.g., Bash(git commit:*) for
#   `git commit -m "fix typo"`) and emits it as a stderr advisory.
#   Operator pastes the suggestion into settings.local.json once,
#   never sees the prompt for that command family again.
#
#   This hook NEVER blocks. It always exits 0. It is a wrapper around
#   the "Always Allow" UX, not a replacement.
#
# Existing-pattern check: reads ~/.claude/settings.json,
#   ~/.claude/settings.local.json, ./.claude/settings.json, and
#   ./.claude/settings.local.json. If the suggested pattern is already
#   in permissions.allow in any of them, no advisory is emitted
#   (the rule exists; the prompt is happening for a different reason).
#
# Environment variables:
#   CC_PATTERN_SUGGESTER_DISABLE=1 — disable the advisory entirely
#   CC_PATTERN_SUGGESTER_VERBOSE=1 — also print the canonical pattern
#                                    breakdown (binary + first arg)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -uo pipefail

INPUT=$(cat)

# Fail-open on missing input or jq parse errors.
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Allow operator to disable without removing the hook.
[ "${CC_PATTERN_SUGGESTER_DISABLE:-0}" = "1" ] && exit 0

# Extract the leading binary + first non-flag argument.
# Strip leading shell-prefix patterns (one or more env var assignments).
WORK_CMD="$COMMAND"
while printf '%s' "$WORK_CMD" | grep -qE '^\s*[A-Z_][A-Z0-9_]*=[^ ]+\s+'; do
    WORK_CMD=$(printf '%s' "$WORK_CMD" | sed -E 's/^\s*[A-Z_][A-Z0-9_]*=[^ ]+\s+//')
done
WORK_CMD=$(printf '%s' "$WORK_CMD" | sed -E 's/^\s+//')

# Split on shell-compound separators and take the FIRST simple command.
# (The operator may chain commands; the prompt fires on a specific tool
# match, but we only need to suggest a pattern for the leading verb.)
FIRST_SEG=$(printf '%s' "$WORK_CMD" | awk -F'[|&;]' '{print $1}' | sed -E 's/^\s+//; s/\s+$//')

# Tokenize the first segment by whitespace.
read -r BIN ARG1 _ <<< "$FIRST_SEG"

# Need at least a binary to suggest anything.
[ -z "${BIN:-}" ] && exit 0

# Strip path prefix from binary (e.g., /usr/bin/git → git).
BIN_BASE=$(basename "$BIN")

# Skip binaries that don't take subcommands or where wildcards
# wouldn't help (single-purpose tools).
case "$BIN_BASE" in
    ls|pwd|whoami|hostname|date|uname|true|false|echo|printf|cat|head|tail|wc|sort|uniq|tr|cut|awk|sed|grep|find|xargs|tee|sleep|test|[)
        # These are typically already covered by Bash(<bin>:*) wildcards;
        # if the operator already allowed them, no advisory needed.
        ;;
esac

# Determine if the first argument looks like a subcommand vs a flag/value.
# Subcommand: starts with a letter, no leading dash, no special chars.
PATTERN_BODY="$BIN_BASE"
IS_SUBCOMMAND=0
if [ -n "${ARG1:-}" ] && printf '%s' "$ARG1" | grep -qE '^[a-zA-Z][a-zA-Z0-9_-]*$'; then
    IS_SUBCOMMAND=1
    PATTERN_BODY="$BIN_BASE $ARG1"
fi

SUGGESTED="Bash($PATTERN_BODY:*)"

# Check if the pattern already exists in any settings file.
EXISTING=0
for CFG in \
    "${HOME}/.claude/settings.json" \
    "${HOME}/.claude/settings.local.json" \
    "./.claude/settings.json" \
    "./.claude/settings.local.json"; do
    [ -f "$CFG" ] || continue
    if jq -e --arg p "$SUGGESTED" '.permissions.allow // [] | any(. == $p)' "$CFG" >/dev/null 2>&1; then
        EXISTING=1
        break
    fi
done

# If pattern already exists, emit nothing; the prompt is for a different
# reason (compound bash, quote-tracking warning, etc.).
[ "$EXISTING" = "1" ] && exit 0

# Build the advisory.
{
    echo "[always-allow-pattern-suggester] If this command triggers a permission prompt,"
    echo "you can avoid future prompts for the same command family by adding this pattern"
    echo "to permissions.allow in .claude/settings.local.json:"
    echo ""
    echo "    \"$SUGGESTED\""
    echo ""
    echo "This is broader than the verbatim string \"Always Allow\" would save."
    if [ "${CC_PATTERN_SUGGESTER_VERBOSE:-0}" = "1" ]; then
        echo ""
        echo "(suggester breakdown: binary=$BIN_BASE; first_arg_is_subcommand=$IS_SUBCOMMAND)"
    fi
} >&2

# Always exit 0 — this hook never blocks.
exit 0
