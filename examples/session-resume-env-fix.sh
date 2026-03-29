#!/bin/bash
# session-resume-env-fix.sh — Fix CLAUDE_ENV_FILE path on session resume
#
# Solves: CLAUDE_ENV_FILE points to startup session directory, but Bash
#         tool loads from resumed session directory (#40391, #24775).
#         Environment variables written by SessionStart hooks are lost.
#
# How it works: SessionStart hook that detects resume (source="resume")
#   and copies/symlinks env files from the startup session directory
#   to the resumed session directory.
#
# TRIGGER: SessionStart
# MATCHER: ""

set -euo pipefail

INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Only act on resume events
[ "$SOURCE" = "resume" ] || exit 0
[ -n "$SESSION_ID" ] || exit 0
[ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0

# Extract the startup session directory from CLAUDE_ENV_FILE
STARTUP_DIR=$(dirname "$CLAUDE_ENV_FILE")
ENV_BASE=$(dirname "$STARTUP_DIR")

# Construct the resumed session directory
RESUME_DIR="${ENV_BASE}/${SESSION_ID}"

# If they're the same, no fix needed
[ "$STARTUP_DIR" != "$RESUME_DIR" ] || exit 0

# Create resumed session directory if missing
mkdir -p "$RESUME_DIR"

# Copy all env files from startup dir to resumed dir
for envfile in "$STARTUP_DIR"/*.sh; do
    [ -f "$envfile" ] || continue
    BASENAME=$(basename "$envfile")
    if [ ! -f "$RESUME_DIR/$BASENAME" ]; then
        cp "$envfile" "$RESUME_DIR/$BASENAME"
        echo "Copied env file to resumed session: $BASENAME" >&2
    fi
done

exit 0
