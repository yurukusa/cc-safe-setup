#!/bin/bash
# ================================================================
# env-source-guard.sh — Block sourcing .env into shell environment
# ================================================================
# PURPOSE:
#   Claude Code sometimes sources .env files directly into bash,
#   causing environment variables to leak across commands.
#   This caused a Laravel test suite to use development database
#   instead of test database, wiping real data.
#
#   GitHub #401 (54 reactions)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHAT IT BLOCKS:
#   - source .env
#   - . .env
#   - source .env.local
#   - export $(cat .env)
#
# WHAT IT ALLOWS:
#   - Reading .env with cat (no sourcing)
#   - Framework commands that load env properly
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Block direct sourcing of .env files
if echo "$COMMAND" | grep -qE '(source|\.\s)\s+\.env'; then
    echo "BLOCKED: Sourcing .env into shell environment." >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "This loads all variables into the shell, affecting subsequent commands." >&2
    echo "Use your framework's env loader (dotenv, etc.) instead." >&2
    exit 2
fi

# Block export $(cat .env) pattern
if echo "$COMMAND" | grep -qE 'export\s+\$\(cat\s+\.env'; then
    echo "BLOCKED: Exporting .env contents into shell." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

exit 0
