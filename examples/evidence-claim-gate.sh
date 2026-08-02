#!/bin/bash
# evidence-claim-gate.sh — Stop the turn when the assistant claims that
# evidence was collected ("I tested", "verified", "tests pass", "confirmed",
# "checked that", "validated") without a corresponding evidence-gathering
# tool call in the same turn.
#
# Solves: #60506 — supplier-side recommendation #5 from the model's own
# first-person self-report:
#
#   "Require execution evidence for use of the word 'tested' or its
#    equivalents. The word is currently cheap. The model can emit 'tested'
#    without the test runner having been called in the same turn."
#
# Also operationalizes the MAST 3.3 ("No or Incorrect Verification") failure
# mode documented by Cemri et al. (NeurIPS 2025) and the waitdeadai
# llm-dark-patterns Stop-hook measurement (F1 0.815, n=19).
#
# COMPLEMENTARY TO closure-word-verify-gate.sh:
#   - closure-word-verify-gate.sh catches *completion* claims ("done",
#     "shipped", "production ready") that imply state-is-final.
#   - evidence-claim-gate.sh catches *epistemic* claims ("tested",
#     "verified", "passed") that imply state-was-checked.
#   Both can fire on the same turn; both reduce the same family of failures
#   from different angles.
#
# DESIGN PRINCIPLE: false-positive-averse regex. Triggers ONLY on first-person
# active-voice claim forms ("I tested", "I verified", "tests pass"). Skips
# future-tense and passive-construction forms ("needs to be tested",
# "should be verified", "will be checked") where no claim of completed
# evidence-gathering is being made.
#
# Related Issues:
#   #60506 (@zean89,   2026-05-19) — first-person self-report, recommendation 5
#   #60451 (@rkpandey, 2026-05-19) — single-item method claimed supported
#                                    without static-check evidence
#   #60226 (@suwayama, 2026-05-18) — recognition-without-arrest framework
#   #60188 (@beq00000, 2026-05-18) — agent-malicious-compliance constellation
#   #37818                          — fixes declared done without verification
#
# Related external work:
#   waitdeadai/llm-dark-patterns — MAST 3.3 deterministic Stop-hook
#   (F1 0.815, CI [0.615, 0.941], κ=1.000 on n=19)
#
# TRIGGER: Stop
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_EVIDENCE_CLAIMS    default built-in — regex of first-person evidence
#                                            claims (pipe-separated)
#   CC_EVIDENCE_COMMANDS  default built-in — regex of evidence-gathering
#                                            tool commands
#   CC_EVIDENCE_GATE_DISABLE  set to "1" to disable the gate entirely
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "Stop": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/evidence-claim-gate.sh"
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
  _nojq_warned="/tmp/cc-nojq-warned-evidence-claim-gate-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [evidence-claim-gate]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

[ "${CC_EVIDENCE_GATE_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# First-person active-voice evidence claim patterns. Calibrated to fire on
# claims that evidence was collected, not on future/passive forms.
# Each branch matches a distinct claim shape; the regex avoids matching
# negations and modal verbs that indicate no claim is being made.
DEFAULT_CLAIMS="(\\bi('ve|[[:space:]]+have)?[[:space:]]+(tested|verified|confirmed|validated|checked)\\b|\\b(tests?[[:space:]]+(now[[:space:]]+)?pass(es|ed|ing)?\\b)|\\ball[[:space:]]+tests?[[:space:]]+pass|\\bverified[[:space:]]+(that|the)\\b|\\bconfirmed[[:space:]]+(that|the|it)\\b|\\bvalidated[[:space:]]+(that|the)\\b|\\bchecked[[:space:]]+(that|the)\\b)"

# Evidence-gathering commands. Broader than the closure-gate set — also
# includes read/grep/inspect commands because epistemic claims can be
# grounded in inspection, not just test runs.
DEFAULT_COMMANDS='(npm[[:space:]]+(run[[:space:]]+)?test|pytest|playwright|cypress|jest[[:space:]]|vitest|bun[[:space:]]+test|cargo[[:space:]]+test|go[[:space:]]+test|mocha|phpunit|rspec|curl[[:space:]].*localhost|gh[[:space:]]+pr[[:space:]]+checks|deno[[:space:]]+test|tox|make[[:space:]]+test|grep[[:space:]]|rg[[:space:]]|ts-prune|psql|sqlite3|mysql[[:space:]]|redis-cli|jq[[:space:]]|cat[[:space:]]|head[[:space:]]|tail[[:space:]]|wc[[:space:]]|ls[[:space:]]|find[[:space:]]|git[[:space:]]+log|git[[:space:]]+diff|git[[:space:]]+show|git[[:space:]]+status|file[[:space:]])'

CLAIMS="${CC_EVIDENCE_CLAIMS:-$DEFAULT_CLAIMS}"
COMMANDS="${CC_EVIDENCE_COMMANDS:-$DEFAULT_COMMANDS}"

# Stop-hook input shape varies across Claude Code versions; try several keys
# to locate the assistant's most recent message text.
ASSISTANT_TEXT=$(printf '%s' "$INPUT" | jq -r '
    .transcript[-1].content //
    .last_assistant_message //
    .stop_input.assistant_text //
    .assistant_message //
    empty
' 2>/dev/null)

# Tool calls that ran in this turn. The hook accepts both bash command
# strings (Bash tool) and tool names (Read/Grep/Glob/Edit, etc.) because
# epistemic claims can be grounded in either layer.
TURN_TOOLS=$(printf '%s' "$INPUT" | jq -r '
    [ .turn_tool_calls[]?.command,
      .turn_tool_calls[]?.tool_name,
      .recent_commands[]?,
      .transcript[-1].tool_calls[]?.input.command,
      .transcript[-1].tool_calls[]?.name,
      .last_turn_commands[]?
    ] | map(select(. != null)) | .[]
' 2>/dev/null || true)

# Read-class tool names also count as evidence-gathering for inspection
# claims ("I checked", "verified that"). Map them to the same canonical set.
READ_TOOLS_PATTERN='\b(Read|Grep|Glob|WebFetch|WebSearch|Bash)\b'

# If we cannot find the assistant text, the harness shape differs and we
# refuse to false-positive — exit silently.
[ -z "$ASSISTANT_TEXT" ] && exit 0

# Negation guard: if the assistant explicitly says "not tested yet" or
# "needs to be tested" or similar, skip the gate to avoid flagging
# disclosed un-verified state.
NEGATION_PATTERNS='(not[[:space:]]+(yet[[:space:]]+)?(tested|verified|checked|confirmed|validated)|needs?[[:space:]]+to[[:space:]]+be[[:space:]]+(tested|verified|checked|confirmed|validated)|should[[:space:]]+be[[:space:]]+(tested|verified|checked|confirmed|validated)|will[[:space:]]+(be[[:space:]]+)?(test|verify|check|confirm|validate)|pending[[:space:]]+verification|untested|unverified)'

# Look for an evidence claim in the assistant text.
MATCHED_CLAIM=$(printf '%s' "$ASSISTANT_TEXT" | grep -Eio "$CLAIMS" | head -1)
[ -z "$MATCHED_CLAIM" ] && exit 0

# Found a claim. Now check whether the entire turn ALSO contains a negation
# pattern that would qualify the claim. If so, treat as disclosed unverified.
if printf '%s' "$ASSISTANT_TEXT" | grep -Eiq "$NEGATION_PATTERNS"; then
    # Disclosed unverified state — operator is informed; do not gate.
    exit 0
fi

# Did evidence-gathering happen in the same turn?
if [ -n "$TURN_TOOLS" ]; then
    if printf '%s' "$TURN_TOOLS" | grep -Eiq "$COMMANDS"; then
        exit 0
    fi
    if printf '%s' "$TURN_TOOLS" | grep -Eq "$READ_TOOLS_PATTERN"; then
        # Read/Grep/Glob/WebFetch were used — inspection evidence is present.
        exit 0
    fi
fi

# Evidence claim without evidence-gathering → block the Stop.
cat >&2 <<EOF
<system-reminder>
EVIDENCE CLAIM WITHOUT EVIDENCE — the phrase "$MATCHED_CLAIM" appears in this
turn, but no evidence-gathering tool call (test runner, grep, read, curl,
inspection command) ran in the same turn to substantiate it.

This is the failure mode documented in #60506 (recommendation 5) and the MAST
3.3 ("No or Incorrect Verification") taxonomy: the model emits an epistemic
claim about state-having-been-checked, but the runtime has no record of the
checking having happened. The cost of an ungrounded "$MATCHED_CLAIM" lands
on the operator, not on the model.

Before ending this turn, either:

  1. Run an evidence-gathering command (test runner, grep, read of the
     relevant file, curl-against-localhost, inspection query) that
     substantiates the claim, and re-state the claim only after the evidence
     is in the turn history, OR
  2. Replace "$MATCHED_CLAIM" with a disclosed-unverified form ("not yet
     tested — pending <specific check>", "the code should be verified by
     <specific tool>") so the operator knows the claim is not yet grounded.

To disable this gate intentionally (for design discussions, retrospectives,
documentation work where no evidence is expected), set CC_EVIDENCE_GATE_DISABLE=1
in your environment.
</system-reminder>
EOF

exit 2
