#!/bin/bash
# ================================================================
# prompt-usage-logger.sh — Log every prompt with timestamps
# ================================================================
# PURPOSE:
#   Track when and what you send to Claude, so you can correlate
#   prompts with token usage on the billing dashboard.
#   Helps diagnose unexpectedly fast token consumption.
#
# TRIGGER: UserPromptSubmit
# MATCHER: ""
#
# HOW IT WORKS:
#   Reads the prompt from stdin JSON, truncates to first 100 chars,
#   and appends a timestamped line to a log file.
#   After a session, compare timestamps with your usage dashboard
#   to identify which interactions consumed the most tokens.
#
# CONFIGURATION:
#   CC_PROMPT_LOG=/tmp/claude-usage-log.txt  (default log path)
#
# OUTPUT:
#   Passes through original input on stdout (required for
#   UserPromptSubmit hooks).
#
# EXAMPLE LOG:
#   12:34:56 prompt=Read the file src/main.ts and explain the error handling
#   12:35:23 prompt=Fix the bug in the validateInput function
#
# SEE ALSO:
#   cost-tracker.sh (PostToolUse-based cost estimation)
#   daily-usage-tracker.sh (daily aggregation)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/41249
#   https://github.com/anthropics/claude-code/issues/38335
#   https://github.com/anthropics/claude-code/issues/16157
# ================================================================

set -euo pipefail

INPUT=$(cat)

LOG_FILE="${CC_PROMPT_LOG:-/tmp/claude-usage-log.txt}"

# Extract first 100 chars of the prompt
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt | .[0:100]' 2>/dev/null || echo "(parse error)")

# Append timestamped entry
echo "$(date -u +%H:%M:%S) prompt=$PROMPT" >> "$LOG_FILE"

# Pass through original input (required for UserPromptSubmit)
printf '%s\n' "$INPUT"
