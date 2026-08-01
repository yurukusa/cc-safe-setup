#!/bin/bash
# nested-background-agent-guard.sh — Refuse background agent spawns from inside a sub-agent
#
# Why: Issue #73829 (2026-07-04, desktop app, 0 comments when filed) is the canonical
#      report. An intermediate background agent spawned *further* background agents
#      instead of doing the sub-topics inline. A grandchild then re-invoked itself with
#      filler no-ops ("checked current time", "Monitor timed out", "no-op while waiting")
#      for 6.5 hours instead of quiescing. Once the intermediate agent's session ended,
#      the top-level session had no handle on its descendants: TaskStop/TaskOutput
#      returned "No task found" while the panel still showed them running. Several
#      hundred USD burned, and restarting the app was the only way to clear it.
#
#      The recursion only compounds because a *sub*-agent is allowed to spawn
#      *background* agents at all. That is the one layer a client-side hook can gate
#      deterministically, so that is what this hook does.
#
# ★2026-08-01: this got worse by default. Claude Code 2.1.219 changed nested subagent
#      spawning from depth 1 to **depth 3 by default**:
#
#        "Subagents can now spawn nested subagents up to depth 3 by default (was 1);
#         set CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 to disable nesting"
#
#      Two consequences for anyone running unattended:
#        - The blast radius of the #73829 shape tripled without anyone changing a setting.
#        - Guards that cap the *number* of concurrent subagents do not see this at all.
#          If each level spawns only a few, the count stays under the threshold while the
#          depth keeps growing. Depth and width are different axes; this hook is the depth one.
#
# Why existing cc-safe-setup hooks miss this exact shape:
#   - nested-spawn-inflight-guard.sh / max-subagent-count.sh / subagent-budget-guard.sh
#     all bound how many subagents are in flight. None of them read whether the *current*
#     run is itself a sub-agent, so none of them can tell depth 1 from depth 3.
#   - background-cost-launch-guard.sh reads the Bash tool's run_in_background parameter.
#     It never sees Agent/Task dispatches.
#
# What this does: on PreToolUse for Agent/Task/SendMessage, if run_in_background is true
# AND the current session is already a sub-agent (CLAUDE_CODE_CHILD_SESSION is set),
# it BLOCKS (exit 2). Foreground agents inside a sub-agent pass. Background agents from
# the top-level session pass. Only the nesting case is refused.
#
# Verified on 2026-07-04 against three inputs, and re-verified 2026-08-01 with the
# regression tests in tests/:
#   (a) run_in_background:true + CLAUDE_CODE_CHILD_SESSION set  -> exit 2 (blocked)
#   (b) run_in_background:true + variable unset (top level)     -> exit 0 (allowed)
#   (c) foreground agent inside a sub-agent                     -> exit 0 (allowed)
#
# ★Limitation, stated plainly: CLAUDE_CODE_CHILD_SESSION is set inside spawned agent
# sessions on the CLI (confirmed while examining transcript inheritance in #73848).
# The desktop app was NOT confirmed to set it identically. Verify on your build first
# with a trivial printenv hook before relying on this.
#
# ★This does not recover already-orphaned tasks. They are app-managed tasks, not OS
# processes you can kill, and the spawning session is gone. The real fixes are
# provider-side: descendants should stay inspectable/stoppable from the root, and an
# agent awaiting children should quiesce rather than emit filler tool calls.
#
# Opt out:   CC_NESTED_BG_AGENT_GUARD_DISABLE=1
#
# TRIGGER: PreToolUse   MATCHER: "Agent|Task|SendMessage"
# settings.json:
# { "hooks": { "PreToolUse": [{ "matcher": "Agent|Task|SendMessage",
#   "hooks": [{ "type": "command",
#     "command": "~/.claude/hooks/nested-background-agent-guard.sh" }] }] } }

set -uo pipefail

[ "${CC_NESTED_BG_AGENT_GUARD_DISABLE:-0}" = "1" ] && exit 0

INPUT="$(cat)"

# jq が無い環境で黙って素通りしないこと。2026-07-27 に、配っていた17本が
# jq 不在で沈黙して素通りしていた(遮断すべき14通りが3環境すべてで0/14)。
# 「検査する対象が無かった」と「検査する道具が無かった」を混同しないため、
# ここでは通すが必ず声を出す。どれも無い環境で遮断を選ぶと全ツール呼び出しが
# 止まって Claude Code が使えなくなるので、fail-open + 警告にする。
if ! command -v jq >/dev/null 2>&1; then
    echo "nested-background-agent-guard: jq not found — cannot inspect this dispatch, passing through unchecked." >&2
    exit 0
fi

TOOL="$(printf '%s\n' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
case "$TOOL" in
    Agent|Task|SendMessage) ;;
    *) exit 0 ;;
esac

BG="$(printf '%s\n' "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)"
[ "$BG" = "true" ] || exit 0

# 親(top-level)からの背景の生成は通す。止めたいのは入れ子の側だけ。
[ -n "${CLAUDE_CODE_CHILD_SESSION:-}" ] || exit 0

cat >&2 <<'MSG'
Blocked: a sub-agent tried to spawn a background agent.

Issue #73829: nested background agents orphan and loop. Once the intermediate
agent's session ends, TaskStop/TaskOutput return "No task found" while the tasks
keep running and burning tokens — 6.5 hours and several hundred USD in the
original report.

Since Claude Code 2.1.219 the default nesting depth is 3 (was 1), so this shape
now has three levels to compound through instead of one.

Do one of these instead:
  - Do the sub-topics inline in this sub-agent (no further dispatch).
  - Spawn background agents only from the top-level session, where TaskStop works.
  - If you genuinely need nesting, cap it first: CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1
MSG
exit 2
