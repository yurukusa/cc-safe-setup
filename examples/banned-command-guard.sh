#!/bin/bash
# banned-command-guard.sh — Block commands that are explicitly banned
#
# Solves: Claude using sed/awk/perl one-liners to edit files instead of
#         the built-in Edit tool, even when CLAUDE.md says "never use sed."
#         Real incident: #36413 — sed from wrong CWD emptied a key file,
#         then git checkout -- discarded 400 lines of uncommitted work.
#
# Why this matters:
#   CLAUDE.md bans are advisory. Claude can ignore them under context pressure.
#   This hook enforces the ban at the process level.
#
# Default banned commands (configurable via CC_BANNED_COMMANDS):
#   sed -i (in-place file editing — use Edit tool instead)
#   awk -i inplace (same reason)
#   perl -i / perl -pi (same reason — covers -i -pe, -pi -e, etc.)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Configuration:
#   CC_BANNED_COMMANDS — colon-separated list of regex patterns to block
#   Default: "sed -i:awk -i inplace:perl -pi:perl .*-i"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Configurable banned patterns (colon-separated)
BANNED="${CC_BANNED_COMMANDS:-sed\s+-i:awk\s+-i\s+inplace:perl\s+-pi:perl\s+.*-i}"

# Check each banned pattern
IFS=':' read -ra PATTERNS <<< "$BANNED"
for pattern in "${PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qE "$pattern"; then
        echo "BLOCKED: Command matches banned pattern." >&2
        echo "" >&2
        echo "Command: $COMMAND" >&2
        echo "Pattern: $pattern" >&2
        echo "" >&2
        echo "Use the built-in Edit tool instead of shell text processors." >&2
        echo "Edit tool preserves file encoding, handles unicode correctly," >&2
        echo "and shows diffs for review." >&2
        exit 2
    fi
done

exit 0
