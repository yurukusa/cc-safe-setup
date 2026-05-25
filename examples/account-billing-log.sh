#!/bin/bash
# ================================================================
# account-billing-log.sh — Append per-session line to a billing
#                          log indexed by Anthropic account label
# ================================================================
# PURPOSE:
#   Consultants billing clients for Claude Code work need
#   defensible per-account session records. This hook fires on
#   Stop and appends one line per session to ~/billing-logs/sessions.log
#   capturing timestamp, account label, working directory, and any
#   session metadata Claude passes to the hook.
#
#   The log format is plain text (one line per session) for easy
#   aggregation with awk/grep/jq at month-end.
#
# TRIGGER: Stop
# MATCHER: ""
#
# WHY IT MATTERS:
#   When you bill multiple clients off the same machine, "which
#   account did this session run under" must be answerable from
#   an audit log, not from memory or chat history. This hook gives
#   that audit log existence — without it, the only record is
#   whatever Anthropic shows you in their billing dashboard, which
#   is per-account but not per-project-per-session.
#
# OPERATOR-SIDE BRIDGE FOR (1,178 cumulative reactions):
#   #18435 Desktop multi-account profile switcher (542 reactions)
#   #27302 Web app per-Connector multi-account (327 reactions)
#   #36151 Mobile app multi-account switching (309 reactions)
#
# OUTPUT FORMAT:
#   One line per session, pipe-separated for easy awk:
#   <timestamp UTC> | <account> | <cwd> | session:<id> | turns:<n>
#
# AGGREGATION EXAMPLES:
#   # Session count this month, grouped by account:
#   awk -F' \\| ' '{print substr($1,1,7), $2}' ~/billing-logs/sessions.log \
#     | grep "^$(date +%Y-%m)" \
#     | awk '{print $2}' | sort | uniq -c
#
#   # All sessions for one client this month:
#   grep "^$(date +%Y-%m)" ~/billing-logs/sessions.log | grep "| client-a |"
#
# CONFIGURATION (env vars):
#   ANTHROPIC_ACCOUNT_LABEL   the active session's account label;
#                              defaults to "unknown" if unset.
#   CC_BILLING_LOG_DIR        directory for the log file;
#                              defaults to $HOME/billing-logs.
#   CC_BILLING_LOG_DISABLE    set to "1" to disable logging.
#
# RELATED:
#   account-routing-preflight.sh (companion hook, SessionStart side)
#   Multi-account operator guide:
#     https://gist.github.com/yurukusa/d880ecc984af5d664f003daf85f956e3
# ================================================================

set -u

if [ "${CC_BILLING_LOG_DISABLE:-0}" = "1" ]; then
    exit 0
fi

LOG_DIR="${CC_BILLING_LOG_DIR:-$HOME/billing-logs}"
LOG_FILE="$LOG_DIR/sessions.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR" 2>/dev/null || {
    echo "account-billing-log: cannot create $LOG_DIR" >&2
    exit 0
}

# Resolve active account label
ACCOUNT="${ANTHROPIC_ACCOUNT_LABEL:-unknown}"

# Read Claude's session JSON from stdin (best-effort)
INPUT=$(cat 2>/dev/null || echo '{}')

# Extract session metadata — accept multiple field shapes
SESSION_ID=$(printf '%s' "$INPUT" \
    | jq -r '.session_id // .sessionId // .session.id // "unknown"' 2>/dev/null \
    || echo "unknown")
TURNS=$(printf '%s' "$INPUT" \
    | jq -r '.turn_count // .turns // .session.turn_count // 0' 2>/dev/null \
    || echo "0")

# Sanitize any pipe characters in cwd to keep the log parseable
CWD_SANITIZED=$(printf '%s' "$PWD" | tr '|' '_')

# Append the log line
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s | %s | %s | session:%s | turns:%s\n' \
    "$TIMESTAMP" "$ACCOUNT" "$CWD_SANITIZED" "$SESSION_ID" "$TURNS" \
    >> "$LOG_FILE"

# Stop hooks should always exit 0 unless they want to block —
# billing logging is advisory.
exit 0
