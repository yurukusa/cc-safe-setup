#!/bin/bash
# ================================================================
# git-remote-guard.sh — Block push/fetch to unknown git remotes
# ================================================================
# PURPOSE:
#   Claude might add a new git remote and push code to it.
#   This hook warns when git push/fetch targets a remote that
#   wasn't in the original repo configuration.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Check for git remote add
if echo "$COMMAND" | grep -qE '\bgit\s+remote\s+add\b'; then
    echo "WARNING: Adding a new git remote." >&2
    echo "Command: $COMMAND" >&2
    echo "Verify this is a trusted repository." >&2
fi

# Check for push to a remote that is not origin.
#
# The previous version used `(?!origin\b)`, a lookahead that ERE does not have:
# grep -E rejected the pattern, returned 2, and the `if` was never true. The
# warning below could not fire on any input. Deciding "is it origin?" in the
# shell instead of the pattern removes the need for a lookahead entirely.
#
# `git` also accepts global options before the subcommand, so `git -C <dir>
# push upstream main` has to be matched as well (#1117).
GIT_OPT='(-[cC][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path|config-env|attr-source|super-prefix)(=[^[:space:]]+|[[:space:]]+[^[:space:]]+)|-[pP]|--(paginate|no-pager|bare|no-replace-objects|literal-pathspecs|glob-pathspecs|noglob-pathspecs|icase-pathspecs|no-optional-locks|no-lazy-fetch|no-advice))'
GIT_HEAD='(^|[[:space:];&|(]|/|"|'"'"')git'
GIT_PUSH_RE="${GIT_HEAD}([[:space:]]+${GIT_OPT})*[[:space:]]+push([[:space:]]|$)"

if echo "$COMMAND" | grep -qE "$GIT_PUSH_RE"; then
    # First bare word after `push` is the remote (flags and their values are
    # skipped). No remote at all means the default one, which is fine.
    REMOTE=$(echo "$COMMAND" | awk '{
        for (i = 1; i <= NF; i++) {
            if ($i == "push") { seen = 1; continue }
            if (!seen) continue
            if ($i ~ /^-/) { continue }
            print $i; exit
        }
    }')
    if [ -n "$REMOTE" ] && [ "$REMOTE" != "origin" ]; then
        echo "WARNING: Pushing to non-origin remote: $REMOTE" >&2
        echo "Verify this remote is trusted." >&2
    fi
fi

exit 0
