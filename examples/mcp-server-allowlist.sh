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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-mcp-server-allowlist-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [mcp-server-allowlist]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
