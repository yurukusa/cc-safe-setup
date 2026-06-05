#!/bin/bash
# ================================================================
# git-pack-temp-cleanup-guard.sh — Stop tmp_pack_* explosion
# ================================================================
# PURPOSE:
#   Subagents and parallel git operations leave stale
#   .git/objects/pack/tmp_pack_* files behind when git gc / repack
#   fails or is interrupted. These accumulate without bound and can
#   fill ext4.vhdx (observed: 1,350 files / 144 GB on a single repo).
#
#   This hook runs before any git command. It removes tmp_pack_*
#   files older than CC_GIT_PACK_AGE_MIN minutes, then checks the
#   remaining total. Above thresholds, it warns or blocks.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIG:
#   CC_GIT_PACK_AGE_MIN=60         minutes; older tmp_pack_* are removed
#   CC_GIT_PACK_WARN_GB=1          warn at this many GiB remaining
#   CC_GIT_PACK_STRONG_GB=5        strong warning at this many GiB
#   CC_GIT_PACK_BLOCK_GB=10        block git command at this many GiB
#   CC_GIT_PACK_DISABLE=1          set to disable this hook entirely
# ================================================================

[ "${CC_GIT_PACK_DISABLE:-0}" = "1" ] && exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Only act on git commands. \bgit\b matches git as a whole word, so
# pathnames like /usr/bin/gitlab won't trigger.
echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9._-])git([^a-zA-Z0-9._-]|$)' || exit 0

AGE_MIN="${CC_GIT_PACK_AGE_MIN:-60}"
WARN_GB="${CC_GIT_PACK_WARN_GB:-1}"
STRONG_GB="${CC_GIT_PACK_STRONG_GB:-5}"
BLOCK_GB="${CC_GIT_PACK_BLOCK_GB:-10}"

# Resolve the .git directory of the current repo. If we are outside a
# git repo, exit silently — the user's git command will fail on its own.
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
PACK_DIR="$GIT_DIR/objects/pack"

[ -d "$PACK_DIR" ] || exit 0

# Step 1: remove tmp_pack_* older than AGE_MIN minutes.
# Use -maxdepth 1 so we never recurse. Only match the literal prefix.
removed_count=0
removed_bytes=0
while IFS= read -r -d '' f; do
    sz=$(stat -c '%s' "$f" 2>/dev/null || echo 0)
    if rm -f "$f" 2>/dev/null; then
        removed_count=$((removed_count + 1))
        removed_bytes=$((removed_bytes + sz))
    fi
done < <(find "$PACK_DIR" -maxdepth 1 -type f -name 'tmp_pack_*' -mmin "+$AGE_MIN" -print0 2>/dev/null)

if [ "$removed_count" -gt 0 ]; then
    removed_mib=$((removed_bytes / 1024 / 1024))
    echo "INFO: git-pack-temp-cleanup-guard removed $removed_count stale tmp_pack_* files (${removed_mib} MiB) older than ${AGE_MIN} min in $PACK_DIR" >&2
fi

# Step 2: compute remaining total size of tmp_pack_*.
remaining_bytes=0
while IFS= read -r -d '' f; do
    sz=$(stat -c '%s' "$f" 2>/dev/null || echo 0)
    remaining_bytes=$((remaining_bytes + sz))
done < <(find "$PACK_DIR" -maxdepth 1 -type f -name 'tmp_pack_*' -print0 2>/dev/null)

remaining_gb=$((remaining_bytes / 1024 / 1024 / 1024))

if [ "$remaining_gb" -ge "$BLOCK_GB" ]; then
    echo "BLOCKED: tmp_pack_* total is ${remaining_gb} GiB in $PACK_DIR (threshold ${BLOCK_GB} GiB)." >&2
    echo "  Past incidents accumulated 144 GiB and filled ext4.vhdx." >&2
    echo "  Investigate before running more git commands. Inspect with:" >&2
    echo "    find \"$PACK_DIR\" -maxdepth 1 -name 'tmp_pack_*' -printf '%s %p\\n'" >&2
    echo "  Override (one shot) with: CC_GIT_PACK_DISABLE=1 git ..." >&2
    exit 2
fi

if [ "$remaining_gb" -ge "$STRONG_GB" ]; then
    echo "STRONG WARNING: tmp_pack_* total is ${remaining_gb} GiB in $PACK_DIR (strong threshold ${STRONG_GB} GiB)." >&2
    echo "  Investigate parallel git activity before this grows further." >&2
elif [ "$remaining_gb" -ge "$WARN_GB" ]; then
    echo "WARNING: tmp_pack_* total is ${remaining_gb} GiB in $PACK_DIR (threshold ${WARN_GB} GiB)." >&2
fi

exit 0
