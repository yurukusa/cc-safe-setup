#!/bin/bash
# node-version-check.sh — Warn if Node.js version is too old
#
# Prevents: Mysterious failures from unsupported Node.js versions
#           Claude Code requires Node.js 18+. Many npm packages
#           also have minimum version requirements.
#
# TRIGGER: Notification
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "Notification": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/node-version-check.sh" }]
#     }]
#   }
# }

# Only run once per session
MARKER="/tmp/cc-node-check-$$"
[ -f "$MARKER" ] && exit 0

NODE_VERSION=$(node --version 2>/dev/null | sed 's/^v//')
if [ -z "$NODE_VERSION" ]; then
  echo "WARNING: Node.js not found in PATH." >&2
  touch "$MARKER"
  exit 0
fi

MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)

if [ "$MAJOR" -lt 18 ] 2>/dev/null; then
  echo "WARNING: Node.js v${NODE_VERSION} detected. Claude Code requires v18+." >&2
  echo "  Update: nvm install 20 && nvm use 20" >&2
fi

touch "$MARKER"
exit 0
