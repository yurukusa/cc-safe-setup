#!/bin/bash
# workspace-lease-guard.sh — Out-of-process workspace ownership lease, with
# compare-and-delete release and heartbeat takeover for crashed siblings.
#
# Solves: #60475 — "Subagent ran `git checkout` and clobbered another active
# session's uncommitted edits in the same working tree." The destructive
# action succeeded because no in-process register state could enumerate
# "is there a sibling agent in this tree?" — and in-process state is exactly
# what was lost across the auto-compact boundary that produced the failure.
#
# In the words of @kcarriedo's pattern 4 in that Issue thread:
#
#   "Workspace ownership needs to be an out-of-process invariant. Once
#    'this directory is being mutated by agent X' lives only in agent X's
#    session, agent Y has no way to discover that and the orchestrator has
#    no way to enforce it. A simple file-based lease ... with compare-and-
#    delete release semantics would have caught this at the moment of the
#    destructive checkout."
#
# This hook implements that lease. The lease file lives at
# ${CC_LEASE_DIR}/workspace-${REPO_HASH}.lease and encodes:
#   <agent_id>|<acquired_ts>|<heartbeat_ts>
#
# Lifecycle:
#   * SessionStart — attempt to acquire. If unheld or stale, claim.
#                    If held by another live agent, BLOCK the session start.
#   * PreToolUse   — refresh heartbeat on every tool call. If the lease was
#                    taken over by a different agent_id (we crashed and got
#                    replaced), BLOCK the tool call so the user is warned
#                    rather than silently competing.
#   * Stop         — compare-and-delete release. Only the lease holder removes
#                    the lease file; an out-of-band cleanup that finds a
#                    different agent_id leaves it alone.
#
# The matcher must be "*" so the hook fires on every tool call (to refresh
# the heartbeat and detect cross-agent contention at the earliest moment).
#
# CONFIG:
#   CC_LEASE_DIR=$HOME/.claude/locks   directory for lease files
#   CC_LEASE_HEARTBEAT_TTL=180         seconds before an idle lease is stale
#   CC_LEASE_DISABLE=1                 set to disable the hook entirely
#
# This is distinct from concurrent-edit-lock.sh (per-file lock on Edit/Write,
# 60-second expiry) and max-concurrent-agents.sh (caps subagent fan-out).
# workspace-lease-guard.sh is repo-scoped, covers Bash (not just Edit/Write),
# and survives auto-compact because the lease lives on the filesystem.
#
# Related Issues:
#   #60475 (@anonymous,  2026-05-19) — subagent git checkout clobbered sibling
#   #60506 (@zean89,     2026-05-19) — six-day drift inside maximal in-process enforcement
#   #60226 (@suwayama,   2026-05-18) — recognition-without-arrest framework
#   #57463                            — subagent destructive-recovery family
#
# TRIGGER: PreToolUse, SessionStart, Stop
# MATCHER: "*"

set -u

[ "${CC_LEASE_DISABLE:-0}" = "1" ] && exit 0

LEASE_DIR="${CC_LEASE_DIR:-$HOME/.claude/locks}"
HEARTBEAT_TTL="${CC_LEASE_HEARTBEAT_TTL:-180}"
NOW=$(date +%s)

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Identify the workspace: prefer the git toplevel, fall back to CLAUDE_PROJECT_DIR
# or PWD. Anything outside a recognisable workspace is ignored.
WORKSPACE=$(git -C "${CLAUDE_PROJECT_DIR:-${PWD:-.}}" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$WORKSPACE" ]; then
    WORKSPACE="${CLAUDE_PROJECT_DIR:-${PWD:-}}"
fi
[ -z "$WORKSPACE" ] && exit 0

# Identify the agent: prefer the session id, fall back to PPID. Parent PID is
# stable across one Claude Code session and distinct between sibling sessions.
AGENT_ID="${CLAUDE_SESSION_ID:-pid-${PPID:-$$}}"

REPO_HASH=$(printf '%s' "$WORKSPACE" | sha256sum | cut -c1-16)
mkdir -p "$LEASE_DIR" 2>/dev/null || true
LEASE_FILE="${LEASE_DIR}/workspace-${REPO_HASH}.lease"

# Read current lease, if any
read_lease() {
    [ -f "$LEASE_FILE" ] || { echo ""; return; }
    cat "$LEASE_FILE" 2>/dev/null
}

write_lease() {
    # acquired_ts | heartbeat_ts
    local acquired="${1:-$NOW}"
    printf '%s|%s|%s\n' "$AGENT_ID" "$acquired" "$NOW" > "$LEASE_FILE"
}

LEASE_CONTENT=$(read_lease)

if [ -n "$LEASE_CONTENT" ]; then
    LEASE_AGENT=$(printf '%s' "$LEASE_CONTENT" | cut -d'|' -f1)
    LEASE_ACQUIRED=$(printf '%s' "$LEASE_CONTENT" | cut -d'|' -f2)
    LEASE_HEARTBEAT=$(printf '%s' "$LEASE_CONTENT" | cut -d'|' -f3)
    LEASE_AGE=$((NOW - ${LEASE_HEARTBEAT:-0}))
else
    LEASE_AGENT=""
    LEASE_ACQUIRED=""
    LEASE_HEARTBEAT=""
    LEASE_AGE=0
fi

case "$EVENT" in
    SessionStart)
        if [ -z "$LEASE_CONTENT" ] || [ "$LEASE_AGENT" = "$AGENT_ID" ]; then
            write_lease "${LEASE_ACQUIRED:-$NOW}"
            exit 0
        fi
        if [ "$LEASE_AGE" -gt "$HEARTBEAT_TTL" ]; then
            # Previous holder went stale (likely crashed) — take over with notice
            write_lease "$NOW"
            cat >&2 <<EOF
NOTICE: workspace-lease-guard took over a stale lease for ${WORKSPACE}.
  Previous agent: ${LEASE_AGENT} (idle ${LEASE_AGE}s, TTL ${HEARTBEAT_TTL}s)
  New agent:      ${AGENT_ID}
  If the previous session is still active, both sessions are now competing
  for the same working tree. Stop one before continuing.
EOF
            exit 0
        fi
        cat >&2 <<EOF
BLOCKED: workspace ${WORKSPACE} is held by another Claude session.
  Held by: ${LEASE_AGENT} (last heartbeat ${LEASE_AGE}s ago)
  This session: ${AGENT_ID}

  A sibling agent is actively mutating this working tree. Concurrent
  sessions in the same repo can silently clobber each other's uncommitted
  edits (see Issue #60475). Either:
    1. Switch to a different worktree:  git worktree add ../sibling-path
    2. Stop the other session, then retry
    3. If the other session is dead, wait ${HEARTBEAT_TTL}s for the lease
       to expire, or manually remove: ${LEASE_FILE}
EOF
        exit 2
        ;;

    PreToolUse)
        # Heartbeat refresh + cross-agent takeover detection
        if [ -z "$LEASE_CONTENT" ]; then
            # No lease — first tool call after SessionStart hook misfire, or
            # SessionStart was not registered. Claim it implicitly.
            write_lease "$NOW"
            exit 0
        fi
        if [ "$LEASE_AGENT" = "$AGENT_ID" ]; then
            # We hold the lease — refresh heartbeat
            write_lease "$LEASE_ACQUIRED"
            exit 0
        fi
        if [ "$LEASE_AGE" -gt "$HEARTBEAT_TTL" ]; then
            # Other holder went stale — take over with notice
            write_lease "$NOW"
            cat >&2 <<EOF
NOTICE: workspace-lease-guard took over a stale lease mid-session.
  Previous agent: ${LEASE_AGENT} (idle ${LEASE_AGE}s)
  This session:   ${AGENT_ID}
EOF
            exit 0
        fi
        cat >&2 <<EOF
BLOCKED: workspace-lease-guard detected a sibling agent.
  Workspace: ${WORKSPACE}
  Held by:   ${LEASE_AGENT} (last heartbeat ${LEASE_AGE}s ago)
  This:      ${AGENT_ID}, attempting ${TOOL:-tool call}

  This is the failure shape of Issue #60475. A second Claude session
  is mutating this working tree concurrently. Refusing the tool call
  to prevent silent clobbering of the sibling's uncommitted edits.
  Switch to a separate worktree before continuing.
EOF
        exit 2
        ;;

    Stop)
        # Compare-and-delete release: only the holder removes the lease
        if [ -n "$LEASE_CONTENT" ] && [ "$LEASE_AGENT" = "$AGENT_ID" ]; then
            rm -f "$LEASE_FILE"
        fi
        exit 0
        ;;

    *)
        exit 0
        ;;
esac
