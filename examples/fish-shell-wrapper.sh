#!/bin/bash
# ================================================================
# fish-shell-wrapper.sh — Run Bash tool commands in fish shell
# ================================================================
# PURPOSE:
#   Users who develop in fish lose PATH, aliases, and env vars because
#   Claude Code's Bash tool uses the system default shell (usually zsh/bash).
#   This hook wraps commands in `fish -c '...'` so they execute in fish.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# See: https://github.com/anthropics/claude-code/issues/7490
#
# Fixed 2026-08-03. This hook returned `permissionDecision: "allow"` on every
# command it wrapped — which is nearly every command, since the skip list held
# ten builtins. The approval was never a judgement about the command. It was the
# carrier for `updatedInput`, and the rewrite came with a signature attached.
#
# Measured against the shipped copy, over 20 destructive or credential-reading
# commands with no separator in them at all: **18 were approved**, including
# `sudo rm -rf`, `dd if=/dev/zero of=/dev/sda`, `mkfs.ext4`, `curl … | sh` and
# `git push --force`. This is a different defect from the first-command-position
# one fixed in #937/#940/#941/#942/#943/#947 — nothing here was being missed
# past a separator. The hook simply approved whatever it wrapped.
#
# Now the approval and the rewrite are separated:
#   - the command is rewritten for fish either way, because that is the job
#   - `permissionDecision: "allow"` is emitted only when every command position
#     qualifies on its own
#
# Whether `updatedInput` alone (with no decision) is honoured is not documented,
# and is deliberately not relied on here: if it is, an unqualified command gets
# wrapped and still goes through the normal permission prompt; if it is not, the
# command is not wrapped and goes through the normal permission prompt. Both
# branches end at the prompt, which is the point.
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Skip if already wrapped in fish
echo "$COMMAND" | grep -q '^fish -c' && exit 0

# Skip simple builtins that work identically in any shell
echo "$COMMAND" | grep -qE '^\s*(cd|echo|cat|ls|pwd|true|false|test|mkdir|touch|rm|cp|mv)\b' && exit 0

# ---------------------------------------------------------------- qualifying
# Command words that carry no destructive form of their own. `git` and the
# interpreters are handled below, because for those the word says nothing.
cc_base_ok() {
    case "$1" in
        cat|head|tail|less|more|wc|file|stat|du|df|ls|tree|\
        which|whereis|type|realpath|readlink|basename|dirname|\
        grep|rg|ag|ack|sort|uniq|tr|cut|column|nl|rev|\
        echo|printf|true|false|pwd|date|uname|hostname|whoami|id|\
        jq|yq|cd|\
        tsc|eslint|prettier|jest|vitest|pytest)
            return 0 ;;
    esac
    return 1
}

cc_segment_base() {
    printf '%s' "$1" \
        | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' \
        | awk '{print $1}' \
        | sed 's|.*/||'
}

# Build tool subcommands that neither destroy history nor run fetched code.
# One line on purpose: inside single quotes a trailing backslash is a literal
# backslash-newline, not a continuation, and the pattern silently stops matching.
CC_SUBCMD_RE='^[[:space:]]*(git[[:space:]]+(status|log|diff|show|add|commit|branch|remote|describe|rev-parse|blame|shortlog|ls-files|ls-tree|fetch|stash[[:space:]]+(list|push|save))|npm[[:space:]]+(test|run|ci|ls|view|outdated)|yarn[[:space:]]+(test|run|info|why)|pnpm[[:space:]]+(test|run|list|why)|bun[[:space:]]+(test|run)|cargo[[:space:]]+(build|test|check|fmt|clippy|tree)|go[[:space:]]+(build|test|vet|fmt|list)|docker[[:space:]]+(ps|images|logs|inspect|version|info)|make[[:space:]]+[A-Za-z0-9_.-]+|pip[[:space:]]+(list|show|freeze)|python3[[:space:]]+-m[[:space:]]+(pytest|unittest|pip[[:space:]]+(list|show|freeze)))([[:space:]]|$)'

# `git branch` reads; `git branch -D main` deletes one. Same first two words.
CC_GIT_DESTRUCTIVE_RE='^[[:space:]]*git[[:space:]]+(branch|tag)[[:space:]]+-([dDmM]|-delete|-move)([[:space:]]|$)'

cc_segment_ok() {
    local seg="$1" base
    base=$(cc_segment_base "$seg")
    [ -z "$base" ] && return 1

    # find reads only while no predicate acts on what it finds
    if [ "$base" = "find" ]; then
        printf '%s' "$seg" \
            | grep -qE '(^|[[:space:]])-(delete|exec|execdir|ok|okdir|fprintf?|fls|fprint0)([[:space:]]|$)' \
            && return 1
        return 0
    fi

    # sed rewrites the file in place with -i
    if [ "$base" = "sed" ]; then
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*i' && return 1
        return 0
    fi
    [ "$base" = "awk" ] && return 0

    cc_base_ok "$base" && return 0

    printf '%s' "$seg" | grep -qE "$CC_GIT_DESTRUCTIVE_RE" && return 1
    printf '%s' "$seg" | grep -qE "$CC_SUBCMD_RE" && return 0

    return 1
}

QUALIFIES=1

# A substitution or a backtick carries a command no string-level read can see.
case "$COMMAND" in
    *'$('*|*'`'*) QUALIFIES=0 ;;
esac
# A redirection writes.
case "$COMMAND" in
    *'>'*) QUALIFIES=0 ;;
esac

if [ "$QUALIFIES" -eq 1 ]; then
    IDX=0
    while IFS= read -r SEG; do
        SEG="${SEG#"${SEG%%[![:space:]]*}"}"
        SEG="${SEG%"${SEG##*[![:space:]]}"}"
        [ -z "$SEG" ] && continue
        if ! cc_segment_ok "$SEG"; then QUALIFIES=0; break; fi
        IDX=$((IDX + 1))
    done <<EOF
$(printf '%s' "$COMMAND" | tr ';&|' '\n\n\n')
EOF
    [ "$IDX" -eq 0 ] && QUALIFIES=0
fi

# ---------------------------------------------------------------- rewrite
# Escape single quotes for fish -c '...'
ESCAPED=$(printf '%s' "$COMMAND" | sed "s/'/'\\\\''/g")

if [ "$QUALIFIES" -eq 1 ]; then
    jq -n --arg cmd "fish -c '$ESCAPED'" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: { command: $cmd }
      }
    }'
else
    # rewrite without signing off on it
    jq -n --arg cmd "fish -c '$ESCAPED'" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        updatedInput: { command: $cmd }
      }
    }'
fi

exit 0
