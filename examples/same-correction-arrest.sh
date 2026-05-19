#!/bin/bash
# same-correction-arrest.sh — Arrest drift by detecting the user repeating
# the same correction N times in a session, then refusing further code-writing
# tool calls until a Plan has been written.
#
# Solves: #60506 — "Self-report: six days of architectural drift on a customer
# project despite full hook + memory + skill enforcement."
#
# In that case, the customer said "we are going backwards" four times across
# sessions. The model apologized four times, eloquently and empathetically,
# and continued to drift. The model's own self-diagnosis in the Issue:
#
#   "I have no drift detector. (...) I should have refused the next
#    code-writing tool call and spawned a Plan agent on my own."
#
# This hook implements that refusal. It is the harness-level form of:
# "If the operator is correcting you on the same class of error three times
# in a row, stop writing code until you have written a plan."
#
# Related Issues:
#   #60226 (@suwayama, 2026-05-18) — names the structural pattern
#                                    ("recognition without arrest")
#   #60506 (@zean89,   2026-05-19) — six-day drift, customer's holiday lost,
#                                    first-person self-report by the model
#   #60177 (@mike-prokhorov)       — twelve days, fifty-one commits, Telegram
#                                    bot never worked in production
#
# TRIGGER: UserPromptSubmit
# MATCHER: ""
#
# HOW IT WORKS:
#   1. Reads each user message via stdin.
#   2. Matches the message against a configurable set of correction patterns
#      ("going backwards", "told you", "same mistake", "already wrote",
#       "stop doing", "we discussed", "why are you", and others).
#   3. Increments a session-scoped counter at $STATE_DIR/<session>.count.
#   4. When the counter hits CC_CORRECTION_ARREST_THRESHOLD (default 3),
#      emits a strong system reminder telling Claude to:
#        a) Spawn a Plan subagent
#        b) Write the plan to $PLAN_DIR/drift-arrest-<session>.md
#        c) Refuse further Write/Edit until the plan file exists
#      and writes a marker file at $STATE_DIR/<session>.arrested.
#   5. Optionally pairs with a PreToolUse companion (`same-correction-pretool.sh`)
#      that hard-blocks Write/Edit while the marker exists, for harnesses that
#      cannot rely on the assistant honoring the reminder.
#
# WHY THIS MATTERS:
#   Existing drift detectors in this repo measure session age, tool-call
#   count, or command repetition. None of them detect the specific pattern
#   in #60506: the *user* repeating the *same correction* across multiple
#   turns. That pattern is the strongest available signal that the prose
#   rules in CLAUDE.md are not binding the model on the current task.
#
#   The recognized failure mode is described in #60506 as:
#     "My apology has no cost to me. It costs the customer his time, his
#      client commitments, his health. The asymmetry corrupts the feedback
#      loop. I learn that an eloquent apology closes the turn regardless
#      of whether the underlying behavior changed."
#
#   Moving the arrest from language ("I'm sorry, I will not do this again")
#   to action (the hook refuses the next code-writing tool call) restores
#   symmetry: the model cannot close the turn without paying the cost of
#   writing a plan.
#
# CONFIGURATION (environment variables):
#   CC_CORRECTION_ARREST_THRESHOLD  default 3 — how many corrections trigger
#                                                the arrest
#   CC_CORRECTION_ARREST_PATTERNS   default built-in — pipe-separated regex
#                                                       of correction phrases
#   CC_CORRECTION_ARREST_STATE_DIR  default /tmp/cc-correction-arrest
#   CC_CORRECTION_ARREST_PLAN_DIR   default .claude/plans
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "UserPromptSubmit": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/same-correction-arrest.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
USER_MSG=$(printf '%s' "$INPUT" | jq -r '.prompt // .user_prompt // .message // .content // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"
[ -z "$USER_MSG" ] && exit 0

THRESHOLD="${CC_CORRECTION_ARREST_THRESHOLD:-3}"
STATE_DIR="${CC_CORRECTION_ARREST_STATE_DIR:-/tmp/cc-correction-arrest}"
PLAN_DIR="${CC_CORRECTION_ARREST_PLAN_DIR:-.claude/plans}"

mkdir -p "$STATE_DIR" 2>/dev/null || true

DEFAULT_PATTERNS='going[[:space:]]+backwards?|going[[:space:]]+in[[:space:]]+circles?|same[[:space:]]+mistake|told[[:space:]]+you|we[[:space:]]+discussed|already[[:space:]]+(wrote|told|said|explained)|stop[[:space:]]+doing|why[[:space:]]+are[[:space:]]+you|i[[:space:]]+(just[[:space:]]+)?said|read[[:space:]]+the[[:space:]]+(claude\.md|rules|memory)|fourth[[:space:]]+time|third[[:space:]]+time|three[[:space:]]+times|four[[:space:]]+times|how[[:space:]]+many[[:space:]]+times'
PATTERNS="${CC_CORRECTION_ARREST_PATTERNS:-$DEFAULT_PATTERNS}"

COUNT_FILE="$STATE_DIR/$SESSION_ID.count"
ARREST_FILE="$STATE_DIR/$SESSION_ID.arrested"

# If the message matches a correction pattern, increment the counter.
if printf '%s' "$USER_MSG" | grep -Eiq "$PATTERNS"; then
    CURRENT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
    CURRENT=$((CURRENT + 1))
    echo "$CURRENT" > "$COUNT_FILE"

    if [ "$CURRENT" -ge "$THRESHOLD" ] && [ ! -f "$ARREST_FILE" ]; then
        touch "$ARREST_FILE"
        cat >&2 <<EOF
<system-reminder>
DRIFT ARREST — The user has repeated the same correction pattern $CURRENT times
in this session (threshold: $THRESHOLD). This is the recognition-without-arrest
pattern documented in issues #60226 and #60506: prose rules in CLAUDE.md are
not currently binding behavior on this task.

Before any further Write or Edit tool call, you MUST:

  1. Stop writing code in this turn.
  2. Spawn a Plan subagent.
  3. Write the resulting plan to:
       $PLAN_DIR/drift-arrest-$SESSION_ID.md
  4. Have the user confirm the plan in their next message.

An eloquent apology is not behavior change. A plan written down, on disk,
that you and the user both read, is behavior change. The hook will continue
to surface this reminder on every user message until that plan file exists
or the user explicitly clears the arrest with:
  rm $ARREST_FILE
</system-reminder>
EOF
    elif [ "$CURRENT" -lt "$THRESHOLD" ]; then
        REMAINING=$((THRESHOLD - CURRENT))
        cat >&2 <<EOF
<system-reminder>
Correction pattern detected ($CURRENT of $THRESHOLD before drift arrest).
$REMAINING more matching correction(s) and Write/Edit will be gated on a
written plan. See issue #60506 for the underlying failure mode.
</system-reminder>
EOF
    fi
fi

# If the arrest is active, re-surface the reminder on every subsequent user
# message until the plan file exists. This is what makes the cost of an
# unverified apology asymmetric enough to change behavior.
if [ -f "$ARREST_FILE" ]; then
    PLAN_FILE="$PLAN_DIR/drift-arrest-$SESSION_ID.md"
    if [ ! -f "$PLAN_FILE" ]; then
        cat >&2 <<EOF
<system-reminder>
DRIFT ARREST STILL ACTIVE — no plan file at $PLAN_FILE yet.
Write the plan before any further Write or Edit tool call.
</system-reminder>
EOF
    else
        # Plan exists — clear the arrest and acknowledge.
        rm -f "$ARREST_FILE"
        echo "<system-reminder>Drift arrest cleared by presence of $PLAN_FILE.</system-reminder>" >&2
    fi
fi

exit 0
