#!/bin/bash
# ================================================================
# stale-temp-settings-detector.sh — Warn when /tmp holds a stale
#   claude-settings file owned by a different local user.
# ================================================================
# PURPOSE:
#   Claude Desktop launches Claude Code with `--settings '{}'` and
#   writes the inline payload to /tmp/claude-settings-<hash>.json.
#   The hash is deterministic across users on the same host, so a
#   stale file owned by user A blocks a fresh start by user B with
#   EACCES, and the only message the user sees is "Claude Code
#   process exited with code 1".
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# WHY THIS MATTERS:
#   Issue #57224 (filed 2026-05-08, area:security) describes a
#   shared-host crash where a stale /tmp/claude-settings-44136fa
#   355b3678a.json owned by another local user blocked startup.
#   The error surfacing was masked into "process exited with code 1".
#
#   This detector scans /tmp at session start, lists any
#   claude-settings-*.json owned by other users, and surfaces the
#   actual owner names so the user can act before retrying.
#
# CONFIGURATION:
#   STALE_TEMP_SETTINGS_DISABLE  set to 1 to silence this hook
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/57224
# ================================================================

set -u

[ "${STALE_TEMP_SETTINGS_DISABLE:-0}" = "1" ] && exit 0

LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="unknown-$(date +%s)"

# One warning per session
WARN_LOG="$LOG_DIR/stale-temp-settings-warned-$SESSION_ID"
[ -f "$WARN_LOG" ] && exit 0

CURRENT_UID=$(id -u 2>/dev/null || echo "")
[ -z "$CURRENT_UID" ] && exit 0

# Find files matching the pattern. -maxdepth 1 keeps the scan scoped.
# Suppress errors so a missing /tmp or restricted access exits cleanly.
MATCHES=$(find /tmp -maxdepth 1 -name 'claude-settings-*.json' -type f 2>/dev/null)
[ -z "$MATCHES" ] && exit 0

FOREIGN=""
while IFS= read -r path; do
    [ -z "$path" ] && continue
    # Skip if we cannot stat the file
    OWNER_UID=$(stat -c '%u' "$path" 2>/dev/null) || continue
    if [ "$OWNER_UID" != "$CURRENT_UID" ]; then
        OWNER_NAME=$(stat -c '%U' "$path" 2>/dev/null)
        FOREIGN="${FOREIGN}  $path  (owner: ${OWNER_NAME:-uid=$OWNER_UID})"$'\n'
    fi
done <<< "$MATCHES"

if [ -n "$FOREIGN" ]; then
    cat >&2 <<MSG
stale-temp-settings-detector: /tmp holds claude-settings file(s)
owned by a different user. Claude Desktop's inline-settings
launch path uses a deterministic name and will fail with EACCES
on collision, surfacing only "process exited with code 1".

Foreign files:
${FOREIGN}
If you have permission, remove them and retry. Otherwise, ask the
host administrator to clean /tmp/claude-settings-*.json or wait
for the other user's session to finish.

Background: Issue #57224 (filed 2026-05-08, area:security).
MSG
    touch "$WARN_LOG"
fi

exit 0
