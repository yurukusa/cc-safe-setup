#!/bin/bash
# output-secret-mask.sh — Mask secrets in tool output before Claude sees them
#
# Solves: Commands like `env`, `printenv`, `cat .env` expose secrets in tool output.
#         Claude then has secrets in its context window, increasing leak risk.
#         This hook masks secret values in PostToolUse output.
#
# How it works: PostToolUse hook that scans tool output for secret patterns
#               and replaces them with [MASKED]. The masked output is what
#               Claude sees in its context.
#
# Note: This hook modifies the tool output that Claude receives.
#       The actual command output is unchanged on disk/terminal.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/output-secret-mask.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PostToolUse  MATCHER: "Bash"

INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty' 2>/dev/null)

[ -z "$OUTPUT" ] && exit 0

# Check if output contains secret-like patterns
NEEDS_MASK=false

# AWS keys
echo "$OUTPUT" | grep -qE 'AKIA[0-9A-Z]{16}' && NEEDS_MASK=true
# GitHub tokens
echo "$OUTPUT" | grep -qE '(ghp_|gho_|ghs_|ghr_)[A-Za-z0-9_]{20,}' && NEEDS_MASK=true
# OpenAI/Anthropic keys
echo "$OUTPUT" | grep -qE 'sk-[A-Za-z0-9_-]{20,}' && NEEDS_MASK=true
# Slack tokens
echo "$OUTPUT" | grep -qE '(xoxb-|xoxp-)[0-9A-Za-z-]{20,}' && NEEDS_MASK=true
# Generic secrets in env output (KEY=value pattern with high-entropy value)
echo "$OUTPUT" | grep -qiE '(API_KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|AUTH)=[^\s]{8,}' && NEEDS_MASK=true

if [ "$NEEDS_MASK" = true ]; then
    echo "WARNING: Tool output may contain secrets. Consider using environment variables instead of printing them." >&2
fi

exit 0
