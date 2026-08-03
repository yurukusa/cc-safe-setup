#!/bin/bash
# ================================================================
# auto-approve-readonly.sh — Auto-approve all read-only commands
# ================================================================
# PURPOSE:
#   The #1 complaint: permission prompts for cat, ls, grep, find.
#   This hook auto-approves any command that only reads data,
#   while letting destructive commands go through normal approval.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Rewritten 2026-08-03. Two things were wrong, and they compounded.
#
#   1. The base command was taken from the FIRST word of the whole line, so
#      `cat README.md && sudo rm -rf app` produced the base `cat` and the
#      approval was handed to the entire line. Same defect as PR #937
#      (allowlist.sh), #940 (cd-git-allow.sh) and #941/#942 (the other
#      auto-approve hooks) — on the approving side, where the decision is an
#      explicit approval rather than a missed block.
#   2. `find` sat in the read-only list with no look at its predicates, so
#      `find . -name '*.log' -delete` was approved as a read-only command.
#      Redirections had the same shape: `cat x > out` writes a file and was
#      approved for reading one.
#
# Now every command position has to qualify on its own, and the forms that
# write are named. A line that does not qualify gets no decision, which leaves
# it to the normal permission flow — this hook only ever adds approval, it
# never blocks.
#
# Known limit: quotes are not parsed, so a separator inside a quoted string
# ends a segment early. That is the conservative direction here (fewer
# approvals, not more).
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# A substitution can carry a command that no string-level read sees.
case "$COMMAND" in
    *'$('*|*'`'*) exit 0 ;;
esac

# Anything that writes to a file is not a read, whatever the command word says.
case "$COMMAND" in
    *'>'*) exit 0 ;;
esac

# Commands that read and nothing else. `git` is handled separately below,
# because only some of its subcommands read.
cc_ro_base_ok() {
    case "$1" in
        cat|head|tail|less|more|wc|grep|rg|ag|ack|locate|\
        ls|ll|dir|tree|stat|file|which|whereis|type|realpath|\
        date|uptime|uname|hostname|whoami|id|groups|env|printenv|\
        pwd|df|du|free|top|ps|pgrep|lsof|netstat|ss|\
        jq|yq)
            return 0 ;;
    esac
    return 1
}

# Filters that only make sense downstream of something else. They stay out of
# the first position so that `sed …` on its own is not read as a read.
cc_filter_base_ok() {
    case "$1" in
        head|tail|grep|wc|sort|uniq|tr|cut|awk|sed|less|more|column|nl|rev)
            return 0 ;;
    esac
    return 1
}

cc_segment_base() {
    # strip leading blanks, leading VAR=value assignments, then take the command
    # word without its directory
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

    # find reads only while it carries no predicate that acts on what it finds
    if [ "$base" = "find" ]; then
        printf '%s' "$seg" \
            | grep -qE '(^|[[:space:]])-(delete|exec|execdir|ok|okdir|fprintf?|fls|fprint0)([[:space:]]|$)' \
            && return 1
        return 0
    fi

    # sed rewrites the file in place with -i
    if [ "$base" = "sed" ]; then
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*i' && return 1
    fi

    cc_ro_base_ok "$base" && return 0

    # git, only the subcommands that read
    if printf '%s' "$seg" | grep -qE '^[[:space:]]*git[[:space:]]+(status|log|diff|show|branch|remote|tag[[:space:]]+-l|blame|shortlog|describe|rev-parse|ls-files|ls-tree)([[:space:]]|$)'; then
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

echo '{"decision":"approve","reason":"Read-only command"}'
exit 0
