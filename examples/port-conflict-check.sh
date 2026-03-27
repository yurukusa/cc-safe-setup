#!/bin/bash
# port-conflict-check.sh — Warn before starting a server on an occupied port
#
# Prevents: "EADDRINUSE" errors that confuse Claude into debugging
#           phantom issues. Detects port conflicts before they happen.
#
# Detects: npm start, npm run dev, python -m http.server, node server.js,
#          next dev, vite, etc.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/port-conflict-check.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Detect server-starting commands
echo "$COMMAND" | grep -qiE '(npm\s+(start|run\s+dev)|npx\s+(next|vite|nuxt)|python.*http\.server|node\s+.*server|flask\s+run|uvicorn|gunicorn|rails\s+s)' || exit 0

# Try to extract port from command
PORT=""
if echo "$COMMAND" | grep -qE '\-\-port[= ]+([0-9]+)'; then
  PORT=$(echo "$COMMAND" | grep -oE '\-\-port[= ]+([0-9]+)' | grep -oE '[0-9]+')
elif echo "$COMMAND" | grep -qE '\-p[= ]+([0-9]+)'; then
  PORT=$(echo "$COMMAND" | grep -oE '\-p[= ]+([0-9]+)' | grep -oE '[0-9]+')
fi

# Common default ports
if [ -z "$PORT" ]; then
  if echo "$COMMAND" | grep -qiE 'next|vite|nuxt'; then PORT=3000
  elif echo "$COMMAND" | grep -qiE 'flask|django'; then PORT=5000
  elif echo "$COMMAND" | grep -qiE 'rails'; then PORT=3000
  elif echo "$COMMAND" | grep -qiE 'http\.server'; then PORT=8000
  else PORT=3000
  fi
fi

# Check if port is in use
if command -v ss >/dev/null 2>&1; then
  if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
    PID=$(ss -tlnp 2>/dev/null | grep ":${PORT} " | grep -oP 'pid=\K[0-9]+' | head -1)
    echo "WARNING: Port $PORT is already in use (PID: ${PID:-unknown})." >&2
    echo "  Kill it: kill $PID  or use a different port." >&2
  fi
elif command -v lsof >/dev/null 2>&1; then
  if lsof -i ":${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "WARNING: Port $PORT is already in use." >&2
    echo "  Check: lsof -i :$PORT" >&2
  fi
fi

exit 0
