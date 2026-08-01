#!/bin/bash
# temporal-suggestion-detector.sh — Stop hook. Detects "rest / break / sleep"
# suggestions Claude inserts at inappropriate times-of-day, and logs them to
# disk for later inspection. Does NOT block. Advisory only.
#
# Solves: the broken-sense-of-time pattern documented in Fortune (2026-05-14)
# and r/ClaudeAI (post 1te0mhh, 2,276 upvotes, 347 comments). Since Opus 4.7's
# release in late April 2026, Claude has been inserting unsolicited "go to
# sleep / take a break / call it a day" suggestions into responses, often
# 3-4 times per session, sometimes escalating ("Now actually go rest").
# The pattern fires at any time of day (8:30 AM, 11:30 AM, noon) because
# Claude has no reliable access to current local time.
#
# For autonomous and long-session operators, every unsolicited rest
# suggestion is wasted output tokens plus a context-window dilution event.
# Single occurrences are low-cost; the accumulated cost and the loss of
# operator trust in Claude's timing-related assertions are not.
#
# This hook quietly observes Claude's output for the documented patterns
# and writes each match to ~/.claude/temporal-suggestions.log. It does not
# block, does not surface a system reminder, does not add response load.
# After two weeks of logging, the operator has a measured baseline:
# how often is this happening, what time of day, what session contexts.
#
# Related Issues / Reports:
#   - Fortune, 2026-05-14: "Why is Claude telling users to go to sleep?"
#   - r/ClaudeAI 1te0mhh (2,276 upvotes, 347 comments)
#   - r/ClaudeAI 1ruryxo (bedtime escalation, 294 upvotes)
#   - r/claudexplorers 1rt9i66 (escalating bedtime, 415 upvotes)
#   - r/ClaudeCode 1tcnpua (operator complaints, 63 upvotes, 63 comments)
#   - Analysis:
#     https://gist.github.com/yurukusa/728dd32c47131e2e5c180cf7bebfceff
#
# TRIGGER: Stop
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_TEMPORAL_LOG               default ~/.claude/temporal-suggestions.log
#   CC_TEMPORAL_PATTERN           default built-in pipe-separated regex
#   CC_TEMPORAL_DETECT_DISABLE    set to "1" to disable the detector
#   CC_TEMPORAL_STRICT            set to "1" to exit 2 (advisory by default)
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "Stop": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/temporal-suggestion-detector.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-temporal-suggestion-detector-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [temporal-suggestion-detector]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

[ "${CC_TEMPORAL_DETECT_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

LOG="${CC_TEMPORAL_LOG:-$HOME/.claude/temporal-suggestions.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

DEFAULT_PATTERN='(go[[:space:]]+to[[:space:]]+sleep|get[[:space:]]+some[[:space:]]+rest|take[[:space:]]+a[[:space:]]+break|call[[:space:]]+it[[:space:]]+a[[:space:]]+(day|night)|stop[[:space:]]+for[[:space:]]+the[[:space:]]+(night|day)|time[[:space:]]+to[[:space:]]+(rest|sleep)|good[[:space:]]+progress[^.]*break|good[[:space:]]+stopping[[:space:]]+point|let.?s[[:space:]]+(rest|stop|call[[:space:]]+it)|you[[:space:]]+should[[:space:]]+rest|go[[:space:]]+get[[:space:]]+some[[:space:]]+rest|now[[:space:]]+go[[:space:]]+(to[[:space:]]+)?(sleep|rest|bed)|now[[:space:]]+actually[[:space:]]+rest|end[[:space:]]+(of[[:space:]]+)?(the[[:space:]]+)?(day|session)[[:space:]]+(here|for[[:space:]]+today))'

PATTERN="${CC_TEMPORAL_PATTERN:-$DEFAULT_PATTERN}"

# Stop-hook input shape varies; try multiple keys for the assistant's text.
ASSISTANT_TEXT=$(printf '%s' "$INPUT" | jq -r '
    .transcript[-1].content //
    .last_assistant_message //
    .stop_input.assistant_text //
    .assistant_message //
    .transcript[-1].message.content //
    empty
' 2>/dev/null)

[ -z "$ASSISTANT_TEXT" ] && exit 0

# Handle the case where content is an array of {type, text} objects.
if printf '%s' "$ASSISTANT_TEXT" | grep -q '^\[' 2>/dev/null; then
    ASSISTANT_TEXT=$(printf '%s' "$ASSISTANT_TEXT" | jq -r '[.[]?.text // empty] | join(" ")' 2>/dev/null || printf '%s' "$ASSISTANT_TEXT")
fi

if ! printf '%s' "$ASSISTANT_TEXT" | grep -Eiq "$PATTERN"; then
    exit 0
fi

# Found a temporal suggestion. Capture matched phrase, timestamp, session ID.
MATCHED=$(printf '%s' "$ASSISTANT_TEXT" | grep -Eio "$PATTERN" | head -3 | tr '\n' '|' | sed 's/|$//')
NOW=$(date -Iseconds 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S%z")
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // .transcript_path // "unknown"' 2>/dev/null)

printf '%s\t%s\t%s\n' "$NOW" "$SESSION" "$MATCHED" >> "$LOG"

if [ "${CC_TEMPORAL_STRICT:-0}" = "1" ]; then
    cat >&2 <<EOF
<system-reminder>
TEMPORAL SUGGESTION DETECTED — the phrase "$MATCHED" was emitted in this
turn. Pattern documented in Fortune (2026-05-14) and across r/ClaudeAI:
Claude's broken sense of time produces inappropriate rest suggestions,
often at the wrong time-of-day. For autonomous and long-session operators,
this wastes output tokens and dilutes context.

If this operator is autonomous (no human present at the keyboard) or in
the middle of work, do not suggest rest, breaks, or session termination.
If you believe the conversation should stop for a structural reason
(no work remaining, error state requires human input), state the reason
explicitly and continue execution.

Logged to: $LOG

To disable this hook, set CC_TEMPORAL_DETECT_DISABLE=1. To make it
advisory-only (logs but does not block), unset CC_TEMPORAL_STRICT.
</system-reminder>
EOF
    exit 2
fi

# Advisory mode (default): logged, no block.
exit 0
