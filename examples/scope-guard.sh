#!/bin/bash
# scope-guard.sh — Block file operations outside the project directory
#
# Solves: Claude Code deleting files on Desktop, in ~/Applications,
# or anywhere outside the working directory (#36233, #36339)
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/scope-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-scope-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [scope-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ "$TOOL" != "Bash" ]] && exit 0
[[ -z "$CMD" ]] && exit 0

# Remove the parts of the command that are DATA, not instructions, before matching.
#
# Why this is needed at all: writing the name of a destructive command inside a file,
# a commit message or a heredoc used to trip this guard. A guard that fires on prose
# gets uninstalled, which is worse than a guard that never existed.
#
# Why the previous version was wrong in BOTH directions (measured 2026-09-16, and the
# measurements are in scripts/probe-skip-line-both-ways.sh so you can re-run them):
#   It read `^\s*(echo|printf|cat\s*<<)` and exited 0 on a match — it looked at the
#   START of the whole command only.
#   - It missed real damage: `echo starting && rm -rf /home/x` starts with echo, so the
#     rm was waved through. Four of seven probes were missed this way.
#   - It still fired on prose: `cat > note.md <<'EOF'` puts `>` between `cat` and `<<`,
#     so it never matched the skip pattern. Eight ways of writing the same harmless thing
#     split four-and-four on whether they were blocked.
#
# What is data and what is not: a heredoc body is data when the thing receiving it stores
# it (cat, tee, a file redirect). It is NOT data when the receiver executes it — `bash <<EOF`
# runs every line. Interpreters (python, node, ruby, perl, php) are also left in: their
# bodies can shell out, and being wrong in the direction of "looks safe" costs more.
strip_data_bodies() {
    awk '
    BEGIN { indoc = 0; delim = "" }
    {
        if (indoc) {
            probe = $0
            sub(/^[ \t]+/, "", probe)
            if (probe == delim) { indoc = 0; delim = "" }
            next
        }
        if (match($0, /<<-?[ \t]*("[^"]+"|'"'"'[^'"'"']+'"'"'|[A-Za-z_][A-Za-z0-9_]*)/)) {
            head = substr($0, 1, RSTART - 1)
            executes = 0
            if (head ~ /(^|[|;&(]|[ \t])(ba|z|k|da)?sh([ \t]|$)/) executes = 1
            if (head ~ /(^|[|;&(]|[ \t])(python[0-9.]*|node|ruby|perl|php)([ \t]|$)/) executes = 1
            if (!executes) {
                d = substr($0, RSTART, RLENGTH)
                sub(/^<<-?[ \t]*/, "", d)
                gsub(/["'"'"']/, "", d)
                delim = d
                indoc = 1
                print head
                next
            }
        }
        print
    }'
}

# A commit message is a string git stores; it is never executed. Blank it out so that
# "guard against rm -rf /x" as a commit message does not read as an rm.
CHECK=$(printf '%s' "$CMD" | strip_data_bodies \
        | sed -E 's/(git[[:space:]]+commit([[:space:]]+[^|;&]*)?[[:space:]]-m[[:space:]]*)("[^"]*"|'"'"'[^'"'"']*'"'"')/\1""/g')

# The arguments to echo and printf are written out, not run. Drop them too.
#
# This is the one piece the old skip line got right, and deleting that line took it away:
# right after the rewrite, `echo "... rm -rf /x ..." > note.md` started being blocked when
# it had passed before. Removing a sloppy check removes whatever it was quietly holding up.
#
# The difference from the old line: that one exited 0 for the WHOLE command as soon as it
# started with echo, so `echo hi && rm -rf /x` was waved through. This drops only the
# arguments and leaves everything after the next |, ; or & in place.
#
# Command substitution is the exception: in `echo $(rm -rf /x)` the substitution runs before
# echo ever sees it. If any is present anywhere, leave the command untouched.
case "$CHECK" in
    *'$('*|*'`'*) : ;;
    *) CHECK=$(printf '%s' "$CHECK" \
               | sed -E 's/(^|[|;&][[:space:]]*)(echo|printf)[[:space:]]+[^|;&]*/\1\2 /g') ;;
esac

# Check for destructive commands with paths outside project
if echo "$CHECK" | grep -qE '\brm\b.*(-[a-zA-Z]*[rf]|--(recursive|force))'; then
    # Block absolute paths
    if echo "$CHECK" | grep -qE '\brm\b[^|;]*\s+/[a-zA-Z]'; then
        echo "BLOCKED: rm with absolute path" >&2
        echo "Command: $CMD" >&2
        exit 2
    fi
    # Block home directory paths
    if echo "$CHECK" | grep -qE '\brm\b[^|;]*\s+~/'; then
        echo "BLOCKED: rm targeting home directory" >&2
        exit 2
    fi
    # Block parent directory escapes
    if echo "$CHECK" | grep -qE '\brm\b[^|;]*\s+\.\./'; then
        echo "BLOCKED: rm escaping project directory" >&2
        exit 2
    fi
fi

# Block targeting well-known user/system directories
if echo "$CHECK" | grep -qiE '\b(rm|del|Remove-Item)\b.*(Desktop|Applications|Documents|Downloads|Library|Keychain|\.aws|\.ssh)'; then
    echo "BLOCKED: targeting system/user directory" >&2
    exit 2
fi

exit 0
