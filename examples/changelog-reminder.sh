#!/bin/bash
# ================================================================
# changelog-reminder.sh — Remind to update CHANGELOG on version bump
# ================================================================
# PURPOSE:
#   When Claude bumps a version number (npm version, cargo set-version,
#   etc.), this hook reminds to update CHANGELOG.md with the changes.
#
# TRIGGER: PostToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Detect version bump commands
if echo "$COMMAND" | grep -qE '(npm\s+version|cargo\s+set-version|bump2version|poetry\s+version)'; then
    if [ -f "CHANGELOG.md" ]; then
        echo "REMINDER: Update CHANGELOG.md with the new version's changes." >&2
    fi
fi

exit 0
