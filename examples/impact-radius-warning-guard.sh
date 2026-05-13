#!/bin/bash
# impact-radius-warning-guard.sh — Warn when destructive ops have large impact radius
#
# Prevents the structural pattern observed across multiple Tier-1 incidents:
#   - HN 47911524 (jeremyccrane, 2026-04-26): AI agent deleted production database
#     volume containing all of operator's prod data. Agent did not count impact
#     before executing.
#   - Issue #56738 (SQL 24,472 rows): AI agent ran DELETE that hit 24,472 rows
#     out of 24,475 total. Agent did not run SELECT count(*) first.
#   - PocketOS (2026-04, 30-hour recovery): AI agent deleted storage volume
#     containing 9 seconds of operator's work after credential mismatch.
#
# The structural commonality: the operation's impact radius is measurable
# beforehand (file count, row count, commit count), but the agent did not
# measure it. This hook surfaces the impact radius as a warning before the
# operation is allowed to proceed.
#
# This hook does NOT block. It writes a warning to stderr that surfaces
# in the Claude Code session, giving the operator (or the agent itself
# via CLAUDE.md instructions) a chance to inspect the radius before
# the operation completes.
#
# Designed to complement (not replace) destructive-guard and
# code-freeze-respect-guard. Those hooks block specific patterns;
# this hook surfaces information that may not match any specific pattern
# but still represents a large blast radius.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/impact-radius-warning-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Threshold for "large" - configurable via env var
THRESHOLD="${IRWG_THRESHOLD:-100}"

WARN_MESSAGES=()

# Case 1: rm -rf with a path - count files that would be deleted
if echo "$COMMAND" | grep -qiE '(^|[[:space:]])rm[[:space:]]+-[rRfF]+[[:space:]]+'; then
    # Extract target path (best effort - takes the last argument-like token)
    TARGET=$(echo "$COMMAND" | grep -oE 'rm[[:space:]]+-[rRfF]+[[:space:]]+([^[:space:];|&]+)' | tail -1 | awk '{print $NF}')
    if [ -n "$TARGET" ] && [ -e "$TARGET" ]; then
        COUNT=$(find "$TARGET" -type f 2>/dev/null | wc -l)
        if [ "$COUNT" -gt "$THRESHOLD" ]; then
            WARN_MESSAGES+=("rm -rf target '$TARGET' contains $COUNT files (threshold: $THRESHOLD)")
        fi
    fi
fi

# Case 2: git reset --hard with multiple commits
if echo "$COMMAND" | grep -qiE 'git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+HEAD~([0-9]+)'; then
    DEPTH=$(echo "$COMMAND" | grep -oE 'HEAD~[0-9]+' | grep -oE '[0-9]+')
    if [ -n "$DEPTH" ] && [ "$DEPTH" -ge 5 ]; then
        WARN_MESSAGES+=("git reset --hard would discard $DEPTH commits (threshold: 5)")
    fi
fi

# Case 3: git clean -fd in a dir with many untracked files
if echo "$COMMAND" | grep -qiE 'git[[:space:]]+clean[[:space:]]+-[fdxX]+'; then
    if command -v git >/dev/null 2>&1 && [ -d ".git" ]; then
        UNTRACKED=$(git status --porcelain 2>/dev/null | grep -c '^??' || echo 0)
        if [ "$UNTRACKED" -gt 10 ]; then
            WARN_MESSAGES+=("git clean would delete $UNTRACKED untracked files (threshold: 10)")
        fi
    fi
fi

# Case 4: find -delete with broad pattern
if echo "$COMMAND" | grep -qiE 'find[[:space:]]+\S+.*-delete'; then
    # Extract find target (first argument)
    FIND_TARGET=$(echo "$COMMAND" | grep -oE 'find[[:space:]]+\S+' | head -1 | awk '{print $2}')
    if [ -n "$FIND_TARGET" ] && [ -e "$FIND_TARGET" ]; then
        COUNT=$(find "$FIND_TARGET" -type f 2>/dev/null | wc -l)
        if [ "$COUNT" -gt "$THRESHOLD" ]; then
            WARN_MESSAGES+=("find -delete on '$FIND_TARGET' could touch up to $COUNT files (threshold: $THRESHOLD)")
        fi
    fi
fi

# Case 5: SQL DELETE FROM without WHERE clause (unbounded)
if echo "$COMMAND" | grep -qiE 'DELETE[[:space:]]+FROM[[:space:]]+[a-zA-Z_]+[[:space:]]*(;|$)'; then
    WARN_MESSAGES+=("DELETE FROM without WHERE clause - entire table will be erased. Run SELECT count(*) first to see impact radius.")
fi

# Case 6: UPDATE without WHERE clause (unbounded)
if echo "$COMMAND" | grep -qiE 'UPDATE[[:space:]]+[a-zA-Z_]+[[:space:]]+SET[[:space:]]+.*[^E][^R][^E]$'; then
    if ! echo "$COMMAND" | grep -qiE 'WHERE'; then
        WARN_MESSAGES+=("UPDATE without WHERE clause - entire table will be modified. Run SELECT count(*) first.")
    fi
fi

# Case 7: docker volume rm of multiple volumes
if echo "$COMMAND" | grep -qiE 'docker[[:space:]]+volume[[:space:]]+(rm|prune)'; then
    if command -v docker >/dev/null 2>&1; then
        VOL_COUNT=$(docker volume ls -q 2>/dev/null | wc -l)
        if [ "$VOL_COUNT" -gt 5 ]; then
            WARN_MESSAGES+=("docker volume rm would affect up to $VOL_COUNT volumes (threshold: 5)")
        fi
    fi
fi

# Case 8: kubectl delete -A or namespace-wide
if echo "$COMMAND" | grep -qiE 'kubectl[[:space:]]+delete[[:space:]]+.*(-A|--all-namespaces|--all)'; then
    WARN_MESSAGES+=("kubectl delete with --all or -A flag - operation spans multiple namespaces or resources.")
fi

# No warnings - hook does not interfere
[[ "${#WARN_MESSAGES[@]}" -eq 0 ]] && exit 0

# Surface warnings on stderr (advisory only - does not block)
echo "" >&2
echo "IMPACT RADIUS WARNING:" >&2
for msg in "${WARN_MESSAGES[@]}"; do
    echo "  - $msg" >&2
done
echo "" >&2
echo "  This is an advisory warning. The operation will proceed if you confirm." >&2
echo "  To skip this warning, set IRWG_QUIET=1 or use a more specific tool/scope." >&2
echo "" >&2

# Advisory only - exit 0 (allow) by default
# To make this hook block, set IRWG_BLOCK=1
if [ "${IRWG_BLOCK:-0}" = "1" ]; then
    exit 2
fi

exit 0
