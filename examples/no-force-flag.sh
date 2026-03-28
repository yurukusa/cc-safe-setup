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
# MATCHER: "Bash"
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# npm install --force / --legacy-peer-deps
if echo "$COMMAND" | grep -qE 'npm\s+install.*--force|npm\s+i\s.*--force'; then
    echo "BLOCKED: npm install --force bypasses peer dependency checks." >&2
    echo "Fix the dependency conflict instead of forcing." >&2
    exit 2
fi

# git push --force (not --force-with-lease)
if echo "$COMMAND" | grep -qE 'git\s+push.*--force($|\s)' && ! echo "$COMMAND" | grep -q 'force-with-lease'; then
    echo "BLOCKED: git push --force can destroy remote history." >&2
    echo "Use --force-with-lease for safer force-push." >&2
    exit 2
fi

# docker system prune --force
if echo "$COMMAND" | grep -qE 'docker\s+(system\s+)?prune.*-f|docker\s+(system\s+)?prune.*--force'; then
    echo "BLOCKED: docker prune --force removes all unused data without confirmation." >&2
    exit 2
fi

exit 0
