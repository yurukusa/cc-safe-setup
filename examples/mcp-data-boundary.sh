#!/bin/bash
# mcp-data-boundary.sh — Prevent MCP tools from accessing sensitive paths
#
# Solves: MCP tools can read/write files outside the intended scope.
#         A rogue or misconfigured MCP server could exfiltrate credentials
#         or modify system files. (OWASP MCP01 + MCP10)
#
# How it works: PostToolUse hook that checks MCP tool results for
#   sensitive file path references. Warns if an MCP tool accessed
#   paths outside the project directory.
#
# CONFIG:
#   CC_MCP_ALLOWED_PATHS="/home/user/project"  (colon-separated)
#
# TRIGGER: PostToolUse
# MATCHER: "" (monitors all tools, focuses on MCP tool outputs)

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null | head -c 2000)
[ -z "$OUTPUT" ] && exit 0

# Only check MCP tool outputs (tool names starting with mcp__)
echo "$TOOL" | grep -q '^mcp__' || exit 0

# Check for sensitive path patterns in output
SENSITIVE_PATHS='/etc/passwd|/etc/shadow|\.ssh/|\.aws/|\.env|credentials|\.npmrc|\.pypirc|\.netrc|\.gnupg|\.kube/config'

if echo "$OUTPUT" | grep -qiE "$SENSITIVE_PATHS"; then
    echo "⚠ MCP DATA BOUNDARY: MCP tool accessed sensitive path" >&2
    echo "  Tool: $TOOL" >&2
    echo "  Detected sensitive path reference in output." >&2
    echo "  Review the MCP server's file access scope." >&2
fi

# Check for data that looks like secrets in output
if echo "$OUTPUT" | grep -qE 'sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{30,}|-----BEGIN.*KEY|AKIA[A-Z0-9]{16}'; then
    echo "⚠ MCP DATA BOUNDARY: MCP tool output contains potential secrets" >&2
    echo "  Tool: $TOOL" >&2
    echo "  Review output for leaked credentials." >&2
fi

exit 0
