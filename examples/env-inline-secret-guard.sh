#!/bin/bash
# env-inline-secret-guard.sh — Block .env values from appearing in commands
#
# Solves: Claude reading .env and hardcoding secrets into inline scripts (#24185).
#         API keys, database URLs, and tokens get embedded in bash commands,
#         potentially leaking to logs, history, or screen recordings.
#
# How it works: PreToolUse hook on Bash that detects common secret patterns
#   (API keys, tokens, connection strings) in command text.
#   If found, blocks with exit 2 and suggests environment variable usage.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Detect inline secrets: known API key prefixes (20+ chars)
# sk- (OpenAI), ghp_/ghu_ (GitHub), AKIA (AWS)
if echo "$COMMAND" | grep -qE '(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|ghu_[a-zA-Z0-9]{36}|AKIA[0-9A-Z]{16}|xoxb-[0-9]+-[0-9]+-[a-zA-Z0-9]+)'; then
  echo "BLOCKED: Possible secret/credential detected in command." >&2
  echo "Use environment variables instead of inline secrets." >&2
  exit 2
fi

# Detect generic long tokens in auth headers or parameters
if echo "$COMMAND" | grep -qE "(Authorization:|Bearer |token=|api[_-]?key=|secret=|password=)['\"]?[a-zA-Z0-9+/=_-]{32,}"; then
  echo "BLOCKED: Long token/key detected inline in command." >&2
  echo "Use environment variables or a secrets file instead." >&2
  exit 2
fi

exit 0
