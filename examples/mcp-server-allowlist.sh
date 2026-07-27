#!/bin/bash
# mcp-server-allowlist.sh — Restrict MCP tool calls to allowed servers
#
# Solves: Unwanted MCP servers (synced from claude.ai) injecting tools
#         that consume memory and cause OOM crashes (#20412).
#         Also prevents untrusted MCP tools from being called.
#
# How it works: PreToolUse hook that checks if a tool call is from an
#   MCP server, and blocks it if the server isn't in the allowlist.
#
# CONFIG:
#   CC_MCP_ALLOWED="filesystem:github:memory" (colon-separated server names)
#
# TRIGGER: PreToolUse
# MATCHER: ""

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

ALLOWED="${CC_MCP_ALLOWED:-}"
[ -n "$ALLOWED" ] || exit 0  # No allowlist = allow all

# MCP tools are prefixed with mcp__servername__
case "$TOOL" in
    mcp__*__*)
        # Extract server name
        SERVER=$(echo "$TOOL" | sed 's/^mcp__\([^_]*\)__.*/\1/')

        IFS=':' read -ra SERVERS <<< "$ALLOWED"
        for s in "${SERVERS[@]}"; do
            [ "$s" = "$SERVER" ] && exit 0
        done

        echo "BLOCKED: MCP tool from non-allowed server '$SERVER'." >&2
        echo "  Tool: $TOOL" >&2
        echo "  Allowed servers: $ALLOWED" >&2
        echo "  Add to CC_MCP_ALLOWED to permit." >&2
        exit 2
        ;;
esac

exit 0
