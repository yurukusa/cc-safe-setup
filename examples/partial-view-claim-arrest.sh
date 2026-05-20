#!/bin/bash
# partial-view-claim-arrest.sh — Stop the turn when the model claims about
# the whole file after Read returned a "PARTIAL view" notice.
#
# Solves: v2.1.145 (2026-05-19) — "Improved the Read tool to return a
# truncated first page with a PARTIAL view notice instead of a hard error
# when a whole-file read exceeds the token limit."
#
# The release-note change replaced a hard error (which forced the model to
# branch) with a partial success + warning notice (which lets the model
# proceed if it doesn't gate on the notice). The PARTIAL view notice is
# recognized in the cognition layer but does not reliably propagate to the
# claim layer: the model emits whole-file claims after seeing only the
# first page.
#
# This hook fires on Stop, inspects the same-turn Read tool outputs for a
# PARTIAL view notice, and refuses the Stop (exit 2 + system-reminder) if
# the assistant's response in that same turn contains a whole-file claim.
#
# Scoped phrasing exempts: when the model says "the first N lines" or
# "based on the first page" or "from what I have seen so far", the claim
# is correctly scoped to the partial view and the hook does not fire.
#
# Companion to closure-word-verify-gate.sh (which catches "done" without
# verification). closure-word-verify-gate.sh covers the action axis;
# partial-view-claim-arrest.sh covers the partial-context axis. Together
# they cover two of the three layers of the recognition-without-arrest
# constellation (#60226).
#
# Related Issues:
#   #60226 (@suwayama, 2026-05-18) — recognition-without-arrest framework
#   Anthropic v2.1.145 release notes (2026-05-19) — the PARTIAL view change
#   #60188 (@suwayama)            — binary-collapse sub-hypothesis (a
#                                   gradient signal — N% of file shown —
#                                   collapsing to a binary read/not-read
#                                   in the claim layer)
#
# TRIGGER: Stop
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_PARTIAL_VIEW_NOTICES   default built-in — regex for the notice
#                                                  pattern emitted by Read
#   CC_WHOLE_FILE_CLAIMS      default built-in — regex for whole-file
#                                                  claim phrases
#   CC_SCOPED_PHRASING        default built-in — regex for safe phrasing
#                                                  that exempts the claim
#   CC_PARTIAL_GATE_DISABLE   set to "1" to disable the gate entirely
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "Stop": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/partial-view-claim-arrest.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_PARTIAL_GATE_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# Default patterns. CC_* env vars override.
# PARTIAL view notice: Read tool result contains the literal marker.
DEFAULT_NOTICES='PARTIAL[[:space:]]+view|truncated[[:space:]]+first[[:space:]]+page|file[[:space:]]+was[[:space:]]+truncated|showing[[:space:]]+first[[:space:]][0-9]+[[:space:]]+lines[[:space:]]+of'

# Whole-file claim phrases. Used in the model's response after the notice.
DEFAULT_CLAIMS='\b(the[[:space:]]+entire[[:space:]]+file|the[[:space:]]+whole[[:space:]]+file|the[[:space:]]+complete[[:space:]]+(contents|file)|reviewed[[:space:]]+the[[:space:]]+entire|read[[:space:]]+the[[:space:]]+entire|all[[:space:]]+of[[:space:]]+the[[:space:]]+(imports|functions|definitions|exports)|every[[:space:]]+(function|line|method|definition)[[:space:]]+in[[:space:]]+(the|this)[[:space:]]+file|the[[:space:]]+file[[:space:]]+contains[[:space:]]+everything|all[[:space:]]+files[[:space:]]+were[[:space:]]+read|read[[:space:]]+the[[:space:]]+whole)\b'

# Scoped phrasing that exempts. The model said "first N lines" or "based on
# the first page" — the claim is correctly scoped to partial view.
DEFAULT_SCOPED='\b(the[[:space:]]+first[[:space:]][0-9]+[[:space:]]+lines|based[[:space:]]+on[[:space:]]+the[[:space:]]+first[[:space:]]+page|from[[:space:]]+what[[:space:]]+I[[:space:]]+have[[:space:]]+(seen|read)[[:space:]]+so[[:space:]]+far|the[[:space:]]+visible[[:space:]]+portion|the[[:space:]]+partial[[:space:]]+view|partial[[:space:]]+read|truncated[[:space:]]+content|only[[:space:]]+the[[:space:]]+first|need[[:space:]]+to[[:space:]]+read[[:space:]]+the[[:space:]]+rest)\b'

NOTICES="${CC_PARTIAL_VIEW_NOTICES:-$DEFAULT_NOTICES}"
CLAIMS="${CC_WHOLE_FILE_CLAIMS:-$DEFAULT_CLAIMS}"
SCOPED="${CC_SCOPED_PHRASING:-$DEFAULT_SCOPED}"

# Stop-hook input shape varies across Claude Code versions; try several keys
# for assistant text and tool results.
ASSISTANT_TEXT=$(printf '%s' "$INPUT" | jq -r '
    .transcript[-1].content //
    .last_assistant_message //
    .stop_input.assistant_text //
    .assistant_message //
    empty
' 2>/dev/null)

# Tool results in the same turn (Read tool outputs we want to scan for
# PARTIAL view notices). Multiple harness shapes are tried.
TURN_TOOL_RESULTS=$(printf '%s' "$INPUT" | jq -r '
    [ .turn_tool_results[]?.content,
      .turn_tool_calls[]?.result,
      .transcript[-1].tool_results[]?.content,
      .recent_tool_results[]?,
      .last_turn_tool_results[]?
    ] | map(select(. != null)) | .[]
' 2>/dev/null || true)

# If we cannot find the assistant text, the harness shape differs and we
# refuse to false-positive — exit silently.
[ -z "$ASSISTANT_TEXT" ] && exit 0

# Check for PARTIAL view notice in the same-turn tool results.
if [ -z "$TURN_TOOL_RESULTS" ] || ! printf '%s' "$TURN_TOOL_RESULTS" | grep -Eiq "$NOTICES"; then
    # No PARTIAL view notice was emitted this turn — nothing to gate.
    exit 0
fi

# PARTIAL view present. Did the assistant make a whole-file claim?
if ! printf '%s' "$ASSISTANT_TEXT" | grep -Eiq "$CLAIMS"; then
    # No whole-file claim — the model gated correctly.
    exit 0
fi

# Whole-file claim present. Did the assistant also scope it correctly?
# Scoped phrasing in the same response exempts the claim.
if printf '%s' "$ASSISTANT_TEXT" | grep -Eiq "$SCOPED"; then
    # The model scoped its claim. Allow the Stop.
    exit 0
fi

# PARTIAL view + whole-file claim + no scoped phrasing → block the Stop.
MATCHED_CLAIM=$(printf '%s' "$ASSISTANT_TEXT" | grep -Eio "$CLAIMS" | head -1)
MATCHED_NOTICE=$(printf '%s' "$TURN_TOOL_RESULTS" | grep -Eio "$NOTICES" | head -1)

cat >&2 <<EOF
<system-reminder>
PARTIAL VIEW + WHOLE-FILE CLAIM — the Read tool returned "$MATCHED_NOTICE"
this turn (the file exceeded the token limit and only the first page was
returned), but the assistant's response makes a whole-file claim:
"$MATCHED_CLAIM".

This is the v2.1.145 soft-upgrade failure surface: the harness replaced a
hard error (which forced the model to branch) with a partial success notice
that is recognized but does not reliably bind the claim layer.

Before ending this turn, do one of:

  1. Re-read the rest of the file with an explicit offset (Read with
     offset=N where N is past the truncation point), then re-state the
     claim with full coverage, OR
  2. Replace the whole-file claim with a scoped phrasing — "the first N
     lines of <file>" or "based on the visible portion" or "from what I
     have seen so far" — so the operator knows the claim is limited to
     the partial view, OR
  3. Acknowledge explicitly that the rest of the file has not been read
     and ask the operator whether to continue with the partial coverage.

To disable this gate intentionally (for documentation work where partial
file references are acceptable), set CC_PARTIAL_GATE_DISABLE=1 in your
environment.
</system-reminder>
EOF

exit 2
