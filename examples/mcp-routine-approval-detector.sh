#!/bin/bash
# mcp-routine-approval-detector.sh — Surface the May 2026 routine-approval cluster
#
# PROBLEM (cluster, active since ~2026-05-20):
#   Scheduled and Remote Claude.ai Routines silently fail every MCP tool call
#   on Anthropic-hosted connectors (Gmail, Calendar, Microsoft 365, Notion,
#   Slack, Datadog, Atlassian, Snowflake, Linear, Granola) with:
#
#     Streamable HTTP error: Error POSTing to endpoint:
#     MCP tool call requires approval
#
#   Cluster anchors: #61015 (52r/40c), #61027 (33r/18c), #61097 (6r/11c,
#   has architectural fix proposal), #61044 (3r/3c, open).
#
#   The routine has no UI surface to approve the prompt, so the call becomes
#   a permanent no-op. Custom user-registered MCP servers work fine in the
#   same routine — the bug is scoped to the CCR proxy's approval gate.
#
# HOW THIS HELPS:
#   PostToolUse hook on mcp__* matcher. Reads tool_result. If the error
#   string matches the cluster signature, writes a structured diagnostic
#   receipt under ~/.claude/state/mcp-routine-approval-blocks/ and emits
#   a stderr warning so the operator sees the silent failure.
#
#   The hook does NOT block the failure — the call has already failed on
#   the server side. The hook surfaces it.
#
# RECEIPT FORMAT (one JSON file per block):
#   {
#     "blocked_at": "2026-05-25T12:00:00Z",
#     "tool_name": "mcp__claude_ai_Gmail__search_threads",
#     "server": "claude_ai_Gmail",
#     "operation": "search_threads",
#     "session_id": "<from input>",
#     "error_excerpt": "Streamable HTTP error: ..."
#   }
#
# CONFIG (all optional):
#   CC_MCP_ROUTINE_BLOCK_DIR        receipt directory (default: ~/.claude/state/mcp-routine-approval-blocks)
#   CC_MCP_ROUTINE_BLOCK_DISABLE=1  skip the hook entirely
#   CC_MCP_ROUTINE_BLOCK_WEBHOOK    if set to a URL, POST a JSON body on each block
#   CC_MCP_ROUTINE_BLOCK_QUIET=1    suppress the stderr warning (still writes receipt)
#
# TRIGGER: PostToolUse
# MATCHER: mcp__.*
#
# OPERATOR NEXT STEPS (printed in stderr warning):
#   - Confirm cluster signature via the Fallback Architecture Gist:
#     https://gist.github.com/yurukusa/7ed7176a8e79ea4635995d717b9af703
#   - Subscribe to the open anchor for the fix-landed signal:
#     https://github.com/anthropics/claude-code/issues/61044
#   - Aggregate receipts to see how many blocks happened today:
#     find ~/.claude/state/mcp-routine-approval-blocks -mtime -1 | wc -l

set -u

[ "${CC_MCP_ROUTINE_BLOCK_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat)

# Need jq for structured field extraction; silent skip if missing
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

# Only inspect MCP tool calls
case "$TOOL" in
    mcp__*) ;;
    *) exit 0 ;;
esac

# Extract the tool result text (could be string or structured)
RESULT_TEXT=$(printf '%s' "$INPUT" | jq -r '
    .tool_result // .tool_response // "" |
    if type == "string" then .
    elif type == "object" then (.content // .text // .error // "" | tostring)
    elif type == "array" then map(tostring) | join(" ")
    else tostring end
' 2>/dev/null)

[ -z "$RESULT_TEXT" ] && exit 0

# Cluster signature: the exact error string the four anchor issues report
SIG_PRIMARY="MCP tool call requires approval"
SIG_SECONDARY="Streamable HTTP error"

# Both signatures present = high-confidence cluster match
if ! printf '%s' "$RESULT_TEXT" | grep -qF "$SIG_PRIMARY"; then
    exit 0
fi

# At this point we have a confirmed cluster hit. Write a receipt.
RECEIPT_DIR="${CC_MCP_ROUTINE_BLOCK_DIR:-${HOME}/.claude/state/mcp-routine-approval-blocks}"
if ! mkdir -p "$RECEIPT_DIR" 2>/dev/null; then
    # State dir not writable — silent skip per the existing-hook convention
    exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Server / operation extraction. Tool names look like mcp__<server>__<operation>
# where server can itself contain underscores (e.g. claude_ai_Gmail).
# The separator is the double underscore __, not a single _.
TOOL_REST="${TOOL#mcp__}"
SERVER="${TOOL_REST%%__*}"
OPERATION="${TOOL_REST#*__}"

# Truncate error excerpt to keep receipt files small
ERROR_EXCERPT=$(printf '%s' "$RESULT_TEXT" | head -c 400)

# Receipt filename: timestamp + tool + short hash of error
SAFE_TOOL=$(printf '%s' "$TOOL" | tr -c 'A-Za-z0-9_-' '_')
RECEIPT_NAME="${TIMESTAMP//:/-}-${SAFE_TOOL}.json"
RECEIPT_PATH="${RECEIPT_DIR}/${RECEIPT_NAME}"

if jq -nc \
    --arg ts "$TIMESTAMP" \
    --arg tool "$TOOL" \
    --arg server "$SERVER" \
    --arg op "$OPERATION" \
    --arg sid "$SESSION_ID" \
    --arg err "$ERROR_EXCERPT" \
    '{blocked_at: $ts, tool_name: $tool, server: $server, operation: $op, session_id: $sid, error_excerpt: $err}' \
    > "$RECEIPT_PATH" 2>/dev/null; then
    :
else
    # Receipt write failed — silent skip
    exit 0
fi

# Optional webhook
if [ -n "${CC_MCP_ROUTINE_BLOCK_WEBHOOK:-}" ] && command -v curl >/dev/null 2>&1; then
    curl -s --max-time 5 -X POST \
        -H "Content-Type: application/json" \
        --data-binary "@${RECEIPT_PATH}" \
        "$CC_MCP_ROUTINE_BLOCK_WEBHOOK" >/dev/null 2>&1 || true
fi

# Stderr warning unless quiet
if [ "${CC_MCP_ROUTINE_BLOCK_QUIET:-0}" != "1" ]; then
    cat >&2 <<EOF
mcp-routine-approval-detector: silent failure detected on $TOOL
  → cluster: #61015 / #61027 / #61097 / #61044 (May 2026 routine-approval regression)
  → receipt: $RECEIPT_PATH
  → fallback architecture: https://gist.github.com/yurukusa/7ed7176a8e79ea4635995d717b9af703
  → fix-landed signal: https://github.com/anthropics/claude-code/issues/61044
EOF
fi

exit 0
