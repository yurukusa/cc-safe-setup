#!/bin/bash
# ================================================================
# stop-transcript-write-health.sh — Detect a silently stalled or reverted transcript
# ================================================================
# PURPOSE:
#   Claude Code writes the conversation to
#   ~/.claude/projects/<slug>/<session-id>.jsonl as the session runs.
#   Some failures stop that write silently: an account switch can revert
#   the live file to an older snapshot and then never write again, with no
#   error shown (anthropics/claude-code#73937). The session keeps working,
#   so the loss is invisible until you diff line counts by hand.
#
# HOW IT WORKS:
#   Stop fires after every completed turn and its input carries
#   `transcript_path`. That is the natural "a turn's worth of lines should
#   have just been written" checkpoint. This hook records the transcript's
#   line count and mtime per session_id, and on the next Stop:
#     - line count + mtime unchanged since last turn  -> the turn was NOT
#       persisted (silent save-stop) -> warn.
#     - line count shrank                             -> the file was
#       reverted to an older snapshot -> warn.
#   The warning is emitted via {"systemMessage": ...} so it surfaces to the
#   user without blocking the session. It only detects; it does not replace
#   an independent content backup.
#
# TRIGGER: Stop
# MATCHER: (none — Stop has no tool matcher)
#
# CONFIGURATION:
#   none
# ================================================================
set -uo pipefail

input=$(cat)
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
sid=$(printf '%s' "$input" | jq -r '.session_id // "nosid"' 2>/dev/null)

# No transcript path / unreadable -> nothing to check.
[ -z "$tp" ] && exit 0
[ ! -f "$tp" ] && exit 0

state_dir="${HOME}/.claude/transcript-health"
mkdir -p "$state_dir"
state_file="${state_dir}/${sid}.state"

cur_lines=$(wc -l < "$tp" 2>/dev/null | tr -d ' ')
cur_mtime=$(stat -c %Y "$tp" 2>/dev/null || stat -f %m "$tp" 2>/dev/null)

warn=""
if [ -f "$state_file" ]; then
    read -r prev_lines prev_mtime < "$state_file"
    if [ "${cur_lines:-0}" -lt "${prev_lines:-0}" ]; then
        warn="⚠ transcript reverted (${prev_lines}→${cur_lines} lines). The live file may have been replaced with an older snapshot (account switch / #73937). Check your recovery point before continuing."
    elif [ "${cur_lines:-0}" -eq "${prev_lines:-0}" ] && [ "${cur_mtime:-0}" -eq "${prev_mtime:-0}" ]; then
        warn="⚠ the last turn was NOT persisted to ${tp} (line count and mtime unchanged since the previous turn). Saves may have silently stopped (#73937). This turn may exist only in memory — take an independent backup and restart."
    fi
fi

printf '%s %s\n' "${cur_lines:-0}" "${cur_mtime:-0}" > "$state_file"

if [ -n "$warn" ]; then
    jq -cn --arg m "$warn" '{systemMessage:$m}'
fi
exit 0
