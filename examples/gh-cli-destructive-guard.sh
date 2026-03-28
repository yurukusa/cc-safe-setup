#!/bin/bash
# gh-cli-destructive-guard.sh — Block destructive GitHub CLI operations
#
# Solves: Claude Code running dangerous gh commands without confirmation:
#   - Closing/deleting issues or PRs
#   - Deleting repos, releases, or branches
#   - Merging PRs without review
#   - Modifying repo settings
#
# The gh CLI is powerful but destructive operations should require
# explicit human approval, not AI autonomy.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Only check gh commands
echo "$COMMAND" | grep -qE '\bgh\s' || exit 0

# Block destructive issue operations
if echo "$COMMAND" | grep -qE 'gh\s+issue\s+(close|delete|lock|transfer)'; then
    echo "BLOCKED: Destructive GitHub Issue operation." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Block destructive PR operations
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+(close|merge|ready)'; then
    echo "BLOCKED: Destructive GitHub PR operation." >&2
    echo "  gh pr merge/close requires human review." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Block repo deletion
if echo "$COMMAND" | grep -qE 'gh\s+repo\s+delete'; then
    echo "BLOCKED: Repository deletion." >&2
    exit 2
fi

# Block release deletion
if echo "$COMMAND" | grep -qE 'gh\s+release\s+delete'; then
    echo "BLOCKED: Release deletion." >&2
    exit 2
fi

# Block branch deletion via gh
if echo "$COMMAND" | grep -qE 'gh\s+api\s+.*DELETE'; then
    echo "BLOCKED: Destructive GitHub API call (DELETE method)." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

exit 0
