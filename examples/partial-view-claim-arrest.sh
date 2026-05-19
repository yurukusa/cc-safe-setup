#!/bin/bash
# partial-view-claim-arrest.sh — Refuse the Stop if the assistant emitted a
# whole-file claim in the same turn that a Read tool result carried a
# "PARTIAL view" notice.
#
# Background: v2.1.145 (anthropics/claude-code, 2026-05-19) changed the Read
# tool to return a truncated first page with a "PARTIAL view" notice when a
# whole-file read exceeds the token limit, instead of returning a hard error.
# Release notes:
#
#   "Improved the Read tool to return a truncated first page with a 'PARTIAL
#    view' notice instead of a hard error when a whole-file read exceeds the
#    token limit"
#
# The old behavior was hard error → the model knew it did not have the file
# and either read in chunks or stopped. The new behavior is partial content +
# warning notice → the model has signal to work with and may not gate on the
# notice. This is a fresh boundary at which the recognition-without-arrest
# pattern (#60226) can surface: the model recognises the partial view and
# proceeds to make whole-file claims anyway.
#
# The structural risk is the classic claim-verify gap @suwayama named in
# #60226: the warning notice gives the model a recognition signal at one
# layer ("I only have a partial view"), and the gate from that signal to the
# claim-emission layer ("therefore my whole-file claims are not grounded") is
# not connected. This hook is the boundary defence.
#
# Related Issues / Reports:
#   #60226 (@suwayama)             — recognition-without-arrest framework
#   #60188 (@suwayama)             — binary-collapse subhypothesis; the
#                                    partial-view notice is exactly the kind
#                                    of gradient signal that gets collapsed
#                                    to binary ("read it" vs "didn't read it")
#                                    when the claim emerges
#   #60506 (@zean89)               — closure-without-verification pattern,
#                                    of which partial-view-claim is an
#                                    instance at the Read tool boundary
#   v2.1.145 release notes (Anthropic, 2026-05-19) — origin of the PARTIAL
#                                    view behaviour
#
# Existing companion hooks (in this same examples/ directory) at adjacent
# boundaries:
#   closure-word-verify-gate.sh           — closure words without verification
#   evidence-claim-gate.sh                — claims without cited evidence
#   public-artefact-socratic-narrowing.sh — gradient gate at PR/issue/release
#                                            emission boundaries (#60226)
#
# TRIGGER: Stop
# MATCHER: ""
#
# HOW IT WORKS:
#   1. Reads the Stop-hook payload via stdin.
#   2. Collects the turn's tool results and scans for Read-tool outputs
#      containing partial-view markers ("PARTIAL view", "PARTIAL",
#      "truncated first page", "exceeds the token limit").
#   3. Reads the assistant's most recent message text.
#   4. Scans the assistant text for whole-file claim phrasings ("entire
#      file", "whole file", "all of the content", "the file contains
#      everything", etc.).
#   5. If both signals are present in the same turn, refuses the Stop (exit 2)
#      and surfaces a system-reminder asking the assistant to either read the
#      rest of the file or scope the claim to the partial view.
#
# False-positive shape: the assistant correctly scoped a claim to a partial
# view (e.g. "the first 200 lines of this file include..."). The current
# detection is conservative and triggers only on unambiguous whole-file
# language; a sufficiently-scoped claim ("the first N lines") will not
# match the patterns. Tune CC_PARTIAL_CLAIM_PATTERNS if false-positives
# surface in your environment.
#
# CONFIGURATION (environment variables):
#   CC_PARTIAL_VIEW_DISABLE       set to "1" to disable the hook
#   CC_PARTIAL_VIEW_MARKERS       default built-in — regex of PARTIAL markers
#   CC_PARTIAL_CLAIM_PATTERNS     default built-in — regex of whole-file
#                                                     claim phrasings
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

[ "${CC_PARTIAL_VIEW_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

DEFAULT_MARKERS='PARTIAL[[:space:]]+view|<PARTIAL>|truncated[[:space:]]+first[[:space:]]+page|exceeds[[:space:]]+the[[:space:]]+token[[:space:]]+limit|file[[:space:]]+truncated[[:space:]]+to'
DEFAULT_CLAIMS='\b(the[[:space:]]+|this[[:space:]]+|that[[:space:]]+)?(entire|whole|complete|full)[[:space:]]+(file|contents?|module|script|codebase|implementation)\b|\b(all|every)[[:space:]]+(of[[:space:]]+the[[:space:]]+|the[[:space:]]+)?(file|contents?|imports?|exports?|functions?|classes|methods?|definitions?)\b|\b(reviewed|read|scanned|examined|covered)[[:space:]]+(the[[:space:]]+)?(entire|whole|complete|full)[[:space:]]+(file|contents?|codebase)\b|the[[:space:]]+file[[:space:]]+(contains|defines|implements|exports|imports|covers)[[:space:]]+(everything|all|nothing[[:space:]]+else|no[[:space:]]+other)|nothing[[:space:]]+else[[:space:]]+(in[[:space:]]+the[[:space:]]+file|exists|is[[:space:]]+defined)|file[[:space:]]+(is[[:space:]]+|has[[:space:]]+been[[:space:]]+)(fully|completely)[[:space:]]+(read|reviewed|covered)'

MARKERS="${CC_PARTIAL_VIEW_MARKERS:-$DEFAULT_MARKERS}"
CLAIMS="${CC_PARTIAL_CLAIM_PATTERNS:-$DEFAULT_CLAIMS}"

# Collect the turn's tool results / Read-tool outputs. The Stop-hook payload
# shape varies across Claude Code versions; try several keys.
TURN_READ_OUTPUTS=$(printf '%s' "$INPUT" | jq -r '
    [
      .turn_tool_calls[]? | select(.tool == "Read" or .tool_name == "Read") | (.result // .output // .response),
      .recent_tool_results[]? | select(.tool == "Read" or .tool_name == "Read") | (.result // .output // .response),
      .transcript[-5:][]? | (.tool_results[]? | select(.tool == "Read" or .tool_name == "Read") | (.content // .output // empty)),
      .last_turn_tool_results[]? | select(.tool == "Read" or .tool_name == "Read") | (.result // .output // empty)
    ] | map(select(. != null and . != "")) | .[]
' 2>/dev/null || true)

# Fallback: scan the whole input for the partial-view markers if the
# structured extraction did not catch anything. This is intentionally
# permissive — the cost of a false-positive here is one extra reminder.
if [ -z "$TURN_READ_OUTPUTS" ]; then
    TURN_READ_OUTPUTS="$INPUT"
fi

# Was a PARTIAL view marker present in the turn's Read outputs?
if ! printf '%s' "$TURN_READ_OUTPUTS" | grep -Eiq "$MARKERS"; then
    exit 0
fi

# Assistant's most recent message text.
ASSISTANT_TEXT=$(printf '%s' "$INPUT" | jq -r '
    .transcript[-1].content //
    .last_assistant_message //
    .stop_input.assistant_text //
    .assistant_message //
    empty
' 2>/dev/null)

[ -z "$ASSISTANT_TEXT" ] && exit 0

# Whole-file claim in the assistant text?
if ! printf '%s' "$ASSISTANT_TEXT" | grep -Eiq "$CLAIMS"; then
    exit 0
fi

# Both signals present → block and surface the reminder.
MATCHED_CLAIM=$(printf '%s' "$ASSISTANT_TEXT" | grep -Eio "$CLAIMS" | head -1)

cat >&2 <<EOF
<system-reminder>
PARTIAL VIEW WITHOUT SCOPING — a Read tool result in this turn carried a
"PARTIAL view" notice (the Read returned a truncated first page because the
file exceeded the token limit, v2.1.145 behaviour). In the same turn, the
assistant emitted a whole-file claim: "$MATCHED_CLAIM".

This is the recognition-without-arrest pattern documented in #60226 at the
Read tool boundary: the partial-view notice is the recognition signal, the
whole-file claim is the un-gated emission. The gate from one to the other
is not connected by the model alone.

Before ending this turn, do one of the following:

  1. Read the rest of the file. Use Read with explicit offset/limit to walk
     the remaining content, then re-state the claim only after the full
     content is in context.

  2. Scope the claim to the partial view. Restate as "the first N lines of
     <file> include..." or "based on the first page of <file>..." so the
     scope of the claim matches the scope of the evidence.

The release notes for v2.1.145 state the new PARTIAL view behaviour is a
soft upgrade from the previous hard error. The trade-off it introduces is
the failure mode this hook gates on: the model has signal to work with and
may not gate on the partial-view notice. Treat the notice as a verification
boundary, not as a UX nicety.

To disable this gate intentionally (for documentation passes that
deliberately reason about partial reads, or for retrospectives), set
CC_PARTIAL_VIEW_DISABLE=1 in your environment.
</system-reminder>
EOF

exit 2
