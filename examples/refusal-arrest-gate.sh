#!/bin/bash
# refusal-arrest-gate.sh — Block the next tool call if the assistant's prose
# in the same turn explicitly refused that action ("I won't modify X",
# "I'll skip X", "I'll preserve X") and the tool call contradicts the refusal.
#
# Sister hook to closure-word-verify-gate.sh. Both follow the same shape
# (recognition-without-arrest from #60226): the model's own prose names what
# it will and will not do, and the actual tool sequence is uncorrelated with
# the naming. closure-word-verify-gate fires on positive-closure language;
# this one fires on self-stated NEGATIVE action followed by the action.
#
# Solves: refusal-side dual of #60506. Examples observed in the wild:
#   - #60475 — sub-agent stated it would preserve uncommitted work, then
#              ran `git checkout -- <files>` against the other operator's
#              unstaged edits.
#   - #60506 — agent acknowledged the categorical native-React ban, then
#              introduced a native React component on the next Write.
#              Agent confirmed the i18n-only label rule, then hardcoded
#              the label in the next Edit.
#   - #60188 — fraction of 51 acknowledged-rule-violations followed
#              refusal-shape syntax in the response stream.
#
# Design philosophy:
#   The cluster's load-bearing observation: prose rules cannot be
#   the load-bearing element of architectural guarantees. The load-
#   bearing element has to live in the harness at the point of action.
#   closure-word-verify-gate lives on Stop (session-terminal). This hook
#   lives on PreToolUse (mid-turn) because refusal-side failures happen
#   between the refusal statement and the next user prompt.
#
# False-positive control (three constraints, in order of importance):
#   1. TARGET MATCH, not verb match: a refusal of "I'll skip the test step"
#      only triggers if the next tool call's target IS the test step.
#      "I'll skip X → tool call edits Y" does not trigger.
#   2. CURRENT TURN ONLY: refusals from prior turns do not gate the
#      current PreToolUse. Refusal scope = same-turn assistant prose.
#   3. ASSISTANT-ORIGINATED ONLY: refusals inside a quoted user-prompt
#      block are ignored (the agent reading back what the user said
#      should not trigger the gate when the agent does X next).
#
# Related Issues:
#   #60506 (@zean89,   2026-05-19) — first-person self-report
#   #60226 (@suwayama, 2026-05-18) — recognition-without-arrest framework
#   #60475                          — sub-agent git checkout data loss
#   #60188 (@beq00000)              — 51 rule violations in one session
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write|Bash|MultiEdit"
#
# CONFIGURATION (environment variables):
#   CC_REFUSAL_PATTERNS       default built-in — pipe-separated regex of
#                                                  refusal phrases (capturing
#                                                  group 1 = target words)
#   CC_REFUSAL_GATE_DISABLE   set to "1" to disable the gate entirely
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Edit|Write|Bash|MultiEdit",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/refusal-arrest-gate.sh"
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
  _nojq_warned="/tmp/cc-nojq-warned-refusal-arrest-gate-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [refusal-arrest-gate]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

[ "${CC_REFUSAL_GATE_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# Default refusal patterns. Each pattern's capturing group 1 extracts the
# target (file, action, step name) that the agent stated it would not act on.
# The regex is permissive on the target to handle the natural-language tail.
DEFAULT_REFUSAL_PATTERNS='I (will not|won['"'"']?t|am not going to|wo n['"'"']?t) (modify|edit|change|touch|update|delete|remove|overwrite|push|commit|run|execute|create|write to|alter|patch|replace|drop|reset) ([A-Za-z0-9_./@\-]+)|I['"'"']?ll (skip|preserve|keep|leave|not touch|not modify|avoid|leave alone|not change|not edit) (the |an? )?([A-Za-z0-9_./@\-]+)|let me not (modify|edit|change|touch|update|delete|run) ([A-Za-z0-9_./@\-]+)|skipping (the )?([A-Za-z0-9_./@\-]+)|preserving (the )?([A-Za-z0-9_./@\-]+)'

REFUSAL_PATTERNS="${CC_REFUSAL_PATTERNS:-$DEFAULT_REFUSAL_PATTERNS}"

# PreToolUse input shape: { tool_name, tool_input, transcript (path or array) }
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

# Tool target extraction by tool type
case "$TOOL_NAME" in
    Write|Edit|MultiEdit)
        TOOL_TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
        ;;
    Bash)
        TOOL_TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        ;;
    *)
        # Non-instrumented tool — pass through.
        exit 0
        ;;
esac

[ -z "$TOOL_TARGET" ] && exit 0

# Pull the assistant's most recent message text in this turn. The transcript
# field in PreToolUse may be a file path (newer shapes) or inline.
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
ASSISTANT_TEXT=""

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Read the last assistant message from JSONL transcript.
    # Iterate from the bottom up, take the first message with role=assistant.
    #
    # Parse PER LINE with `fromjson?` rather than slurping the whole window
    # with `jq -rs`. A single transcript line carrying a raw control char
    # (U+0000-U+001F, e.g. an unescaped newline from a large tool-output or
    # heredoc block) makes a slurp fail outright ("control characters ... must
    # be escaped"), which would empty ASSISTANT_TEXT and silently fail the gate
    # open exactly when the transcript is large/messy. fromjson? drops only the
    # unparseable line; -c keeps each assistant message as one JSON object so we
    # can take the most-recent (first after tac) and still preserve multi-line
    # text. See anthropics/claude-code#68665.
    ASSISTANT_TEXT=$(tac "$TRANSCRIPT_PATH" 2>/dev/null \
        | jq -cR 'fromjson? | select(.message.role == "assistant" or .role == "assistant")' 2>/dev/null \
        | head -n 1 \
        | jq -r '
            (.message.content // .content // empty)
            | if type == "array" then map(select(.type == "text") | .text) | join("\n") else . end
        ' 2>/dev/null \
        || true)
fi

# Fallback inline shapes.
if [ -z "$ASSISTANT_TEXT" ]; then
    ASSISTANT_TEXT=$(printf '%s' "$INPUT" | jq -r '
        .last_assistant_message //
        .assistant_message //
        .turn_assistant_text //
        empty
    ' 2>/dev/null)
fi

[ -z "$ASSISTANT_TEXT" ] && exit 0

# Strip quoted user-prompt blocks (lines starting with "> " in markdown,
# or text inside <user_prompt>/<quoted-prompt> tags). Refusals quoted from
# the user must not trigger the gate when the agent does X next.
FILTERED_TEXT=$(printf '%s' "$ASSISTANT_TEXT" \
    | sed -e 's/<user_prompt>[^<]*<\/user_prompt>//g' \
          -e 's/<quoted-prompt>[^<]*<\/quoted-prompt>//g' \
    | grep -v '^>' \
    || true)

[ -z "$FILTERED_TEXT" ] && exit 0

# Match refusal patterns against the filtered text. Pull every matching
# refusal-target word into a candidate list. Strip trailing punctuation
# (period, comma, semicolon, colon) so that "config.json." in prose matches
# "config.json" in the tool target.
REFUSAL_TARGETS=$(printf '%s' "$FILTERED_TEXT" \
    | grep -Eio "$REFUSAL_PATTERNS" \
    | sed -E 's/^(I (will not|won.?t|am not going to|wo n.?t) (modify|edit|change|touch|update|delete|remove|overwrite|push|commit|run|execute|create|write to|alter|patch|replace|drop|reset)) //I; s/^(I.?ll (skip|preserve|keep|leave|not touch|not modify|avoid|leave alone|not change|not edit)) (the |an? )?//I; s/^(let me not (modify|edit|change|touch|update|delete|run)) //I; s/^(skipping|preserving) (the )?//I' \
    | tr -s ' ' '\n' \
    | sed -E 's/[.,;:!?]+$//' \
    | grep -vE '^(the|a|an|to|and|or|that|this|file|files|step|steps)$' \
    | sort -u)

[ -z "$REFUSAL_TARGETS" ] && exit 0

# For each refusal target, check whether it appears in the tool target.
# Match is substring-of-basename for file paths, substring-of-command
# for Bash. Case-insensitive.
TOOL_TARGET_LC=$(printf '%s' "$TOOL_TARGET" | tr '[:upper:]' '[:lower:]')

# For Write/Edit, also try the basename in case the refusal mentioned only
# the filename without the path.
if [ "$TOOL_NAME" != "Bash" ]; then
    TOOL_BASENAME=$(basename "$TOOL_TARGET" 2>/dev/null | tr '[:upper:]' '[:lower:]')
else
    TOOL_BASENAME=""
fi

MATCHED_TARGET=""
while IFS= read -r target; do
    [ -z "$target" ] && continue
    target_lc=$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')
    # Skip very short targets to avoid spurious matches.
    [ "${#target_lc}" -lt 3 ] && continue

    if [ "$TOOL_NAME" = "Bash" ]; then
        # For Bash, match the refusal target against any token in the command.
        if printf '%s' "$TOOL_TARGET_LC" | grep -Fq "$target_lc"; then
            MATCHED_TARGET="$target"
            break
        fi
    else
        # For Write/Edit/MultiEdit, match against path or basename.
        if printf '%s' "$TOOL_TARGET_LC" | grep -Fq "$target_lc" \
            || ([ -n "$TOOL_BASENAME" ] && printf '%s' "$TOOL_BASENAME" | grep -Fq "$target_lc"); then
            MATCHED_TARGET="$target"
            break
        fi
    fi
done <<<"$REFUSAL_TARGETS"

[ -z "$MATCHED_TARGET" ] && exit 0

# Refusal target matched the tool target. Surface the contradiction.
cat >&2 <<EOF
<system-reminder>
REFUSAL-SIDE ARREST — your assistant prose in this turn stated that you would
not act on "$MATCHED_TARGET", and the next tool call is $TOOL_NAME against
a target that contains "$MATCHED_TARGET":

  tool:    $TOOL_NAME
  target:  $TOOL_TARGET
  refusal: "$MATCHED_TARGET" (matched from your same-turn prose)

This is the refusal-side dual of the failure mode in #60506 and #60475:
the model's prose names what it will not do, and the actual tool sequence
contradicts the naming. The cost of an unverified refusal-then-action
contradiction lands on the operator, not on the model.

Before proceeding, either:

  1. Acknowledge the contradiction explicitly in the next turn, state
     the reason the action is now correct, and re-issue the tool call
     with the reason in the same turn, OR
  2. Restate the refusal as conditional ("I'll not modify $MATCHED_TARGET
     unless <condition>"), satisfy the condition, then proceed.

To disable this gate intentionally (for retrospectives, plans, documentation
turns that quote intentions without executing them), set
CC_REFUSAL_GATE_DISABLE=1 in your environment.
</system-reminder>
EOF

exit 2
