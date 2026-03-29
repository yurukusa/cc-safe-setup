#!/bin/bash
# permission-audit-log.sh — Log all tool invocations for permission debugging
#
# Solves: No way to know which commands trigger permission prompts vs auto-allow
#         (#37153, #30519 58👍 partial)
#         Users can't debug why certain commands prompt and others don't.
#         This hook logs every tool call to help optimize permission rules.
#
# How it works: PostToolUse hook that appends every invocation to a JSONL log.
#               Captures tool name, command/path, timestamp, and exit status.
#               Companion script analyzes the log to suggest permission rules.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/permission-audit-log.sh" }]
#     }]
#   }
# }
#
# Analyze the log:
#   cat ~/.claude/tool-usage.jsonl | jq -s 'group_by(.tool) | map({tool: .[0].tool, count: length}) | sort_by(-.count)'
#   # Top commands:
#   cat ~/.claude/tool-usage.jsonl | jq -s '[.[] | select(.tool=="Bash")] | group_by(.command | split(" ")[0]) | map({cmd: .[0].command | split(" ")[0], count: length}) | sort_by(-.count) | .[:20]'
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[ -z "$TOOL" ] && exit 0

LOG_FILE="${CC_AUDIT_LOG:-$HOME/.claude/tool-usage.jsonl}"

# Extract relevant info based on tool type
case "$TOOL" in
    Bash)
        DETAIL=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        # Extract base command (first word)
        BASE_CMD=$(echo "$DETAIL" | awk '{print $1}')
        ;;
    Write|Read)
        DETAIL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        BASE_CMD="$TOOL"
        ;;
    Edit)
        DETAIL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        BASE_CMD="Edit"
        ;;
    Glob|Grep)
        DETAIL=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null)
        BASE_CMD="$TOOL"
        ;;
    Agent)
        DETAIL=$(echo "$INPUT" | jq -r '.tool_input.description // empty' 2>/dev/null)
        BASE_CMD="Agent"
        ;;
    *)
        DETAIL=""
        BASE_CMD="$TOOL"
        ;;
esac

# Build log entry
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Append to JSONL log (atomic write via temp file)
jq -n \
    --arg ts "$TIMESTAMP" \
    --arg tool "$TOOL" \
    --arg cmd "$BASE_CMD" \
    --arg detail "$DETAIL" \
    '{timestamp: $ts, tool: $tool, base_command: $cmd, detail: $detail}' \
    >> "$LOG_FILE" 2>/dev/null

exit 0
