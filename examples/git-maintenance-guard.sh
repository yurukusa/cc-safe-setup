#!/bin/bash
# ================================================================
# git-maintenance-guard.sh — Block automatic git maintenance
# ================================================================
# PURPOSE:
#   Claude Code, Codex, and parallel subagents sometimes run
#   git gc / git repack / git maintenance / git prune on their own.
#   When these run concurrently in the same repo, lock contention
#   leaves stale .git/objects/pack/tmp_pack_* files behind. Past
#   incident: 1,350 tmp_pack_* / 144 GiB filled the WSL ext4.vhdx.
#
#   This hook blocks those maintenance commands at PreToolUse. The
#   user can still run them manually by setting CC_GIT_MAINTENANCE_ALLOW=1
#   for that single command.
#
# Detects:
#   git gc                      (any args)
#   git repack                  (any args)
#   git maintenance run         (any args, including 'start' / 'stop')
#   git prune                   (any args)
#   git gc --auto               (also blocked: still triggers repack)
#
# Does NOT block:
#   git gc --prune=now          (still blocked — prune is the risky part)
#   read-only inspection: git count-objects, git fsck, git verify-pack
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIG:
#   CC_GIT_MAINTENANCE_ALLOW=1   one-shot override
#   CC_GIT_MAINTENANCE_DISABLE=1 disable this hook entirely
# ================================================================

[ "${CC_GIT_MAINTENANCE_DISABLE:-0}" = "1" ] && exit 0
[ "${CC_GIT_MAINTENANCE_ALLOW:-0}" = "1" ] && exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# git gc (any args)
if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9._-])git[[:space:]]+gc([[:space:]]|$)'; then
    echo "BLOCKED: git gc can leave stale tmp_pack_* under parallel access." >&2
    echo "  Past incident: 1,350 tmp_pack_* / 144 GiB filled the WSL ext4.vhdx." >&2
    echo "  Override (one shot): CC_GIT_MAINTENANCE_ALLOW=1 git gc ..." >&2
    exit 2
fi

# git repack (any args)
if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9._-])git[[:space:]]+repack([[:space:]]|$)'; then
    echo "BLOCKED: git repack can leave stale tmp_pack_* under parallel access." >&2
    echo "  Override (one shot): CC_GIT_MAINTENANCE_ALLOW=1 git repack ..." >&2
    exit 2
fi

# git maintenance (run / start / stop / register / unregister)
if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9._-])git[[:space:]]+maintenance([[:space:]]|$)'; then
    echo "BLOCKED: git maintenance schedules background gc/repack — same risk." >&2
    echo "  Override (one shot): CC_GIT_MAINTENANCE_ALLOW=1 git maintenance ..." >&2
    exit 2
fi

# git prune (any args). git prune-packed is also caught here, intentionally.
if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9._-])git[[:space:]]+prune([[:space:]-]|$)'; then
    echo "BLOCKED: git prune removes unreachable objects. Skip unless investigating manually." >&2
    echo "  Override (one shot): CC_GIT_MAINTENANCE_ALLOW=1 git prune ..." >&2
    exit 2
fi

exit 0
