#!/bin/bash
# ================================================================
# mcp-warmup-wait.sh — Wait for MCP servers to be ready on start
# ================================================================
# PURPOSE:
#   MCP servers take time to initialize after session start.
#   In Remote Trigger / scheduled sessions, the first turn often
#   fires before MCP tools are available. This hook adds a brief
#   delay on SessionStart to let MCP servers spin up.
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# WHY THIS MATTERS:
#   When Claude Code starts via Remote Trigger or cron, the
#   first message is sent immediately. MCP servers may not
#   be connected yet, causing "tool not available" errors
#   on the first turn. A short warmup delay fixes this.
#
# CONFIGURATION:
#   CC_MCP_WARMUP_SECONDS — seconds to wait (default: 3)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/41778
#   https://github.com/anthropics/claude-code/issues/35899
# ================================================================

WARMUP="${CC_MCP_WARMUP_SECONDS:-3}"

# Only wait if MCP servers are configured
MCP_CONFIG="${HOME}/.claude/settings.json"
if [ -f "$MCP_CONFIG" ]; then
    if grep -q '"mcpServers"' "$MCP_CONFIG" 2>/dev/null; then
        sleep "$WARMUP"
        printf 'MCP warmup: waited %ds for server initialization\n' "$WARMUP" >&2
    fi
fi

exit 0
