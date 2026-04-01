#!/bin/bash
# ================================================================
# subagent-error-detector.sh — Detect failed subagent results
# ================================================================
# PURPOSE:
#   When a subagent returns, checks whether the result contains
#   API error indicators (529 Overloaded, 500 Internal, timeout).
#   Warns via stderr so the main agent doesn't silently accept
#   error results as valid work.
#
# TRIGGER: PostToolUse
# MATCHER: "Agent"
#
# WHY THIS MATTERS:
#   API 529 "Overloaded" errors silently kill parallel subagents.
#   The agent reports "completion" but the result is just an error
#   string. Without detection, the main agent accepts the error
#   as a valid response and continues — losing all subagent work.
#
# WHAT IT CHECKS:
#   - 529 Overloaded errors
#   - 500/502/503 API errors
#   - Timeout indicators
#   - Empty or suspiciously short results
#
# OUTPUT:
#   Warning to stderr when subagent result looks like an error.
#   Always exits 0 — advisory only.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/41911
# ================================================================

set -u

INPUT=$(cat)

# Extract the tool result (subagent's returned output)
RESULT=$(printf '%s' "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null)

if [ -z "$RESULT" ]; then
    exit 0
fi

WARNINGS=""

# Check for API error patterns
if printf '%s' "$RESULT" | grep -qiE '529.*overloaded|overloaded_error'; then
    WARNINGS="${WARNINGS}  - ⛔ 529 Overloaded error detected — subagent hit API rate limit\n"
fi

if printf '%s' "$RESULT" | grep -qiE '500 Internal|502 Bad Gateway|503 Service Unavailable'; then
    WARNINGS="${WARNINGS}  - ⛔ Server error detected in subagent result\n"
fi

if printf '%s' "$RESULT" | grep -qiE 'timeout|timed out|ETIMEDOUT|ECONNRESET'; then
    WARNINGS="${WARNINGS}  - ⚠ Timeout detected in subagent result\n"
fi

# Check for suspiciously short results (< 50 chars often means error)
RESULT_LEN=${#RESULT}
if [ "$RESULT_LEN" -lt 50 ]; then
    WARNINGS="${WARNINGS}  - ⚠ Subagent result is only ${RESULT_LEN} chars — may be an error, not real work\n"
fi

if [ -n "$WARNINGS" ]; then
    printf '\n⚠ Subagent result quality check:\n' >&2
    printf '%b' "$WARNINGS" >&2
    printf 'The subagent may have failed. Verify the result before using it.\n' >&2
    printf 'Consider re-running the subagent or doing the work directly.\n\n' >&2
fi

exit 0
