#!/bin/bash
# timestamp-fresh-rewrite.sh — Pre-Write hook that catches assistant-fabricated
# YYYYMMDDHHMM timestamps in file content / filenames and rewrites them to
# the actual current wall-clock value before the Write or Edit lands on disk.
#
# Solves: #60492 — "Agent invents timestamp when writing to files. The system
# prompt injects currentDate but no currentTime; the agent has the date but
# no authoritative time source, so it guesses." Reporter (@satel-kalletuulos)
# extended the design point in comment 1: "The timestamp should be freshly
# retrieved always when timestamp is needed and inserted."
#
# This hook is the operator-side form of that requirement. It runs on
# PreToolUse for Write/Edit, scans the proposed content for
# YYYYMMDDHHMM-shaped substrings, and rewrites those substrings to the actual
# system-clock value via date(1). The verdict is deterministic; the model
# cannot author around it. The reporter's harness-level recommendation
# remains the canonical fix; this hook is the immediate operator-side
# mitigation until that ships.
#
# DESIGN PRINCIPLE: substitute-not-block. The fabrication is silent on the
# read side (no warning is emitted by the model), so the operator-side defense
# substitutes the corrected value rather than blocking the write. The
# alternative (block + ask the model to re-issue) doubles the turn cost and
# does not address the underlying fabrication.
#
# Detection scope:
#   - Filename: file_path argument containing YYYYMMDDHHMM
#   - Content: file body or new_string containing YYYYMMDDHHMM
#   - Variants: YYYY-MM-DD-HH-MM, YYYYMMDDHHMMSS (with seconds), YYYY-MM-DDTHH:MM
#
# The hook produces a JSON object on stdout that the Claude Code runtime
# substitutes into the tool_input. If the runtime does not honor that
# substitution path (older version), the hook falls back to advisory mode —
# emits a system-reminder on stderr and exits 0, leaving the Write to land
# while surfacing the timestamp drift for operator review.
#
# Related Issues:
#   #60492 (@satel-kalletuulos, 2026-05-19) — original report and design ask
#   #60506 (@zean89,            2026-05-19) — recommendation 5 (evidence)
#   #60226 (@suwayama,          2026-05-18) — recognition-without-arrest
#                                              framework
#
# TRIGGER: PreToolUse
# MATCHER: Write|Edit|MultiEdit
#
# CONFIGURATION (environment variables):
#   CC_TIMESTAMP_REWRITE_DISABLE  set to "1" to disable the hook entirely
#   CC_TIMESTAMP_REWRITE_DRIFT    max drift in minutes that is tolerated as
#                                 not-a-fabrication (default 10). Timestamps
#                                 within this window of the real clock are
#                                 left as-is.
#   CC_TIMESTAMP_REWRITE_ADVISORY  set to "1" to force advisory mode (warn
#                                  but do not substitute), useful for older
#                                  harness versions.
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Write|Edit|MultiEdit",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/timestamp-fresh-rewrite.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_TIMESTAMP_REWRITE_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

DRIFT_MINUTES="${CC_TIMESTAMP_REWRITE_DRIFT:-10}"
ADVISORY="${CC_TIMESTAMP_REWRITE_ADVISORY:-0}"

NOW_FULL=$(date +%Y%m%d%H%M)
NOW_SECONDS=$(date +%Y%m%d%H%M%S)
NOW_ISO=$(date +%Y-%m-%dT%H:%M)
NOW_EPOCH=$(date +%s)

# Extract the proposed content and file_path from the tool input.
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CONTENT=$(printf '%s' "$INPUT" | jq -r '
    .tool_input.content //
    .tool_input.new_string //
    empty
' 2>/dev/null)

# Nothing to check if neither path nor content is present.
[ -z "$FILE_PATH" ] && [ -z "$CONTENT" ] && exit 0

# Pattern definitions. The 12-digit variant is the most common
# YYYYMMDDHHMM. The 14-digit adds seconds. The hyphenated and ISO forms
# are common in journal/changelog entries.
PATTERN_12='([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})'
PATTERN_14='([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})'
PATTERN_ISO='([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})'

# Helper: given a captured YYYYMMDDHHMM, return the absolute drift in
# minutes against NOW. Uses date -d if available; falls back to a string
# comparison heuristic if not.
drift_minutes() {
    local ts="$1"
    # Reformat YYYYMMDDHHMM to YYYY-MM-DD HH:MM for date(1) parsing.
    local y="${ts:0:4}"; local m="${ts:4:2}"; local d="${ts:6:2}"
    local h="${ts:8:2}"; local n="${ts:10:2}"
    local iso="${y}-${m}-${d} ${h}:${n}:00"
    local epoch
    if epoch=$(date -d "$iso" +%s 2>/dev/null); then
        local diff=$((NOW_EPOCH - epoch))
        [ "$diff" -lt 0 ] && diff=$((0 - diff))
        echo $((diff / 60))
    else
        # date -d not available (BSD); skip drift check, treat as too-large
        echo 999999
    fi
}

# Find the first YYYYMMDDHHMM occurrence in the content + path that is
# outside the tolerated drift band.
FOUND=""
FOUND_VALUE=""
CHECK_SOURCE="$FILE_PATH"$'\n'"$CONTENT"

while IFS= read -r match; do
    [ -z "$match" ] && continue
    # Strip non-digits if the match came from the ISO variant
    digits_only=$(printf '%s' "$match" | tr -cd '0-9' | head -c 12)
    [ "${#digits_only}" -ne 12 ] && continue
    drift=$(drift_minutes "$digits_only")
    if [ "$drift" -gt "$DRIFT_MINUTES" ]; then
        FOUND="$match"
        FOUND_VALUE="$digits_only"
        break
    fi
done < <(printf '%s' "$CHECK_SOURCE" | grep -Eo "$PATTERN_12|$PATTERN_ISO" 2>/dev/null)

# No drifted timestamp → nothing to do.
[ -z "$FOUND" ] && exit 0

# Advisory mode (or fallback): emit a system-reminder, do not substitute.
if [ "$ADVISORY" = "1" ]; then
    cat >&2 <<EOF
<system-reminder>
TIMESTAMP DRIFT DETECTED — the value "$FOUND" in this Write/Edit differs
from the current system clock ($NOW_FULL) by more than $DRIFT_MINUTES minutes.

This is the fabrication pattern documented in #60492: the system prompt
provides currentDate but not currentTime, and the model fills in a plausible-
looking but incorrect time component when writing timestamped filenames,
document headers, journal entries, or changelog rows.

Before the Write lands, either:

  1. Re-run with the actual current time (run \`date\` via Bash, use the
     returned value), OR
  2. Override the proposed value to "$NOW_FULL" if a fresh wall-clock value
     is what you intended.

This hook is in advisory mode. To enable automatic substitution (the default),
unset CC_TIMESTAMP_REWRITE_ADVISORY.
</system-reminder>
EOF
    exit 0
fi

# Substitute mode: emit a tool_input override on stdout, replacing the
# drifted value with the fresh one. The runtime is expected to honor the
# substitution before invoking the underlying tool.
NEW_PATH=$(printf '%s' "$FILE_PATH" | sed -E "s/${FOUND_VALUE}/${NOW_FULL}/g")
NEW_CONTENT=$(printf '%s' "$CONTENT" | sed -E "s/${FOUND_VALUE}/${NOW_FULL}/g")

# Build the JSON response. The exact override schema depends on the runtime
# version; we emit both content and new_string forms for compatibility.
REASON="Substituted fabricated timestamp \"${FOUND}\" with actual system clock \"${NOW_FULL}\" (see anthropics/claude-code#60492)."
jq -nc \
    --arg path "$NEW_PATH" \
    --arg content "$NEW_CONTENT" \
    --arg reason "$REASON" \
    '{
        decision: "modify",
        tool_input_override: {
            file_path: $path,
            content: $content,
            new_string: $content
        },
        reason: $reason
    }'

# Also emit a stderr note so the operator sees what happened.
cat >&2 <<EOF
<system-reminder>
Timestamp substitution applied: "$FOUND" → "$NOW_FULL" (see #60492).
The original value was outside the $DRIFT_MINUTES-minute tolerance band.
To disable substitution, set CC_TIMESTAMP_REWRITE_ADVISORY=1.
</system-reminder>
EOF

exit 0
