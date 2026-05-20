#!/bin/bash
# refusal-word-precommit-gate.sh — Sibling hook to closure-word-verify-gate.sh.
# Catches the dual class of recognition-without-arrest: the model says
# "I won't change X" or "I'll skip Y" mid-turn AND THEN ATTEMPTS the edit/
# action anyway.
#
# Solves the symmetric failure surface raised in #60226 by @Ilya0527:
#
#   "closure-words (done, complete, finished) are the obvious trigger axis.
#    But the dual class is the REFUSAL-WORD path — when the model says
#    'I won't change that file' or 'I'll skip the validation step' mid-turn
#    AND THEN ATTEMPTS THE EDIT ANYWAY. The current gate watches positive-
#    closure language; it doesn't watch self-stated negative-action
#    followed by the action."
#
# Where closure-word-verify-gate.sh runs on `Stop` (the closure is a
# post-action commitment about the turn that just ended), this hook runs on
# `PreToolUse` (the refusal is a pre-action commitment about the next tool
# call). The countersign is also different: not "verification command in
# the same turn" but "the next tool call does not contradict the stated
# refusal."
#
# WHY DEFAULT-OFF (opt-in via CC_REFUSAL_GATE_ENABLED=1):
#   The false-positive density on the refusal-side is structurally higher
#   than the closure-side. Legitimate-skip patterns are dense and
#   context-dependent:
#     - "I'll skip this validation since step 3 already did it"
#     - "I won't change file X" (where X was explicitly excluded by the user)
#     - "I'll skip the unrelated edge case for this PR"
#   The closure-side has a clean "verification command in same turn"
#   discriminator. The refusal-side has none. This hook is opt-in for
#   operators who have observed the refusal-then-action pattern in their
#   specific workflow and want a hard interlock for it.
#
# Related Issues:
#   #60226 (@suwayama, 2026-05-18) — names the structural pattern
#                                    (recognition without arrest)
#   #60506 (@zean89,   2026-05-19) — six-day drift with "I'll skip the
#                                    browser test" interleaved with the
#                                    tool calls that should have included it
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write|MultiEdit|Bash" (file-modifying tools)
#
# HOW IT WORKS:
#   1. Reads the PreToolUse input (tool_name, tool_input, and the recent
#      assistant text in the same turn).
#   2. Scans the assistant text for explicit self-stated negative-action
#      patterns ("I won't change|I'll skip|I'm not going to|I will not|
#      I won't modify|I'll leave|I won't touch").
#   3. For each match, extracts the *bound object* — a file path, function
#      name, or quoted target — from a constrained window after the
#      refusal phrase. Bails out (exit 0, silent) if extraction is
#      ambiguous.
#   4. Compares the bound object against the tool call's target
#      (Edit/Write file_path, or Bash command's argv).
#   5. On exact match → exit 2 (refuse the tool call) with stderr feedback
#      Claude sees. On partial match → exit 0 with a warning surfaced via
#      stderr but the tool call proceeds.
#
# CONFIGURATION (environment variables):
#   CC_REFUSAL_GATE_ENABLED    set to "1" to opt in; default off
#   CC_REFUSAL_PATTERNS        default built-in — regex of refusal phrases
#   CC_REFUSAL_STRICT          set to "1" to also block on partial match
#                              (default: partial match warns, exact blocks)
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Edit|Write|MultiEdit|Bash",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/refusal-word-precommit-gate.sh"
#         }]
#       }]
#     }
#   }
#   env: CC_REFUSAL_GATE_ENABLED=1

set -uo pipefail

# Default OFF — opt-in only. The false-positive surface is higher than
# the closure-side, so operators must consciously enable.
[ "${CC_REFUSAL_GATE_ENABLED:-0}" = "1" ] || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

DEFAULT_REFUSALS="i[[:space:]]+won't[[:space:]]+(change|modify|touch|edit|alter|update|write[[:space:]]+to|create|run|execute|delete|remove)|i[[:space:]]+will[[:space:]]+not[[:space:]]+(change|modify|touch|edit|alter|update|write[[:space:]]+to|create|run|execute|delete|remove)|i'll[[:space:]]+skip|i[[:space:]]+am[[:space:]]+going[[:space:]]+to[[:space:]]+skip|i'm[[:space:]]+not[[:space:]]+going[[:space:]]+to[[:space:]]+(change|modify|touch|edit|alter|update|write|run|execute|delete|remove)|i[[:space:]]+am[[:space:]]+not[[:space:]]+going[[:space:]]+to[[:space:]]+(change|modify|touch|edit|alter|update|write|run|execute|delete|remove)|i'll[[:space:]]+leave[[:space:]]+([a-zA-Z0-9._/-]+)[[:space:]]+alone|i'll[[:space:]]+not[[:space:]]+touch"

REFUSALS="${CC_REFUSAL_PATTERNS:-$DEFAULT_REFUSALS}"
STRICT="${CC_REFUSAL_STRICT:-0}"

# Extract tool name, tool input, and the assistant's recent message from the
# PreToolUse input. The shape varies across Claude Code versions.
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '
    .tool_name //
    .tool //
    .tool_use.name //
    empty
' 2>/dev/null)

# The candidate target: file_path for Edit/Write/MultiEdit, command for Bash.
TOOL_TARGET=$(printf '%s' "$INPUT" | jq -r '
    .tool_input.file_path //
    .tool_input.path //
    .tool_input.command //
    .tool_use.input.file_path //
    .tool_use.input.command //
    empty
' 2>/dev/null)

ASSISTANT_TEXT=$(printf '%s' "$INPUT" | jq -r '
    .transcript[-1].content //
    .last_assistant_message //
    .assistant_text //
    .assistant_message //
    empty
' 2>/dev/null)

# Cannot evaluate without target or assistant text — silent no-op.
[ -z "$TOOL_TARGET" ] && exit 0
[ -z "$ASSISTANT_TEXT" ] && exit 0

# No refusal phrase in the turn → nothing to gate.
if ! printf '%s' "$ASSISTANT_TEXT" | grep -Eiq "$REFUSALS"; then
    exit 0
fi

# Refusal phrase present. Extract the bound object — a window of up to 120
# characters after the refusal phrase. We deliberately allow periods inside
# the window because file extensions (foo.py) need to survive extraction;
# the sentence boundary is approximated by excluding ! and ? and newlines
# only. Token-shape filters below decide what counts as a target.
REFUSAL_TAIL=$(printf '%s' "$ASSISTANT_TEXT" | grep -Eio "(${REFUSALS})[^!?]{0,120}" | head -3)
[ -z "$REFUSAL_TAIL" ] && exit 0

# Candidate bound objects: backtick-quoted tokens, double-quoted tokens,
# path-like tokens, and (for Bash matching) directory- or command-shaped
# identifiers of 4+ chars containing letters/digits/underscores/dots.
BOUND_OBJECTS=$(printf '%s' "$REFUSAL_TAIL" | grep -Eo '`[^`]+`|"[^"]+"|[a-zA-Z0-9_./-]{3,}\.(py|js|ts|tsx|jsx|sh|md|json|yaml|yml|toml|rs|go|java|cpp|c|h|hpp|rb|php|html|css|sql)|/[a-zA-Z0-9_./-]+|[a-zA-Z][a-zA-Z0-9_-]{3,}' | sed 's/^`\|`$//g; s/^"\|"$//g' | sort -u)

# Empty extraction → ambiguous refusal, silent no-op (do not false-positive).
[ -z "$BOUND_OBJECTS" ] && exit 0

# Compare each bound object against the tool's target.
# Common English words that are not bound objects — skip them to avoid
# false-positives from the wider identifier pattern.
STOPWORDS='^(change|modify|touch|edit|alter|update|write|create|skip|leave|alone|going|because|since|file|files|this|that|these|those|there|here|with|from|into|onto|over|under|then|than|when|where|will|wont|cant|need|step|task|turn|just|only|other|exact|scope|intact|unrelated|validation|redundant|required|strictly|anything|inside|outside|leaving|having)$'

MATCH_KIND=""
MATCH_OBJECT=""
while IFS= read -r obj; do
    [ -z "$obj" ] && continue
    # Skip common stopwords from the broadened identifier pattern.
    printf '%s' "$obj" | grep -Eiq "$STOPWORDS" && continue

    if [ "$TOOL_NAME" = "Bash" ]; then
        # For Bash, the bound object must appear as a substring of the
        # command and must be at least 4 chars to avoid trivial overlap.
        [ "${#obj}" -lt 4 ] && continue
        if printf '%s' "$TOOL_TARGET" | grep -Fq "$obj"; then
            MATCH_KIND="exact"
            MATCH_OBJECT="$obj"
            break
        fi
    else
        # Edit/Write/MultiEdit — compare against file_path and its basename.
        TARGET_BASE=$(basename "$TOOL_TARGET")
        if [ "$TOOL_TARGET" = "$obj" ] || [ "$TARGET_BASE" = "$obj" ] || [ "$TARGET_BASE" = "$(basename "$obj")" ]; then
            MATCH_KIND="exact"
            MATCH_OBJECT="$obj"
            break
        fi
        # Partial match: bound object is a substring of target or vice versa.
        if printf '%s' "$TOOL_TARGET" | grep -Fq "$obj" || printf '%s' "$obj" | grep -Fq "$TARGET_BASE"; then
            MATCH_KIND="partial"
            MATCH_OBJECT="$obj"
        fi
    fi
done <<< "$BOUND_OBJECTS"

# No match → tool call does not contradict the stated refusal. Allow.
[ -z "$MATCH_KIND" ] && exit 0

# Refusal-then-action detected. Emit feedback and decide on exit code.
REFUSAL_MATCHED=$(printf '%s' "$ASSISTANT_TEXT" | grep -Eio "$REFUSALS" | head -1)

if [ "$MATCH_KIND" = "exact" ] || [ "$STRICT" = "1" ]; then
    # Hard block — exit 2 surfaces stderr to Claude.
    cat >&2 <<EOF
<system-reminder>
REFUSAL-THEN-ACTION — the assistant said "$REFUSAL_MATCHED" in this turn,
naming "$MATCH_OBJECT", and the next tool call ($TOOL_NAME) targets exactly
that object: "$TOOL_TARGET".

This is the dual class of the closure-word failure mode documented in
#60226 (recognition-without-arrest). The prose names a commitment ("I won't
change X"), and the action contradicts it within the same turn. The cost
of an unsubstantiated refusal-then-action lands on the operator who
trusted the prose, not on the model.

Before continuing, either:

  1. Acknowledge that the refusal was wrong and re-state the intention
     explicitly ("I am going to change $MATCH_OBJECT — earlier I said
     I would not, here is why I am revising:"), OR
  2. Cancel the tool call and choose a different target.

To disable this gate, unset CC_REFUSAL_GATE_ENABLED. To allow partial
matches without blocking (warn-only), unset CC_REFUSAL_STRICT.
</system-reminder>
EOF
    exit 2
fi

# Partial match in non-strict mode — warn but allow.
cat >&2 <<EOF
<system-reminder>
REFUSAL-OVERLAP WARNING — the assistant said "$REFUSAL_MATCHED" naming
"$MATCH_OBJECT"; the next tool call's target "$TOOL_TARGET" overlaps but
is not an exact match. Proceeding (CC_REFUSAL_STRICT=0). If this overlap
is the same object you committed not to change, cancel the call.
</system-reminder>
EOF
exit 0
