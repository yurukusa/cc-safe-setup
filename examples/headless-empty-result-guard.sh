#!/bin/bash
# headless-empty-result-guard.sh — Detect empty results in headless mode
#
# Solves: claude -p exits with empty result when stream is interrupted (#40432).
#         stop_reason: "tool_use" with result: "" is treated as success,
#         but the model was actually mid-generation.
#
# How it works: Stop hook that checks environment for headless indicators
#   and warns if the session produced no visible output. In CI/automation,
#   this can trigger a retry or alert.
#
# CONFIG:
#   CC_HEADLESS_MARKER="/tmp/claude-headless-result"
#   Set this in your CI script to check after claude -p exits.
#
# TRIGGER: Stop
# MATCHER: ""

set -euo pipefail

INPUT=$(cat)

# Check if we're in headless/print mode
# Indicators: CLAUDE_PRINT_MODE env var, or no TTY
if [ -z "${CLAUDE_PRINT_MODE:-}" ] && [ -t 0 ]; then
    # Interactive mode — skip
    exit 0
fi

# Check for empty/incomplete result indicators
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // empty' 2>/dev/null)
RESULT=$(echo "$INPUT" | jq -r '.result // empty' 2>/dev/null)

MARKER="${CC_HEADLESS_MARKER:-/tmp/claude-headless-result-${PPID:-0}}"

if [ "$STOP_REASON" = "tool_use" ] || [ -z "$RESULT" ]; then
    echo "WARNING: Headless session ended with incomplete result." >&2
    echo "  stop_reason: ${STOP_REASON:-unknown}" >&2
    echo "  result length: ${#RESULT}" >&2
    echo "  This may indicate a stream interruption, not a completed task." >&2
    echo "incomplete" > "$MARKER"
else
    echo "complete" > "$MARKER"
fi

exit 0
