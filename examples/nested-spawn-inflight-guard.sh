#!/bin/bash
# nested-spawn-inflight-guard.sh — Refuse Task/SendMessage dispatch when too many subagents are already in flight
#
# Why: Issue #62193 (fdpr-H, 2026-05-25 — 3,079 bash subprocesses spawned in 17s,
#      hard reboot required) and the 2026-05-29 follow-up from @allenfu000 (Windows,
#      v2.1.156, Opus 4.8 ultracode workflow — subagents spawning nested PowerShell
#      until OOM, taking down two other Claude Code windows alongside) are the two
#      canonical reproductions of Cluster 1's nested-spawn sub-pattern: uncapped
#      fan-out at the orchestration layer rather than inside a single tool call.
#
#      Two existing cc-safe-setup hooks address the same architectural surface
#      with different approaches:
#
#        - max-concurrent-agents.sh uses a /tmp counter file that increments on
#          dispatch but never decrements — relies on file-age expiry (10 min) to
#          reset. Over-counts on the rebound path (counter persists after agents
#          complete), under-counts on burst recovery (file mtime resets the
#          window for unrelated samples).
#
#        - subagent-budget-guard.sh uses a per-line timestamp tracker in
#          ~/.claude/active-agents with a 30-minute "active" window. Same
#          time-window approximation; same dual error mode.
#
#      Both also match only the legacy tool_name "Agent", missing the modern
#      "Task" and "SendMessage" dispatcher entry points.
#
#      This hook reads the actual transcript at dispatch time, counts in-flight
#      subagents (tool_use entries with no matching tool_result), and refuses
#      the new dispatch when the count exceeds the configured budget. Because
#      the count comes from the transcript itself, there is no stale-state
#      window and no counter to leak.
#
# Event: PreToolUse  MATCHER: "Task|Agent|SendMessage"
# Action: Scan the transcript for tool_use entries whose name matches the
#         dispatcher family (Task / Agent / SendMessage). Subtract those that
#         already have a tool_result with the same tool_use_id. If the
#         remaining count (in-flight) >= CC_NESTED_SPAWN_BUDGET, exit 2 with
#         a stderr advisory naming the budget, the counted in-flight ids,
#         and the override path. Otherwise exit 0.
#
# Configuration (all optional):
#   CC_NESTED_SPAWN_BUDGET     Max concurrent in-flight subagents (default: 5)
#   CC_NESTED_SPAWN_DISABLE    Set to "1" to bypass entirely (escape hatch)
#   CC_NESTED_SPAWN_LOOKBACK   Number of trailing transcript lines to scan
#                              (default: 2000; raise for very long sessions)
#
# Override one specific dispatch (clear after the call to re-arm):
#   CC_NESTED_SPAWN_OVERRIDE=1 claude ...
#
# Reading the in-flight set (manual inspection):
#   jq -c 'select(.message.content[]?.type=="tool_use" and
#                 (.message.content[].name|test("Task|Agent|SendMessage")))' \
#     ~/.claude/projects/*/SESSION.jsonl

set -u

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-nested-spawn-inflight-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [nested-spawn-inflight-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

BUDGET="${CC_NESTED_SPAWN_BUDGET:-5}"
LOOKBACK="${CC_NESTED_SPAWN_LOOKBACK:-2000}"
DISABLE="${CC_NESTED_SPAWN_DISABLE:-0}"
OVERRIDE="${CC_NESTED_SPAWN_OVERRIDE:-0}"

# Escape hatches: disable entirely, or override one specific call.
if [ "$DISABLE" = "1" ] || [ "$OVERRIDE" = "1" ]; then
  exit 0
fi

INPUT=$(cat)

# Only act when the tool being dispatched is itself a subagent dispatcher.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in
  Task|Agent|SendMessage) ;;
  *) exit 0 ;;
esac

# Locate the transcript. Without it we can't measure in-flight state — fail open.
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ]; then
  exit 0
fi

# Sanity-check the budget; nonsense values fail open.
case "$BUDGET" in
  ''|*[!0-9]*) exit 0 ;;
esac
case "$LOOKBACK" in
  ''|*[!0-9]*) LOOKBACK=2000 ;;
esac

# Collect dispatched ids (tool_use entries with name in the dispatcher family)
# and resolved ids (tool_result entries) from the trailing window of the
# transcript. The set difference is the in-flight set.
#
# Two transcript shapes are common:
#   - {"message": {"content": [...]}}              (assistant turns + user turns)
#   - {"type":"tool_use","id":"...","name":"..."}  (some hook payload echoes)
#
# We accept both. jq extracts the union by trying each path.
ANALYSIS=$(tail -n "$LOOKBACK" "$TRANSCRIPT" 2>/dev/null | \
  jq -rs '
    def extract_tool_use:
      (.message.content // [.])[] |
      select(type == "object" and .type == "tool_use") |
      select(.name | test("^(Task|Agent|SendMessage)$"; "")) |
      .id // empty;
    def extract_tool_result:
      (.message.content // [.])[] |
      select(type == "object" and .type == "tool_result") |
      .tool_use_id // empty;

    . as $rows |
    ($rows | map(extract_tool_use) | flatten | map(select(. != ""))) as $dispatched |
    ($rows | map(extract_tool_result) | flatten | map(select(. != ""))) as $resolved |
    ($dispatched - $resolved) as $inflight |
    {
      inflight_count: ($inflight | length),
      inflight_ids: $inflight
    } |
    @json
  ' 2>/dev/null)

# If the jq pipeline failed, fail open — never block on hook bugs.
if [ -z "$ANALYSIS" ]; then
  exit 0
fi

INFLIGHT_COUNT=$(printf '%s' "$ANALYSIS" | jq -r '.inflight_count // 0' 2>/dev/null)
case "$INFLIGHT_COUNT" in
  ''|*[!0-9]*) exit 0 ;;
esac

# If at or above the budget, the new dispatch would push us into runaway territory.
# Refuse with a stderr advisory.
if [ "$INFLIGHT_COUNT" -ge "$BUDGET" ]; then
  IDS=$(printf '%s' "$ANALYSIS" | jq -r '.inflight_ids | join(", ")' 2>/dev/null)
  cat >&2 <<EOF
BLOCKED: ${INFLIGHT_COUNT} subagent(s) already in flight (budget: ${BUDGET}).
  In-flight ids: ${IDS}
  This dispatch would push the count to $((INFLIGHT_COUNT + 1)). Wait for one
  or more to complete (tool_result) before dispatching another, or raise the
  budget via CC_NESTED_SPAWN_BUDGET=N for legitimate fan-out workloads.

  To allow this specific call without changing the budget:
    CC_NESTED_SPAWN_OVERRIDE=1 (clears after the next dispatch)
  To disable the guard entirely:
    CC_NESTED_SPAWN_DISABLE=1

  Root cause, if you never wanted nesting: subagents spawning subagents is
  opt-out at the source.
    CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1
  Set it explicitly rather than relying on the default. Verified in 2.1.220 by
  reading the shipped binary: the depth default is fetched from a remote config
  and only falls back to the built-in 3 when that fetch yields nothing, so the
  changelog's "default is 3" is a fallback, not a guarantee. The two sibling
  caps are plain constants by contrast (concurrent 20, per-session 200).

  Why this guard exists: Issue #62193 (3,079 bash subprocesses in 17s, hard
  reboot) and the 2026-05-29 Windows follow-up (ultracode subagents spawning
  PowerShell until two other Claude Code windows crashed). Cluster 1
  (Sub-Agent Observability) nested-spawn sub-pattern.
  See: https://github.com/yurukusa/cc-safe-setup/blob/main/docs/cluster-tracker.html#cluster-soh
EOF
  exit 2
fi

exit 0
