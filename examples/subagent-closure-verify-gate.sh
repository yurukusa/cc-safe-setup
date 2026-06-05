#!/bin/bash
# subagent-closure-verify-gate.sh — Refuse the Stop event if the assistant
# narrates sub-agent completion ("the sub-agent completed", "all agents
# returned", "I dispatched X sub-agents and they finished") without a
# corresponding Agent-tool call in the same turn.
#
# Companion to closure-word-verify-gate.sh (PR #250 / merged):
#   * closure-word-verify-gate.sh fires on main-agent closure words
#     ("done", "shipped", "complete") without a verification command.
#   * THIS hook fires on sub-agent closure narration without a
#     verification of dispatch — i.e., the parent claims sub-agent
#     activity that may not have actually happened.
#
# Solves the sub-agent half of the four-sub-pattern decomposition at
# https://gist.github.com/yurukusa/9857a9ed407696ba8483b354917ff161 —
# specifically sub-pattern 1 (dispatch fabrication, #61107, #61167) at the
# closure-claim layer rather than the per-tool-call layer.
#
# Why the closure-claim layer matters:
#   * Per-tool-call defenses (e.g. PR #275 route-handler-body-emptiness-gate,
#     PR #281 scope-expansion-receipt) catch specific failure shapes but
#     can't catch the general pattern of "parent narrates work that didn't
#     happen." Closure-claim narration is the place where the fabrication
#     becomes a load-bearing claim the operator will trust downstream.
#   * #61167 explicitly: "Opus 4.7 narrates dispatching 39 agents in
#     parallel, reports the aggregated result, when the actual spawn count
#     was 5 of 39 and the synthesis is a hallucinated summary covering the
#     34 that never ran."
#
# Architecture:
#   Stop event. Read assistant's last turn text. If it matches a closure-
#   narration pattern (the sub-agent (completed|returned|finished|reported)
#   ..., I dispatched N sub-agents, all (sub-)?agents (have )?(completed|
#   returned|finished), etc.) AND no Agent tool was called in this turn,
#   write an advisory to stderr with the matched phrase and recovery
#   guidance.
#
# Default mode is advisory (exit 0 + stderr). Strict mode (exit 2) is
# opt-in via CC_SUBAGENT_CLOSURE_MODE=strict — it refuses the Stop and
# forces the assistant to either verify the dispatch or restate the
# closure as "pending verification."
#
# TRIGGER: Stop
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_SUBAGENT_CLOSURE_MODE      "strict" → exit 2 when narration matches
#                                 and no Agent call in the turn.
#                                 Default: advisory (exit 0).
#   CC_SUBAGENT_CLOSURE_DISABLE   "1" → skip the gate entirely.
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "Stop": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/subagent-closure-verify-gate.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

[ "${CC_SUBAGENT_CLOSURE_DISABLE:-0}" = "1" ] && exit 0
[ -z "$INPUT" ] && exit 0

# Pull assistant's last turn text (multiple harness shapes accepted).
ASSISTANT_TEXT=$(printf '%s' "$INPUT" | jq -r '
    .transcript[-1].content //
    .last_assistant_message //
    .stop_input.assistant_text //
    .assistant_message //
    empty
' 2>/dev/null)

[ -z "$ASSISTANT_TEXT" ] && exit 0

# Closure-narration patterns. Each captures a phrase that asserts sub-agent
# activity completion. We intentionally over-match a little; false-positive
# cost is a stderr advisory, false-negative cost is the operator trusting a
# fabricated dispatch summary.
#
# Patterns covered:
#   * the sub-agent (completed|returned|finished|reported) ...
#   * the (X|<numeric>) sub-agents (have )?(completed|returned|finished)
#   * (both|all|each) (of the )?sub-?agents (have )?(completed|returned)
#   * I (dispatched|spawned|fanned out) [N] (sub-)?agents (and|that) ...
#   * all [N] (sub-)?agents (returned|completed|reported back)
CLOSURE_PATTERN='(\bthe[[:space:]]+sub-?agent[[:space:]]+(completed|returned|finished|reported|came[[:space:]]+back|delivered)\b|\b(both|all|each)[[:space:]]+(of[[:space:]]+the[[:space:]]+)?sub-?agents[[:space:]]+(have[[:space:]]+)?(completed|returned|finished|reported)\b|\bI[[:space:]]+(dispatched|spawned|fanned[[:space:]]+out|invoked)[[:space:]]+[0-9A-Za-z]+[[:space:]]+sub-?agents?\b|\ball[[:space:]]+[0-9]+[[:space:]]+sub-?agents?[[:space:]]+(returned|completed|reported)\b|\bsub-?agents?[[:space:]]+(returned|completed|reported)[[:space:]]+back\b|\bthe[[:space:]]+(parallel|fan-?out|delegated)[[:space:]]+(work|investigation|analysis)[[:space:]]+(is|has[[:space:]]+been)[[:space:]]+(complete|done|finished)\b)'

MATCHED_PHRASE=$(printf '%s' "$ASSISTANT_TEXT" | grep -Eio "$CLOSURE_PATTERN" | head -1)

if [ -z "$MATCHED_PHRASE" ]; then
    exit 0
fi

# Did any Agent tool call happen in this turn? Try several harness shapes.
AGENT_CALLS=$(printf '%s' "$INPUT" | jq -r '
    [
      .transcript[-1].tool_calls[]?.name,
      .turn_tool_calls[]?.name,
      .last_turn_tool_calls[]?.name,
      .recent_tool_calls[]?.name
    ] | map(select(. != null)) | .[]
' 2>/dev/null | grep -ix "Agent" | head -1)

if [ -n "$AGENT_CALLS" ]; then
    # Narration was grounded in actual Agent invocations — pass.
    exit 0
fi

# Narration without Agent calls. Emit advisory.
{
    echo "<system-reminder>"
    echo "SUB-AGENT CLOSURE WITHOUT DISPATCH EVIDENCE — the assistant's last"
    echo "turn narrated sub-agent activity completion:"
    echo ""
    echo "    \"$MATCHED_PHRASE\""
    echo ""
    echo "but no Agent tool was called in the same turn. This is the failure"
    echo "shape documented in anthropics/claude-code#61167 (Opus 4.7 narrating"
    echo "39 sub-agent dispatches, actual spawn count 5/39) and #61107 (route"
    echo "handlers that look right but do nothing): the model's narration of"
    echo "sub-agent activity becomes evidence the activity happened, when in"
    echo "fact no dispatch occurred."
    echo ""
    echo "Before ending this turn, either:"
    echo ""
    echo "  1. Invoke the Agent tool now to ground the narration in actual"
    echo "     dispatches (the recommended path), OR"
    echo "  2. Restate the closure as \"pending — sub-agent dispatch not yet"
    echo "     performed\" so the operator knows the work is not yet started."
    echo ""
    echo "This is the sub-agent dual of #60506's main-agent closure-word"
    echo "verification gate (cc-safe-setup PR #250). Together they cover both"
    echo "tiers of the claim-verify gap."
    echo ""
    echo "To disable this gate intentionally (for non-dispatch retrospectives,"
    echo "documentation, or planning turns), set CC_SUBAGENT_CLOSURE_DISABLE=1"
    echo "in your environment."
    echo "</system-reminder>"
} >&2

if [ "${CC_SUBAGENT_CLOSURE_MODE:-advisory}" = "strict" ]; then
    exit 2
fi
exit 0
