#!/bin/bash
# mcp-config-freeze.sh — Prevent MCP configuration changes during session
#
# Solves: Shadow MCP servers added mid-session (OWASP MCP09).
#         An agent or prompt injection could modify .mcp.json or
#         settings.json to add unauthorized MCP servers.
#
# How it works: On SessionStart, snapshots the current MCP config.
#   On subsequent Edit/Write to config files, compares against snapshot.
#   Blocks changes that add new MCP servers.
#
# Complements mcp-server-guard.sh (which blocks Bash-based server launches)
# by also covering config file modification.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check MCP-related config files
FILENAME=$(basename "$FILE")
case "$FILENAME" in
    .mcp.json|mcp.json|mcp-config.json)
        ;;
    settings.json|settings.local.json)
        # Check if the edit adds mcpServers
        CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
        if echo "$CONTENT" | grep -qiE '"mcpServers"|"mcp_servers"'; then
            echo "BLOCKED: MCP server configuration change detected" >&2
            echo "  File: $FILE" >&2
            echo "  MCP server additions require manual approval." >&2
            echo "  Edit the file manually or remove this hook temporarily." >&2
            exit 2
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac

# For .mcp.json files, block all modifications
echo "BLOCKED: MCP configuration file is frozen during this session" >&2
echo "  File: $FILE" >&2
echo "  To modify MCP config, edit the file manually outside Claude Code." >&2
exit 2
