#!/bin/bash
# closure-word-verify-gate.sh — Stop the turn if a closure word ("done",
# "shipped", "complete", "production ready", "bitti", "finished") was used
# without a corresponding verification tool call in the same turn.
#
# Solves: #60506 — "Self-report: six days of architectural drift on a customer
# project despite full hook + memory + skill enforcement."
#
# In that case, claude-opus-4-7 reported in its own first-person Issue body:
#
#   "'Done' is cheap for me. I said 'bitti / shipped / production ready'
#    without performing a browser CRUD round-trip, even after the customer
#    wrote an explicit rule: 'no claim bitti without browser test.' Two
#    hours after the rule I said 'bitti' again, without opening the browser.
#    The customer caught me because he opened the screen."
#
# The customer's own engineering recommendation #4 in #60506:
#
#   "Quality-scorecard gate before closure words. When I emit 'shipped',
#    'complete', 'production ready', 'done', 'bitti', require — by hook
#    or by tool — that a quality-scorecard tool was called in the same
#    turn. Otherwise replace the closure word with 'pending verification.'"
#
# This hook is the harness-level form of that requirement. It runs on Stop,
# scans the assistant's most recent transcript turn for closure words, and
# refuses the Stop (returning exit 2 with stderr feedback Claude sees) if
# no verification command appeared in the same turn.
#
# This is distinct from existing verify-before-commit.sh and
# verify-before-done.sh, both of which fire on `git commit` time only.
# closure-word-verify-gate.sh fires on *any* assistant turn that asserts
# completion, regardless of whether a commit is being made.
#
# Related Issues:
#   #60506 (@zean89,   2026-05-19) — first-person self-report of the failure
#   #60226 (@suwayama, 2026-05-18) — recognition-without-arrest framework
#   #37818                          — Claude declares fixes done without
#                                     verification
#
# TRIGGER: Stop
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_CLOSURE_WORDS          default built-in — pipe-separated regex of
#                                                  closure phrases
#   CC_VERIFICATION_COMMANDS  default built-in — regex of verification tools
#                                                  (test runners, browsers)
#   CC_CLOSURE_GATE_DISABLE   set to "1" to disable the gate entirely
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "Stop": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/closure-word-verify-gate.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_CLOSURE_GATE_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

DEFAULT_CLOSURES='\b(done|shipped|complete|completed|production[[:space:]]+ready|ready[[:space:]]+to[[:space:]]+merge|ready[[:space:]]+to[[:space:]]+ship|bitti|finished|all[[:space:]]+set|works[[:space:]]+now|fixed[[:space:]]+it)\b'
DEFAULT_VERIFICATION='(npm[[:space:]]+(run[[:space:]]+)?test|pytest|playwright|cypress|jest[[:space:]]|vitest|bun[[:space:]]+test|cargo[[:space:]]+test|go[[:space:]]+test|mocha|phpunit|rspec|curl[[:space:]].*localhost|gh[[:space:]]+pr[[:space:]]+checks|deno[[:space:]]+test|tox|make[[:space:]]+test)'

CLOSURES="${CC_CLOSURE_WORDS:-$DEFAULT_CLOSURES}"
VERIFICATION="${CC_VERIFICATION_COMMANDS:-$DEFAULT_VERIFICATION}"

# Stop-hook input shape varies across Claude Code versions; try several keys.
# The fields we care about are the assistant's most recent message text and
# the list of Bash commands that ran in the same turn.
ASSISTANT_TEXT=$(printf '%s' "$INPUT" | jq -r '
    .transcript[-1].content //
    .last_assistant_message //
    .stop_input.assistant_text //
    .assistant_message //
    empty
' 2>/dev/null)

# Commands that ran in this turn (multiple possible keys depending on
# harness version)
TURN_COMMANDS=$(printf '%s' "$INPUT" | jq -r '
    [ .turn_tool_calls[]?.command,
      .recent_commands[]?,
      .transcript[-1].tool_calls[]?.input.command,
      .last_turn_commands[]?
    ] | map(select(. != null)) | .[]
' 2>/dev/null || true)

# If we cannot find the assistant text, the harness shape differs and we
# refuse to false-positive — exit silently.
[ -z "$ASSISTANT_TEXT" ] && exit 0

# No closure word in the turn → nothing to gate.
if ! printf '%s' "$ASSISTANT_TEXT" | grep -Eiq "$CLOSURES"; then
    exit 0
fi

# Closure word present. Did a verification command run in the same turn?
if [ -n "$TURN_COMMANDS" ] && printf '%s' "$TURN_COMMANDS" | grep -Eiq "$VERIFICATION"; then
    # Verification artifact present — closure is grounded.
    exit 0
fi

# Closure word without verification → block the Stop and surface feedback.
MATCHED_WORD=$(printf '%s' "$ASSISTANT_TEXT" | grep -Eio "$CLOSURES" | head -1)

cat >&2 <<EOF
<system-reminder>
CLOSURE WITHOUT VERIFICATION — the word "$MATCHED_WORD" was used in this turn
but no verification command (test runner, Playwright, curl-against-local,
gh pr checks) ran in the same turn.

This is the failure mode documented in #60506 and #37818: closure words are
emitted before the actual state has been verified. The cost of an unverified
"$MATCHED_WORD" lands on the operator, not on the model.

Before ending this turn, either:

  1. Run a verification command (npm test, pytest, playwright, curl, etc.)
     that exercises the claim being made, and re-state closure only after
     that verification passes, OR
  2. Replace "$MATCHED_WORD" with "pending verification — needs <specific
     verification step>" so the operator knows the claim is not yet grounded.

To disable this gate intentionally (for non-code turns, retrospectives,
documentation work), set CC_CLOSURE_GATE_DISABLE=1 in your environment.
</system-reminder>
EOF

exit 2
