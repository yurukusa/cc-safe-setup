#!/bin/bash
# dotenv-watch.sh — Alert when .env files change on disk
#
# Uses the FileChanged hook event (v2.1.83+) to detect when
# environment configuration files are modified outside of Claude Code.
#
# Solves: When .env files are modified by another process (git pull,
#         manual edit, dotenv rotation script), Claude Code doesn't
#         know the environment has changed. This can cause stale
#         API keys, wrong database URLs, or missing config values.
#
# TRIGGER: FileChanged
# MATCHER: ".env" (watches the .env file in cwd — use ".env|.env.local" for multiple files)
#
# INPUT: {"file_path": "/path/to/.env", "event": "change|add|unlink"}
#
# DECISION CONTROL: None (notification only — shows stderr to user)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // empty' 2>/dev/null)
EVENT=$(echo "$INPUT" | jq -r '.event // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

FILENAME=$(basename "$FILE_PATH")

case "$EVENT" in
    change)
        echo "⚠ Environment file changed: ${FILENAME}" >&2
        echo "  Path: ${FILE_PATH}" >&2
        echo "  Action: Verify environment variables are still correct" >&2
        ;;
    add)
        echo "📝 New environment file: ${FILENAME}" >&2
        echo "  Path: ${FILE_PATH}" >&2
        echo "  Action: Review contents before use" >&2
        ;;
    unlink)
        echo "🗑 Environment file deleted: ${FILENAME}" >&2
        echo "  Path: ${FILE_PATH}" >&2
        echo "  Action: Check if environment variables are still available" >&2
        ;;
    *)
        echo "📂 Environment file event (${EVENT}): ${FILENAME}" >&2
        ;;
esac

exit 0
