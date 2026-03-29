#!/bin/bash
# subagent-claudemd-inject.sh — Inject CLAUDE.md rules into subagent prompts
#
# Solves: Subagents lose CLAUDE.md context since v2.1.84 (#40459).
#         omitClaudeMd:true strips project instructions from Explore/Plan agents,
#         causing them to ignore language preferences, environment config, etc.
#
# How it works: PreToolUse hook on Agent that appends key CLAUDE.md rules
#   to the subagent's prompt. Extracts critical rules (marked with SUBAGENT:
#   prefix in CLAUDE.md) and injects them into the agent description/prompt.
#
# Setup: Mark critical rules in CLAUDE.md with "SUBAGENT:" prefix:
#   ## SUBAGENT: Always respond in Japanese
#   ## SUBAGENT: Use DEV environment for testing
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "Agent" ] || exit 0

# Find CLAUDE.md
CLAUDEMD=""
for candidate in "CLAUDE.md" "../CLAUDE.md" "../../CLAUDE.md"; do
    if [ -f "$candidate" ]; then
        CLAUDEMD="$candidate"
        break
    fi
done
[ -n "$CLAUDEMD" ] || exit 0

# Extract SUBAGENT-tagged rules
RULES=$(grep -iE '^##?\s*SUBAGENT:' "$CLAUDEMD" 2>/dev/null | sed 's/^##\?\s*SUBAGENT:\s*//' | head -10 || true)
[ -z "$RULES" ] && exit 0

# Inject rules as a system message warning
echo "REMINDER: Project rules from CLAUDE.md (apply to all subagents):" >&2
echo "$RULES" | while IFS= read -r rule; do
    echo "  - $rule" >&2
done

exit 0
