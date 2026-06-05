#!/bin/bash
# skill-cumulative-size-detector.sh — Detect cumulative skill descriptions size
#                                     approaching the silent-drop threshold
#
# Solves: Issue #59921 — Skill descriptions silently dropped from system prompt
#         above some cumulative-size threshold. The user enables many skills,
#         the system prompt size grows past an undocumented threshold, and
#         some skill descriptions are silently omitted from the active context.
#         The user cannot tell which skills are active versus dropped from
#         within a running session.
#
# How it works: SessionStart hook that walks both user-scope (~/.claude/skills)
#               and project-scope (.claude/skills) directories, sums the byte
#               counts of every SKILL.md description, and emits an advisory
#               warning when the cumulative total approaches or exceeds the
#               observed silent-drop threshold. Read-only; never modifies
#               any skill content.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# Tunables:
#   CC_SKILL_SIZE_WARN_BYTES        — soft warning threshold (default 25000)
#   CC_SKILL_SIZE_HARD_BYTES        — hard warning threshold (default 50000)
#   CC_SKILL_SIZE_DISABLE_WARNING=1 — suppress all warnings
#
# Exit: always 0 (advisory). Output goes to stderr.

set -uo pipefail

if [ "${CC_SKILL_SIZE_DISABLE_WARNING:-0}" = "1" ]; then
    exit 0
fi

WARN_BYTES="${CC_SKILL_SIZE_WARN_BYTES:-25000}"
HARD_BYTES="${CC_SKILL_SIZE_HARD_BYTES:-50000}"

# Absorb the SessionStart JSON without depending on its fields.
read -r -d '' _INPUT < /dev/stdin 2>/dev/null || true

# Helper: append every SKILL.md byte count under a base directory.
count_skill_bytes() {
    local base="$1"
    local total=0
    local count=0
    [ -d "$base" ] || { printf '%d %d\n' 0 0; return 0; }
    while IFS= read -r -d '' file; do
        local size
        size=$(wc -c < "$file" 2>/dev/null || printf '0')
        total=$((total + size))
        count=$((count + 1))
    done < <(find "$base" -mindepth 1 -maxdepth 3 -type f -name 'SKILL.md' -print0 2>/dev/null)
    printf '%d %d\n' "$total" "$count"
}

USER_BASE="${HOME}/.claude/skills"
read -r USER_BYTES USER_COUNT <<< "$(count_skill_bytes "$USER_BASE")"

PROJECT_BASE=".claude/skills"
read -r PROJECT_BYTES PROJECT_COUNT <<< "$(count_skill_bytes "$PROJECT_BASE")"

TOTAL_BYTES=$((USER_BYTES + PROJECT_BYTES))
TOTAL_COUNT=$((USER_COUNT + PROJECT_COUNT))

if [ "$TOTAL_BYTES" -lt "$WARN_BYTES" ]; then
    exit 0
fi

LEVEL="WARN"
if [ "$TOTAL_BYTES" -ge "$HARD_BYTES" ]; then
    LEVEL="HARD"
fi

{
    echo "[$LEVEL] Cumulative skill description size approaches silent-drop threshold."
    echo ""
    echo "  user scope    ($USER_BASE): ${USER_BYTES} bytes across ${USER_COUNT} SKILL.md files"
    echo "  project scope ($PROJECT_BASE): ${PROJECT_BYTES} bytes across ${PROJECT_COUNT} SKILL.md files"
    echo "  cumulative total: ${TOTAL_BYTES} bytes across ${TOTAL_COUNT} skills"
    echo ""
    echo "  soft warning threshold: ${WARN_BYTES} bytes"
    echo "  hard warning threshold: ${HARD_BYTES} bytes"
    echo ""
    echo "  Issue #59921: Skill descriptions silently dropped from system prompt"
    echo "                above an undocumented cumulative-size threshold."
    echo "                The user cannot tell which skills are active versus"
    echo "                dropped from within a running session."
    echo ""
    if [ "$LEVEL" = "HARD" ]; then
        echo "  Some skill descriptions are very likely already being silently dropped."
    else
        echo "  Some skill descriptions may be silently dropped in this session."
    fi
    echo "  Recommended actions to confirm scope and recover the dropped skills:"
    echo "    1. Run /skills to list which skills the model can currently see."
    echo "    2. Cross-check against ls $USER_BASE $PROJECT_BASE to find the gap."
    echo "    3. Disable rarely-used skills (move them out of the skills/ tree)"
    echo "       until the cumulative total falls below the warning threshold."
    echo ""
    echo "  Suppress this warning: CC_SKILL_SIZE_DISABLE_WARNING=1"
    echo "  Adjust thresholds:     CC_SKILL_SIZE_WARN_BYTES / CC_SKILL_SIZE_HARD_BYTES"
} >&2

exit 0
