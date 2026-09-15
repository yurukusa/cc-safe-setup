#!/bin/bash
# ================================================================
# git-operations-require-approval.sh — Block git write operations
# ================================================================
# PURPOSE:
#   Claude Code sometimes ignores CLAUDE.md rules about git commit,
#   push, and branch creation — performing these operations without
#   user approval. This hook enforces the restriction at process level.
#
# Blocks:
#   git commit, git push (including --force and `git send-pack`),
#   git checkout -b, git switch -c, git branch <name> - including when
#   they arrive with git's own global options in front, such as
#   `git -C <dir> push` or `git --git-dir=<path> commit` (#1117).
#
# Does NOT block:
#   git status, git log, git diff, git show, git branch (list),
#   git fetch, git stash, git add
#
# Handles compound commands (&&, ;, ||, |) by checking each segment.
#
# See: https://github.com/anthropics/claude-code/issues/40695
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-git-operations-require-approval-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [git-operations-require-approval]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# git accepts global options between `git` and the subcommand, so matching the
# two as adjacent words misses every one of these real shapes (reported in #1117
# with four working examples):
#     git -C /tmp/repo push --force origin main
#     git --git-dir=/tmp/r/repo.d push origin main
#     git -c user.name=x commit -m x
#     git send-pack origin main
# GIT_OPT is the set of options git itself accepts before a subcommand.
GIT_OPT='(-[cC][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path|config-env|attr-source|super-prefix)(=[^[:space:]]+|[[:space:]]+[^[:space:]]+)|-[pP]|--(paginate|no-pager|bare|no-replace-objects|literal-pathspecs|glob-pathspecs|noglob-pathspecs|icase-pathspecs|no-optional-locks|no-lazy-fetch|no-advice))'

# `git` at a command position, not the `git` inside a path. The old pattern
# matched `git --git-dir=/tmp/r/.git push` only because the *path* ended in
# `.git`, and let the same command through when the git-dir was named anything
# else (#1117). Quotes are allowed on purpose: `bash -c "git push ..."` runs.
GIT_HEAD='(^|[[:space:];&|(]|/|"|'"'"')git'

# Build "git [global options] <subcommand>" for one subcommand pattern.
git_re() {
    printf '%s([[:space:]]+%s)*[[:space:]]+%s' "$GIT_HEAD" "$GIT_OPT" "$1"
}

# Read-only front halves that mention a command without running it.
# This list is a guess about how people write, not a rule - `sed -i` and any
# wrapper not named here will still be inspected.
READ_ONLY_RE='^[[:space:]]*(echo|printf|grep|rg|cat|less|head|tail)[[:space:]]'

# Check each segment of compound commands
check_segment() {
    local seg="$1"
    # Trim whitespace
    seg=$(echo "$seg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$seg" ] && return 0

    # Exempt only THIS segment. Applying it to the whole command let
    # `echo hi && git push origin main` through completely.
    echo "$seg" | grep -qE "$READ_ONLY_RE" && return 0

    # git commit
    if echo "$seg" | grep -qE "$(git_re 'commit\b')|${GIT_HEAD}-commit\b"; then
        echo "BLOCKED: git commit requires explicit user approval." >&2
        echo "Command: $seg" >&2
        echo "" >&2
        echo "See: https://github.com/anthropics/claude-code/issues/40695" >&2
        return 1
    fi

    # git push (including force variants)
    if echo "$seg" | grep -qE "$(git_re '(push|send-pack)\b')|${GIT_HEAD}-(push|send-pack)\b"; then
        echo "BLOCKED: git push requires explicit user approval." >&2
        echo "Command: $seg" >&2
        echo "" >&2
        echo "See: https://github.com/anthropics/claude-code/issues/40695" >&2
        return 1
    fi

    # git checkout -b (branch creation)
    if echo "$seg" | grep -qE "$(git_re 'checkout[[:space:]]+(-b|--branch)\b')"; then
        echo "BLOCKED: git branch creation requires explicit user approval." >&2
        echo "Command: $seg" >&2
        return 1
    fi

    # git switch -c / --create (branch creation)
    if echo "$seg" | grep -qE "$(git_re 'switch[[:space:]]+(-c|--create)\b')"; then
        echo "BLOCKED: git branch creation requires explicit user approval." >&2
        echo "Command: $seg" >&2
        return 1
    fi

    # git branch <name> (creation, not listing)
    # git branch without flags or with only -a/-r/-l/--list is listing
    if echo "$seg" | grep -qE "$(git_re 'branch[[:space:]]')"; then
        # Allow listing flags
        if echo "$seg" | grep -qE "$(git_re 'branch[[:space:]]+(-[arl]|--list|--merged|--no-merged|--contains|-v|--verbose|-d|--delete|-D)\b')"; then
            return 0
        fi
        # If it has a name argument after "git branch", it's creation
        local args
        # The old sed required `git` and `branch` to be adjacent; with a
        # global option in between it stripped nothing and every listing form
        # looked like a creation. Strip up to the subcommand instead.
        args=$(echo "$seg" | sed -E 's/.*[[:space:]]branch[[:space:]]+//')
        if [ -n "$args" ] && ! echo "$args" | grep -qE '^\s*$'; then
            echo "BLOCKED: git branch creation requires explicit user approval." >&2
            echo "Command: $seg" >&2
            return 1
        fi
    fi

    return 0
}

# Split on && ; || | and check each part.
#
# A single `|` is a separator too. Without it, a read-only command piped into
# a git write arrives as ONE segment whose first word is the reader, and
# READ_ONLY_RE above exempts that whole segment - so the git write on the
# right-hand side of the pipe is never examined. Measured on the published
# file 2026-09-15: four piped shapes exited 0 while the same git operations
# exited 2 when written plainly.
#
# `||` is already turned into newlines by the rule before this one, so the
# single-pipe rule only ever sees real single pipes.
while IFS= read -r segment; do
    if ! check_segment "$segment"; then
        exit 2
    fi
done < <(echo "$COMMAND" | sed 's/&&/\n/g; s/;/\n/g; s/||/\n/g; s/|/\n/g')

exit 0
