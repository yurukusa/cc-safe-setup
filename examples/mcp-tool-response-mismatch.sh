#!/bin/bash
# ================================================================
# mcp-tool-response-mismatch.sh — Detect MCP relay claim/reality gap
# ================================================================
# PURPOSE:
#   MCP relays report `connected · N tools` in `/mcp` status output,
#   but tool invocations sometimes fail with disconnection errors
#   ("Browser extension is not connected", "Tools not exposed",
#   "MCP server not responding"). The /mcp status claim and the
#   runtime tool response diverge.
#
#   Issue #58553 documents claude-in-chrome MCP showing 20 tools as
#   connected, with every tool call returning "Browser extension is
#   not connected". Issue #58506 documents the GitLab MCP server
#   connecting but tools not being exposed to Claude's context.
#
# WHAT THIS HOOK DOES:
#   On PostToolUse for any mcp__* tool call, inspect the tool
#   response for disconnection error patterns. If found, exit 2
#   with a notice instructing the operator to verify the MCP
#   relay state (the /mcp status claim has diverged from the
#   runtime reality).
#
#   This hook does not block valid uses — only ones where the
#   response itself reports a disconnection error.
#
# TRIGGER: PostToolUse
# MATCHER: "mcp__.*"  (any MCP tool)
#
# CONFIGURATION:
#   CC_MCP_MISMATCH_DISABLE=1  — set to 1 to disable this hook
#   CC_MCP_MISMATCH_EXTRA_PATTERNS — colon-separated additional
#     regex patterns to treat as disconnection errors
#
# STATE: ~/.claude/state/mcp-mismatch-log.jsonl
#   Append-only log of detected mismatches with timestamp,
#   tool name, and matched pattern for auditing.
#
# REFERENCES:
#   - Issue #58553 (claude-in-chrome 20 tools claim vs all-fail reality)
#   - Issue #58506 (GitLab MCP connects but tools not exposed)
#   - Claim-Verify Handbook Part 1 Chapter 3 (environment-verification
#     impossibility) — same structural pattern
# ================================================================

# Allow disable
if [[ "${CC_MCP_MISMATCH_DISABLE:-0}" == "1" ]]; then
    exit 0
fi

INPUT=$(cat)

# Only fire on mcp__* tools
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [[ ! "$TOOL" =~ ^mcp__ ]]; then
    exit 0
fi

# Get the tool response body
# Hook payload format (PostToolUse):
#   { "tool_name": "...", "tool_response": {...} or "...", ... }
RESPONSE=$(echo "$INPUT" | jq -r '
    .tool_response //
    .tool_output //
    .response //
    empty
    | if type == "string" then .
      elif type == "object" then (tostring)
      else (tostring) end
' 2>/dev/null)

if [[ -z "$RESPONSE" ]]; then
    exit 0
fi

# Default disconnection error patterns (case-insensitive substrings)
# Each line is one pattern (extended regex)
DEFAULT_PATTERNS=$(cat <<'EOF'
browser extension is not connected
extension is not connected
mcp server not responding
mcp server is not connected
not connected to mcp
not connected to claude
relay not connected
tools not exposed
no tools available
tool not registered
tool not found in mcp
mcp connection lost
mcp handshake failed
mcp server unavailable
disconnected from mcp
EOF
)

# Allow extra patterns via env (colon-separated)
EXTRA="${CC_MCP_MISMATCH_EXTRA_PATTERNS:-}"
if [[ -n "$EXTRA" ]]; then
    EXTRA_LINES=$(echo "$EXTRA" | tr ':' '\n')
    DEFAULT_PATTERNS="${DEFAULT_PATTERNS}
${EXTRA_LINES}"
fi

# Check each pattern (case-insensitive)
MATCHED_PATTERN=""
while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    if echo "$RESPONSE" | grep -iqF "$pattern"; then
        MATCHED_PATTERN="$pattern"
        break
    fi
done <<< "$DEFAULT_PATTERNS"

if [[ -z "$MATCHED_PATTERN" ]]; then
    exit 0
fi

# Mismatch detected. Log and warn.
STATE_DIR="${HOME}/.claude/state"
STATE_FILE="${STATE_DIR}/mcp-mismatch-log.jsonl"
mkdir -p "$STATE_DIR"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
LOG_ENTRY=$(jq -nc \
    --arg ts "$TS" \
    --arg sid "$SESSION_ID" \
    --arg tool "$TOOL" \
    --arg pattern "$MATCHED_PATTERN" \
    --arg response_preview "${RESPONSE:0:200}" \
    '{timestamp: $ts, session_id: $sid, tool: $tool, matched_pattern: $pattern, response_preview: $response_preview}')
echo "$LOG_ENTRY" >> "$STATE_FILE"

cat >&2 <<EOF
[mcp-tool-response-mismatch] MCP relay claim/reality divergence detected.

Tool: $TOOL
Response contains: "$MATCHED_PATTERN"
Response preview: ${RESPONSE:0:200}

The /mcp status output likely claims this relay is connected, but the
runtime tool response reports a disconnection. This pattern matches
issue #58553 (claude-in-chrome reporting 20 connected tools while all
tool calls fail) and issue #58506 (GitLab MCP reporting connected
while tools are not exposed).

Suggested actions:
  - Run /mcp status and verify the relay's reported state
  - Restart the MCP relay if the divergence persists
  - Set CC_MCP_MISMATCH_DISABLE=1 to suppress this hook for this session

Log: $STATE_FILE
EOF

exit 2
