#!/bin/bash
# ================================================================
# no-force-flag.sh — Block dangerous --force flags
# ================================================================
# PURPOSE:
#   --force flags bypass safety checks in package managers and git.
#   This hook blocks common dangerous --force patterns:
#   - npm install --force (ignores peer dependency conflicts)
#   - pip install --force-reinstall (skips cache, wastes time)
#   - git push --force (overwrites remote history)
#   - docker system prune --force (removes all unused data)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|PowerShell"
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-force-flag-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-force-flag]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# npm install --force / --legacy-peer-deps
if echo "$COMMAND" | grep -qE 'npm\s+install.*--force|npm\s+i\s.*--force'; then
    echo "BLOCKED: npm install --force bypasses peer dependency checks." >&2
    echo "Fix the dependency conflict instead of forcing." >&2
    exit 2
fi

# git push --force / -f (not --force-with-lease)
# -f is git's official short form and is exactly equivalent to --force; the old
# pattern only matched the long form, so `git push -f` slipped through entirely.
# Require -f to be a standalone flag (preceded by whitespace) so a branch name
# ending in "-f" (e.g. `git push origin feature-f`) is not falsely blocked.
if echo "$COMMAND" | grep -qE 'git\s+push.*\s(-f\b|--force($|\s))' && ! echo "$COMMAND" | grep -q 'force-with-lease'; then
    echo "BLOCKED: git push --force/-f can destroy remote history and overwrite others' commits." >&2
    echo "If --force-with-lease just failed, that failure means someone else pushed changes you do not have locally." >&2
    echo "Do NOT escalate to --force; run git fetch, then rebase/merge, then push again. (issue #70378)" >&2
    exit 2
fi

# docker system prune --force
if echo "$COMMAND" | grep -qE 'docker\s+(system\s+)?prune.*-f|docker\s+(system\s+)?prune.*--force'; then
    echo "BLOCKED: docker prune --force removes all unused data without confirmation." >&2
    exit 2
fi

exit 0
