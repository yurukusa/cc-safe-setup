#!/bin/bash
# quoted-flag-approver.sh — Auto-approve commands with quoted flag values
#
# Solves: "Command contains quoted characters in flag names" false positives
#         (#27957 — 70 reactions, breaks agentic workflows)
#
# After a Claude Code update, normal commands like:
#   git commit -m "fix bug"
#   bun run build --flag "value"
# trigger a confirmation prompt even when they match allowlist patterns.
#
# This PermissionRequest hook auto-approves these prompts when:
# 1. Every command position is in a safe list
# 2. The only "issue" is quoted characters in flag values
#
# TRIGGER: PermissionRequest
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "PermissionRequest": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/quoted-flag-approver.sh" }]
#     }]
#   }
# }
#
# Fixed 2026-08-03. The safe list held bare command *words* — `git`, `curl`,
# `chmod`, `sed`, `node`, `python3`, `npx` — and a word says nothing about what
# the command does. `git commit -m "fix"` and `git push --force origin main`
# have the same first word.
#
# Measured against the shipped copy, over 20 destructive or credential-reading
# commands with no separator in them at all: **15 were approved**, among them
# `git push --force`, `git reset --hard`, `git clean -fdx`, `chmod -R 777 /`,
# `curl … | sh`, `node -e '…rmSync…'` and `cat ~/.aws/credentials`.
#
# This is a different defect from the first-command-position one repaired in
# #937/#940/#941/#942/#943/#947, and mixing the two would produce a number that
# looks right and is not: nothing here was hiding past a separator. The
# granularity of the list was the problem. (The first-position defect was here
# too, and is fixed in the same pass.)
#
# Known limit: quotes are not parsed when splitting, so a separator inside a
# quoted string ends a segment early. That errs toward fewer approvals.

INPUT=$(cat)

# Only handle "quoted characters in flag names" prompts
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty' 2>/dev/null)
echo "$MESSAGE" | grep -qi "quoted characters in flag" || exit 0

# Extract the command being checked
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# A substitution or backtick carries a command no string-level read can see.
# This hook is about quoted flag values, not substitution, so it refuses them.
case "$COMMAND" in
    *'$('*|*'`'*) exit 0 ;;
esac

# Command words that carry no destructive form of their own. Anything that
# takes code as an argument (`node -e`, `python3 -c`, `npx`) or fetches and runs
# (`curl`, `wget`) is deliberately absent: for those the word says nothing.
cc_base_ok() {
    case "$1" in
        cat|head|tail|less|more|wc|file|stat|du|df|ls|tree|\
        which|whereis|type|realpath|readlink|basename|dirname|\
        grep|rg|ag|ack|sort|uniq|tr|cut|column|nl|rev|awk|\
        echo|printf|true|false|pwd|date|uname|hostname|whoami|id|\
        jq|yq|cd|\
        tsc|eslint|prettier|jest|vitest|pytest)
            return 0 ;;
    esac
    return 1
}

# Build tool subcommands that neither destroy history nor run fetched code.
# One line on purpose: inside single quotes a trailing backslash is a literal
# backslash-newline, not a continuation, and the pattern silently stops matching.
CC_SUBCMD_RE='^[[:space:]]*(git[[:space:]]+(status|log|diff|show|add|commit|branch|remote|describe|rev-parse|blame|shortlog|ls-files|ls-tree|fetch|stash[[:space:]]+(list|push|save))|npm[[:space:]]+(test|run|ci|ls|view|outdated)|yarn[[:space:]]+(test|run|info|why)|pnpm[[:space:]]+(test|run|list|why)|bun[[:space:]]+(test|run)|cargo[[:space:]]+(build|test|check|fmt|clippy|tree)|go[[:space:]]+(build|test|vet|fmt|list)|docker[[:space:]]+(ps|images|logs|inspect|version|info)|make[[:space:]]+[A-Za-z0-9_.-]+|pip[[:space:]]+(list|show|freeze)|python3[[:space:]]+-m[[:space:]]+(pytest|unittest|pip[[:space:]]+(list|show|freeze)))([[:space:]]|$)'

cc_subcommand_ok() {
    printf '%s' "$1" | grep -qE "$CC_SUBCMD_RE"
}

cc_segment_base() {
    printf '%s' "$1" \
        | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' \
        | awk '{print $1}' \
        | sed 's|.*/||'
}

# `git branch` reads; `git branch -D main` deletes one. Same first two words.
CC_GIT_DESTRUCTIVE_RE='^[[:space:]]*git[[:space:]]+(branch|tag)[[:space:]]+-([dDmM]|-delete|-move)([[:space:]]|$)'

cc_segment_ok() {
    local seg="$1" base
    base=$(cc_segment_base "$seg")
    [ -z "$base" ] && return 1

    if [ "$base" = "find" ]; then
        printf '%s' "$seg" \
            | grep -qE '(^|[[:space:]])-(delete|exec|execdir|ok|okdir|fprintf?|fls|fprint0)([[:space:]]|$)' \
            && return 1
        return 0
    fi
    if [ "$base" = "sed" ]; then
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*i' && return 1
        return 0
    fi

    cc_base_ok "$base" && return 0
    printf '%s' "$seg" | grep -qE "$CC_GIT_DESTRUCTIVE_RE" && return 1
    cc_subcommand_ok "$seg" && return 0
    return 1
}

# A redirection writes a file, whatever the command word says.
case "$COMMAND" in
    *'>'*) exit 0 ;;
esac

IDX=0
while IFS= read -r SEG; do
    SEG="${SEG#"${SEG%%[![:space:]]*}"}"
    SEG="${SEG%"${SEG##*[![:space:]]}"}"
    [ -z "$SEG" ] && continue
    cc_segment_ok "$SEG" || exit 0
    IDX=$((IDX + 1))
done <<EOF
$(printf '%s' "$COMMAND" | tr ';&|' '\n\n\n')
EOF

[ "$IDX" -eq 0 ] && exit 0

echo '{"permissionDecision":"allow"}'
exit 0
