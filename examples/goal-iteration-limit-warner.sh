#!/bin/bash
# goal-iteration-limit-warner.sh — Warn before /goal command without iteration termination
#
# Solves: github.com/anthropics/claude-code/issues/58550
#         "/goal evaluator has no circuit breaker — unsatisfiable conditions burn unlimited tokens"
#
#         Reporter (2026-05-13): a `/goal` set with no termination clause kept
#         firing the same "condition not satisfied" check for 200+ iterations
#         over 5 hours, consuming approximately 50% of the user's weekly token
#         budget. The assistant cannot programmatically clear a goal; only the
#         user can with `/goal clear`. If the user steps away after setting the
#         goal, the budget burns silently.
#
# WHY THIS MATTERS:
#   This is a textbook irreversible-operation pattern: the goal-evaluator's
#   per-turn token spend is non-refundable once consumed, and the only stop
#   condition is the user manually noticing and running `/goal clear`. For
#   developers running Claude Code autonomously or stepping away mid-session,
#   this is a high-impact silent failure.
#
# TRIGGER: UserPromptSubmit  MATCHER: ""
#
# HOW IT WORKS:
#   When the user submits a prompt:
#     1. Check whether the prompt is a `/goal` command.
#        Skip `/goal clear`, `/goal status`, `/goal evaluate-once`, etc.
#        (anything that isn't setting a new goal).
#     2. For a goal-setting command, check whether the goal text already
#        contains a termination clause ("stop after", "or stop", "max", a
#        turn-count like "20 turns", "within N iterations", etc.).
#     3. If no termination clause is present, emit a warning explaining the
#        known iteration-limit bug and recommend adding a clause such as
#        "or stop after 20 turns". Do not block — let the user proceed with
#        eyes open.
#
# CONFIGURATION:
#   CC_GOAL_WARN_DISABLE=1       — disable the hook entirely
#   CC_GOAL_WARN_ACTION          — "warn" (default) or "block" (exit 2)
#   CC_GOAL_WARN_LOG             — log file path (default /tmp/cc-goal-warn.log)
#   CC_GOAL_WARN_MAX_TURNS       — suggested max turn count (default 20)
#
# Usage:
# {
#   "hooks": {
#     "UserPromptSubmit": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/goal-iteration-limit-warner.sh" }]
#     }]
#   }
# }

if [ "${CC_GOAL_WARN_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-goal-iteration-limit-warner-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [goal-iteration-limit-warner]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)

# Pull user prompt (UserPromptSubmit puts it in tool_input.prompt or .prompt)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // .tool_input.prompt // empty' 2>/dev/null)
if [ -z "$PROMPT" ]; then
  exit 0
fi

# Quick scan: only act on /goal commands
case "$PROMPT" in
  "/goal "*|"/goal"|*$'\n'"/goal "*)
    ;;
  *)
    exit 0
    ;;
esac

ACTION="${CC_GOAL_WARN_ACTION:-warn}"
LOG_FILE="${CC_GOAL_WARN_LOG:-/tmp/cc-goal-warn.log}"
MAX_TURNS="${CC_GOAL_WARN_MAX_TURNS:-20}"

# Extract the line that begins with /goal
GOAL_LINE=$(printf '%s' "$PROMPT" | grep -oE '^/goal[[:space:]]+[^\n]+' | head -1)
if [ -z "$GOAL_LINE" ]; then
  # Could be just "/goal" with no args — informational, no action needed
  exit 0
fi

# Skip non-setting subcommands. Anything starting with /goal followed by
# clear/status/evaluate-once/help/list is not setting a new goal.
case "$GOAL_LINE" in
  "/goal clear"*|"/goal status"*|"/goal help"*|"/goal list"*|"/goal evaluate-once"*|"/goal evaluate"*|"/goal show"*)
    exit 0
    ;;
esac

# Check for a termination clause. These are heuristic — false negatives are
# acceptable (we just warn once); false positives let a careful user proceed.
# Patterns:
#   - "stop after"
#   - "or stop"
#   - "max N"
#   - "N turns" / "N iterations" / "N evaluations"
#   - "within N turns"
#   - "after N attempts"
HAS_LIMIT=0
if echo "$GOAL_LINE" | grep -qiE '(stop[[:space:]]+after|or[[:space:]]+stop|max[[:space:]]+[0-9]+|[0-9]+[[:space:]]+(turns|iterations|evaluations|attempts|tries)|within[[:space:]]+[0-9]+[[:space:]]+(turns|iterations)|after[[:space:]]+[0-9]+[[:space:]]+(attempts|tries|turns))'; then
  HAS_LIMIT=1
fi

if [ "$HAS_LIMIT" = "1" ]; then
  # Termination clause present — silent pass.
  exit 0
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
GOAL_TEXT_TRIMMED=$(echo "$GOAL_LINE" | head -c 200)
echo "[$TIMESTAMP] goal_without_limit detected, action=$ACTION goal_excerpt=$GOAL_TEXT_TRIMMED" >> "$LOG_FILE"

MSG="⚠️  /goal without a termination clause detected"
MSG+=$'\n'"     command: $GOAL_TEXT_TRIMMED"
MSG+=$'\n'
MSG+=$'\n'"  Known bug: github.com/anthropics/claude-code/issues/58550"
MSG+=$'\n'"  The /goal evaluator runs after every assistant turn and has no built-in"
MSG+=$'\n'"  iteration limit. One reported incident: 200+ iterations over 5 hours,"
MSG+=$'\n'"  burning approximately 50% of the user's weekly token quota before the"
MSG+=$'\n'"  user noticed and ran /goal clear. The assistant cannot clear or modify"
MSG+=$'\n'"  a goal programmatically; only the user can."
MSG+=$'\n'
MSG+=$'\n'"  Recommendation: add an explicit termination clause. Examples:"
MSG+=$'\n'"    /goal <condition> or stop after $MAX_TURNS turns"
MSG+=$'\n'"    /goal <condition>, max $MAX_TURNS iterations"
MSG+=$'\n'"    /goal <condition> within $MAX_TURNS turns"
MSG+=$'\n'
MSG+=$'\n'"  Reportedly, the 'or stop after N turns' clause is honored by the"
MSG+=$'\n'"  evaluator already (issue #58550 workaround #4). If you proceed without"
MSG+=$'\n'"  a clause, set a phone alarm for ~30 minutes and confirm /goal clear"
MSG+=$'\n'"  if the condition turns out to be unreachable."

if [ "$ACTION" = "block" ]; then
  printf '%s\n' "$MSG" >&2
  exit 2
else
  printf '%s\n' "$MSG" >&2
  exit 0
fi
