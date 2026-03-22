#!/bin/bash
# timeout-guard.sh — Warn before long-running commands
#
# Solves: Claude running commands that hang indefinitely
# (e.g., servers, watchers, interactive tools) without
# using run_in_background.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/timeout-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Detect commands that typically run forever
FOREVER_PATTERNS=(
    "npm start"
    "npm run dev"
    "npm run serve"
    "yarn start"
    "yarn dev"
    "python -m http.server"
    "python manage.py runserver"
    "flask run"
    "uvicorn"
    "nodemon"
    "webpack serve"
    "vite"
    "next dev"
    "ng serve"
    "rails server"
    "rails s"
    "php artisan serve"
    "cargo watch"
    "go run.*server"
    "docker-compose up$"
    "tail -f"
    "watch "
    "inotifywait"
)

for pattern in "${FOREVER_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$pattern"; then
        RUN_BG=$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)
        if [[ "$RUN_BG" != "true" ]]; then
            echo "" >&2
            echo "WARNING: This command may run indefinitely: $pattern" >&2
            echo "Consider using run_in_background: true" >&2
        fi
        break
    fi
done

exit 0
