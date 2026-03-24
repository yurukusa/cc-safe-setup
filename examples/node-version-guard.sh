#!/bin/bash
# node-version-guard.sh — Warn when Node.js version doesn't match .nvmrc
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*(npm|node|npx|yarn|pnpm)\s' || exit 0
if [ -f ".nvmrc" ] || [ -f ".node-version" ]; then
  EXPECTED=$(cat .nvmrc 2>/dev/null || cat .node-version 2>/dev/null)
  ACTUAL=$(node --version 2>/dev/null | tr -d 'v')
  if [ -n "$EXPECTED" ] && [ -n "$ACTUAL" ]; then
    EXPECTED_MAJOR=$(echo "$EXPECTED" | cut -d. -f1 | tr -d 'v')
    ACTUAL_MAJOR=$(echo "$ACTUAL" | cut -d. -f1)
    if [ "$EXPECTED_MAJOR" != "$ACTUAL_MAJOR" ]; then
      echo "WARNING: Node.js version mismatch. Expected v${EXPECTED}, running v${ACTUAL}." >&2
      echo "Run: nvm use" >&2
    fi
  fi
fi
exit 0
