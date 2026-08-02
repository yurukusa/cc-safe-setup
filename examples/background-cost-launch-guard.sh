#!/bin/bash
# background-cost-launch-guard.sh — Block a *background* Bash launch that can
#                                   incur ongoing API/compute cost and would
#                                   keep running after the model says "Done".
#
# Solves (#68642): Claude Code launched a batch API script with
# run_in_background=true, announced completion ("Done."), and the user walked
# away — but three processes kept hammering the API for 6+ hours, racking up
# several hundred USD. The model signaled completion WITHOUT confirming the
# background processes had exited. A foreground run would have blocked (and been
# visible); a background run is fire-and-forget and silent.
#
# Why existing guards miss this exact shape:
#   - timeout-guard.sh nudges you TO use run_in_background for forever-servers —
#     the opposite direction; it never inspects the cost of a bg launch.
#   - dangling-process-guard.sh is a Stop hook that lists leftover `&`/`nohup`
#     processes; it does not read the Bash tool's `run_in_background` parameter
#     and only fires at session end, after the money is already spent.
#   - api-busyloop-guard.sh fires on no-op-body busy-poll loops; a batch API
#     script is not a busy-poll, so it never trips.
#
# What this does: on PreToolUse for Bash, if run_in_background is true AND the
# command matches a cost-incurring signature (LLM API endpoints/SDKs, `claude -p`
# headless runs, or a loop that calls curl/python against an API), it BLOCKS
# (exit 2) and tells the model to (a) run it in the FOREGROUND so completion is
# actually observed, or (b) add an explicit budget/turn cap and a hard timeout.
# Background launches with no cost signature (dev servers, log tails) pass.
#
# TRIGGER: PreToolUse   MATCHER: "Bash"
# settings.json:
# { "hooks": { "PreToolUse": [{ "matcher": "Bash",
#   "hooks": [{ "type": "command",
#     "command": "~/.claude/hooks/background-cost-launch-guard.sh" }] }] } }

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-background-cost-launch-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [background-cost-launch-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)

# Only act on background launches. Claude Code exposes run_in_background as a
# top-level field of the Bash tool input.
BG=$(printf '%s' "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)
[[ "$BG" != "true" ]] && exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

# Cost-incurring signatures. Kept deliberately specific so ordinary background
# work (servers, builds, log tails) is never blocked.
COST_RE='api\.anthropic\.com|api\.openai\.com|generativelanguage\.googleapis\.com|/v1/(messages|complete|chat/completions|batches)|anthropic|openai|litellm|(^|[^a-z])claude[[:space:]]+-p([[:space:]]|$)|--print|messages\.batches|batch'
LOOP_RE='(while|until|for)[[:space:]].*(curl|wget|python|node|claude|gh[[:space:]]+api)'

if printf '%s' "$CMD" | grep -qiE "$COST_RE" || printf '%s' "$CMD" | grep -qiE "$LOOP_RE"; then
    {
        echo "BLOCKED: background launch that can incur ongoing API/compute cost."
        echo ""
        echo "This Bash call sets run_in_background=true on a command that looks"
        echo "like it spends money or loops over an API. A background launch is"
        echo "fire-and-forget: the session can report \"Done\" while it keeps"
        echo "running for hours (see anthropics/claude-code#68642 — several"
        echo "hundred USD burned this exact way)."
        echo ""
        echo "Do one of:"
        echo "  1) Run it in the FOREGROUND (run_in_background=false) so its exit"
        echo "     is actually observed before any completion is claimed; or"
        echo "  2) Bound it: add a hard timeout and an explicit budget/turn cap"
        echo "     (e.g. 'timeout 600 ...', a max-iteration counter), then verify"
        echo "     the process has exited before moving on."
    } >&2
    exit 2
fi

exit 0
