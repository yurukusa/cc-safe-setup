#!/bin/bash
# dotenv-read-guard.sh — Block Read/Glob/Grep of .env files
#
# Solves: Sub-agents (especially Explore) reading .env files and exposing
#         API keys, tokens, and secrets in the conversation transcript.
#         (#51030 — Explore agent read .env, exposed 5 API keys, $50 damage)
#         (#30731 — credentials exposed in output)
#
# This hook catches the Read tool accessing .env files, which
# credential-file-cat-guard.sh misses (it only covers Bash cat commands).
# Sub-agents inherit hooks but NOT memory/security instructions, making
# this hook essential for preventing secret leaks in multi-agent workflows.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Read",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/dotenv-read-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Read"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE_PATH" ] && exit 0

BASENAME=$(basename "$FILE_PATH")

# Block .env and all variants (.env.local, .env.production, .env.staging, etc.)
# Allow .env.example, .env.sample, .env.template (safe reference files)
if echo "$BASENAME" | grep -qE '^\.env(\.example|\.sample|\.template)$'; then
    exit 0
fi

if echo "$BASENAME" | grep -qE '^\.env(\..+)?$'; then
    echo "BLOCKED: Reading $BASENAME — contains secrets (API keys, tokens)" >&2
    echo "  .env files should never be read by Claude Code." >&2
    echo "  If you need to check which variables are set, read .env.example instead." >&2
    echo "  Related: GitHub Issue #51030 (sub-agent exposed 5 API keys)" >&2
    exit 2
fi

exit 0
