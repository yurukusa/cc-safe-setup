#!/bin/bash
# compaction-transcript-guard.sh — Save conversation state before compaction
#
# Solves: Compaction race condition destroys transcript (#40352).
#         When rate limiting hits during compaction, the JSONL transcript
#         is left with 4,300+ empty messages. All context is permanently lost.
#
# How it works: Uses PreCompact hook event to save a recovery snapshot
#   before compaction begins. If compaction fails, the snapshot enables
#   manual recovery.
#
# Saves:
#   1. Git state (uncommitted changes committed as checkpoint)
#   2. Current task context to ~/.claude/recovery/pre-compact-snapshot.md
#   3. Recent file list to ~/.claude/recovery/recent-files.txt
#
# TRIGGER: PreCompact
# MATCHER: No matcher support — fires on every compaction
#
# DECISION CONTROL: None (notification only)

RECOVERY_DIR="${HOME}/.claude/recovery"
mkdir -p "$RECOVERY_DIR"

TIMESTAMP=$(date -u '+%Y%m%d-%H%M%S')
SNAPSHOT="${RECOVERY_DIR}/pre-compact-${TIMESTAMP}.md"

# 1. Save git state
if git rev-parse --is-inside-work-tree &>/dev/null; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
    LAST_COMMIT=$(git log --oneline -1 2>/dev/null)

    # Auto-commit uncommitted changes
    if [ "$DIRTY" -gt 0 ]; then
        git add -A 2>/dev/null
        git commit -m "recovery: pre-compact checkpoint (${DIRTY} files, ${TIMESTAMP})" --no-verify 2>/dev/null
        echo "📸 Recovery checkpoint: ${DIRTY} uncommitted files saved" >&2
    fi

    cat > "$SNAPSHOT" << EOF
# Pre-Compaction Recovery Snapshot
Timestamp: ${TIMESTAMP}
Branch: ${BRANCH}
Uncommitted files: ${DIRTY}
Last commit: ${LAST_COMMIT}

## Recent files (last 10 modified)
$(git diff --name-only HEAD~3 HEAD 2>/dev/null | tail -10)

## Working directory
$(pwd)

## Recovery instructions
If compaction failed and context was lost:
1. Check git log: git log --oneline -5
2. Restore from checkpoint: git show HEAD
3. Resume work from this snapshot
EOF
fi

# 2. Save list of recently accessed files
if [ -f "${HOME}/.claude/session-changes.log" ]; then
    tail -20 "${HOME}/.claude/session-changes.log" > "${RECOVERY_DIR}/recent-files-${TIMESTAMP}.txt"
fi

echo "📋 Recovery snapshot saved: ${SNAPSHOT}" >&2
echo "  If compaction fails, recovery data is preserved" >&2

exit 0
