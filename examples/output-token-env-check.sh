#!/bin/bash
# output-token-env-check.sh — Warn if max output tokens is not configured
#
# Solves: "Response exceeded 32000 output token maximum" error
#         (#24055 — 80 reactions)
#
# Claude Code defaults to 32,000 max output tokens. For complex tasks,
# this is often not enough. Setting CLAUDE_CODE_MAX_OUTPUT_TOKENS
# prevents the error, but many users don't know about this env var.
#
# This hook checks on session start (Notification/Stop) and warns
# if the env var is not set or is set to the default 32000.
#
# TRIGGER: Notification
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "Notification": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/output-token-env-check.sh" }]
#     }]
#   }
# }

# Only run once per session (check if we already warned)
MARKER="/tmp/cc-output-token-warned-$$"
[ -f "$MARKER" ] && exit 0

MAX_TOKENS="${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-}"

if [ -z "$MAX_TOKENS" ]; then
  echo "TIP: CLAUDE_CODE_MAX_OUTPUT_TOKENS is not set (default: 32,000)." >&2
  echo "  For complex tasks, set it higher to avoid truncated responses:" >&2
  echo "  export CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000" >&2
  touch "$MARKER"
elif [ "$MAX_TOKENS" -le 32000 ] 2>/dev/null; then
  echo "TIP: CLAUDE_CODE_MAX_OUTPUT_TOKENS=$MAX_TOKENS (low for complex tasks)." >&2
  echo "  Consider: export CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000" >&2
  touch "$MARKER"
fi

exit 0
