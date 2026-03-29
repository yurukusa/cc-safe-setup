#!/bin/bash
# skill-injection-detector.sh — Detect silently injected skills/plugins
#
# Solves: Skills and plugins from claude.ai silently injected into Claude Code
#         sessions (#39686). External tool definitions bloat context and
#         can override local behavior without user awareness.
#
# How it works: Notification hook that monitors for unexpected skill/plugin
#   loading messages. Warns when tools are loaded from external sources.
#   Also checks MCP config for unexpected servers.
#
# TRIGGER: PreToolUse
# MATCHER: ""

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Check MCP tool calls for unexpected servers
if [ "$TOOL" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  # Detect MCP server addition
  if echo "$COMMAND" | grep -qE 'claude\s+mcp\s+add'; then
    echo "WARNING: MCP server addition detected." >&2
    echo "Command: $COMMAND" >&2
    echo "Verify this server is expected before proceeding." >&2
  fi
fi

# Check for skill/plugin invocation from unexpected sources
if echo "$INPUT" | jq -e '.tool_input.skill // empty' 2>/dev/null | grep -qv '^$'; then
  SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill' 2>/dev/null)
  # Check if skill is local
  if [ ! -f ".claude/skills/${SKILL}/SKILL.md" ] && [ ! -f ".claude/skills/${SKILL}.md" ]; then
    echo "WARNING: Skill '$SKILL' invoked but not found locally." >&2
    echo "This may be an externally injected skill." >&2
  fi
fi

exit 0
