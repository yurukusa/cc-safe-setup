#!/bin/bash
# commit-message-quality.sh — Warn about low-quality commit messages
#
# Prevents: "fix", "update", "wip", "asdf" commit messages.
#           Claude sometimes generates vague messages.
#
# Checks: minimum length, conventional commit format suggestion
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git commit
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Extract commit message
MSG=$(echo "$COMMAND" | grep -oP '(-m\s+["\x27])(.+?)(["\x27])' | sed "s/^-m\s*[\"']//" | sed "s/[\"']$//")
[ -z "$MSG" ] && exit 0

# Check message quality
LEN=${#MSG}

if [ "$LEN" -lt 10 ]; then
  echo "WARNING: Commit message too short ($LEN chars). Be more descriptive." >&2
fi

# Check for vague messages
if echo "$MSG" | grep -qiE '^(fix|update|change|wip|temp|test|asdf|todo|misc|stuff|things|more)$'; then
  echo "WARNING: Vague commit message '$MSG'. Describe WHAT changed and WHY." >&2
fi

exit 0
