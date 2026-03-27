#!/bin/bash
# mcp-server-guard.sh — Block unauthorized MCP server configuration changes
#
# Solves: Shadow MCP servers being added without review (OWASP MCP09)
#         Prevents agents from silently adding MCP servers that could
#         exfiltrate data or inject malicious tool responses.
#
# Blocks:
#   - Writing to .mcp.json files
#   - Adding mcpServers entries to settings files
#   - Running npx/node commands that start new MCP servers
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write|Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Edit|Write|Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/mcp-server-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

case "$TOOL" in
  Edit|Write)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

    # Block direct MCP config file modification
    if echo "$FILE" | grep -qE '\.mcp\.json$|mcp-config\.json$'; then
      echo "BLOCKED: MCP server configuration change detected." >&2
      echo "  File: $FILE" >&2
      echo "  Review MCP server changes manually outside Claude Code." >&2
      exit 2
    fi

    # Block adding mcpServers to settings files
    if echo "$FILE" | grep -qE 'settings\.json$|settings\.local\.json$'; then
      CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
      if echo "$CONTENT" | grep -qiE 'mcpServers|mcp_servers'; then
        echo "BLOCKED: Adding MCP server configuration to settings." >&2
        echo "  MCP servers should be reviewed and added manually." >&2
        exit 2
      fi
    fi
    ;;

  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$CMD" ] && exit 0

    # Block commands that start MCP servers
    if echo "$CMD" | grep -qE 'npx.*@.*mcp|node.*mcp-server|python.*mcp.*server|mcp.*serve'; then
      # Allow known/approved MCP servers (customize this list)
      if echo "$CMD" | grep -qE '@playwright/mcp|godot-mcp'; then
        exit 0
      fi
      echo "BLOCKED: Unknown MCP server launch detected." >&2
      echo "  Command: $CMD" >&2
      echo "  Add to allowlist in mcp-server-guard.sh if trusted." >&2
      exit 2
    fi
    ;;
esac

exit 0
