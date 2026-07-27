#!/bin/bash
# mcp-tool-audit-log.sh — Log all MCP tool calls for security auditing
#
# Solves: No visibility into which MCP tools are being called, by whom,
#         and with what parameters. Essential for OWASP MCP Top 10
#         compliance (MCP09: Insufficient Logging).
#
# How it works: PostToolUse hook that logs MCP tool calls to a file
#   with timestamp, tool name, server, and input summary.
#
# CONFIG:
#   CC_MCP_AUDIT_LOG="~/.claude/mcp-audit.log"
#
# TRIGGER: PostToolUse
# MATCHER: ""

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

# Only log MCP tool calls
case "$TOOL" in
    mcp__*) ;;
    *) exit 0 ;;
esac

LOG_FILE="${CC_MCP_AUDIT_LOG:-${HOME}/.claude/mcp-audit.log}"
mkdir -p "$(dirname "$LOG_FILE")"

# Extract details
SERVER=$(echo "$TOOL" | sed 's/^mcp__\([^_]*\)__.*/\1/')
OPERATION=$(echo "$TOOL" | sed 's/^mcp__[^_]*__//')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exitCode // "0"' 2>/dev/null)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Log entry
echo "${TIMESTAMP} | server=${SERVER} | op=${OPERATION} | exit=${EXIT_CODE} | tool=${TOOL}" >> "$LOG_FILE"

exit 0
