#!/bin/bash
# ================================================================
# post-credential-failure-destructive-guard.sh
# Block destructive commands that follow a credential/auth failure
# ================================================================
# PURPOSE:
#   When a Bash tool fails with a credential/auth/permission error,
#   the AI sometimes infers "I should clean up and retry" and runs
#   a destructive command (DROP DATABASE, rm -rf, volume delete,
#   environment recreate) without checking the failure context.
#   This is the exact pattern documented in the PocketOS incident
#   (2026-04-25): Cursor with Opus 4.6 hit a credential mismatch,
#   decided autonomously to delete the Railway volume, and erased
#   the production database in 9 seconds.
#
#   This hook ties the PostToolUse credential-failure signal to the
#   next PreToolUse Bash call. If the next call is destructive and
#   the previous call failed on credentials, the hook blocks.
#
# TRIGGER: PreToolUse + PostToolUse (the same script handles both)
# MATCHER: "Bash"
#
# CONFIGURATION:
#   CC_CRED_FAILURE_WINDOW_SEC=60 (state lifetime, default 60s)
#   CC_CRED_FAILURE_DISABLE=1     (disable the hook entirely)
#
# References:
# - PocketOS 2026-04-25: https://www.tomshardware.com/tech-industry/artificial-intelligence/claude-powered-ai-coding-agent-deletes-entire-company-database-in-9-seconds-backups-zapped-after-cursor-tool-powered-by-anthropics-claude-goes-rogue
# - Amazon Kiro 2025-12: AWS Cost Explorer 13-hour outage from environment recreate
# ================================================================

set -euo pipefail

[ "${CC_CRED_FAILURE_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Bash" ] && exit 0

STATE_FILE="/tmp/cc-cred-failure-${PPID:-0}"
WINDOW="${CC_CRED_FAILURE_WINDOW_SEC:-60}"

# Determine if PostToolUse (has tool_result) or PreToolUse (has tool_input.command only)
if echo "$INPUT" | jq -e 'has("tool_result") or .hook_event_name == "PostToolUse"' >/dev/null 2>&1; then
    # PostToolUse mode: detect credential/auth failures
    EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exitCode // .tool_result.exit_code // "0"' 2>/dev/null)
    STDERR=$(echo "$INPUT" | jq -r '.tool_result.stderr // empty' 2>/dev/null)
    STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty' 2>/dev/null)
    COMBINED="${STDERR}${STDOUT}"

    # Non-zero exit and credential-failure indicators in output
    if [ "$EXIT_CODE" != "0" ] && [ -n "$COMBINED" ]; then
        if echo "$COMBINED" | grep -qiE 'credential.{0,20}(mismatch|invalid|expired|not.{0,5}found|missing)|auth.{0,20}(fail|denied|invalid|expired|required)|permission.{0,5}denied|access.{0,5}denied|unauthorized|forbidden|401 (unauthorized|error)|403 (forbidden|error)|invalid (token|api.{0,3}key|password)|token (expired|invalid|revoked)|login (failed|required)'; then
            # Record the failure timestamp
            date +%s > "$STATE_FILE"
            echo "[post-credential-failure-destructive-guard] Detected credential/auth failure. Next destructive command within ${WINDOW}s will be blocked." >&2
        fi
    elif [ "$EXIT_CODE" = "0" ]; then
        # Successful command resets the state (the failure recovered)
        [ -f "$STATE_FILE" ] && rm -f "$STATE_FILE"
    fi
    exit 0
fi

# PreToolUse mode: block destructive commands if recent credential failure
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Check state file freshness
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

LAST=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
NOW=$(date +%s)
AGE=$((NOW - LAST))

if [ "$AGE" -gt "$WINDOW" ]; then
    # Stale, clean up and pass
    rm -f "$STATE_FILE"
    exit 0
fi

# Check for destructive patterns
DESTRUCTIVE_PATTERN='(\brm\b.*-[rRf]*[rR]|\bDROP\s+DATABASE|\bDROP\s+TABLE|\bTRUNCATE\b|\bDELETE\s+FROM\b|\bgit\s+checkout\s+--|\bgit\s+reset\s+--hard|\bgit\s+clean\s+-fd|\bdropdb\b|\bmigrate:fresh|\bmigrate:reset|\bdb:drop|\bdb:wipe|\bmigrate\s+reset|\brailway\s+(volume|database).*(delete|destroy|remove)|\bgcloud\s+(sql|compute).*(delete|destroy)|\bkubectl\s+delete\b|\bdocker\s+(rm|volume\s+rm|network\s+rm)|\baws\s+(s3\s+rb|rds\s+delete|ec2\s+terminate)|\bterraform\s+destroy\b|\bdrop\s+volume\b|\bRemove-Item.*-Recurse)'

if echo "$COMMAND" | grep -qiE "$DESTRUCTIVE_PATTERN"; then
    cat >&2 <<EOF
BLOCKED: post-credential-failure-destructive-guard.sh

A credential or auth failure occurred ${AGE}s ago in this session.
The next command would execute a destructive operation:

  ${COMMAND}

This matches the pattern documented in the PocketOS 2026-04-25 incident
(Cursor with Claude Opus 4.6 deleted a production database in 9 seconds
after a credential mismatch).

To proceed:
1. Verify that the destructive command is the correct response to the auth failure.
2. If yes, set CC_CRED_FAILURE_DISABLE=1 for this turn or clear the state:
     rm /tmp/cc-cred-failure-${PPID:-0}
3. Re-run the command.

The window is ${WINDOW}s. Adjust with CC_CRED_FAILURE_WINDOW_SEC.
EOF
    exit 2
fi

exit 0
