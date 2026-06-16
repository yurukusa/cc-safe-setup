#!/bin/bash
# commit-all-scope-guard.sh — Surface the full scope before a "commit everything"
#                             so in-progress work isn't swept into a commit.
#
# Solves (#68915): Claude tried to roll back its own change and ran a
# commit-everything (git commit -a / git add -A / git add .), which staged ALL
# modified + untracked files — including the user's unrelated in-progress edits —
# instead of only the files it had touched. commit-scope-guard.sh checks the
# already-STAGED count, so it never sees `git commit -a` (those files aren't in
# the index until commit time). This guard inspects the working tree and lists
# exactly what a commit-everything WOULD include, before it happens.
#
# Precision: warn (non-blocking) — the operation is legitimate and reversible
# (git reset --soft HEAD^), so we surface scope rather than block. It fires only
# on the commit-everything shapes, not on `git add <explicit paths>`.
#
# TRIGGER: PreToolUse   MATCHER: "Bash"

CMD=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Match: git commit -a / -am / --all ; git add -A / --all / . / -- .
COMMIT_ALL='git[[:space:]]+commit[[:space:]]+(-[a-zA-Z]*a|--all)'
ADD_ALL='git[[:space:]]+add[[:space:]]+(-A|--all|\.|-- \.)([[:space:]]|$)'
echo "$CMD" | grep -qE "$COMMIT_ALL|$ADD_ALL" || exit 0

# What would be swept in (tracked-modified + untracked), excluding ignored.
FILES=$(git status --porcelain 2>/dev/null)
[ -z "$FILES" ] && exit 0
COUNT=$(printf '%s\n' "$FILES" | grep -c .)

{
    echo "NOTE: this is a commit-everything — it will include ALL $COUNT changed/untracked"
    echo "file(s) below, not just the ones you edited. In-progress work gets swept in:"
    printf '%s\n' "$FILES" | head -12 | sed 's/^/  /'
    [ "$COUNT" -gt 12 ] && echo "  ... and $((COUNT-12)) more"
    echo ""
    echo "If you only meant some of these, stage them explicitly instead:"
    echo "  git add <path1> <path2> && git commit -m ..."
    echo "Already committed too much? Undo without losing anything:"
    echo "  git reset --soft HEAD^   # un-commits, keeps every change staged"
} >&2

exit 0
