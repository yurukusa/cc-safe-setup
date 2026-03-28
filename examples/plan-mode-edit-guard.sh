#!/bin/bash
# plan-mode-edit-guard.sh — Warn when editing non-plan files during plan mode
#
# Solves: Claude editing source files while plan mode is active,
#         bypassing the "plan only" constraint. Real incident: #38255 —
#         Opus edited api/app/routers/ despite system reminders saying
#         plan mode was active.
#
# How it works: Uses a flag file to track plan mode state.
#   - Create ~/.claude/plan-mode-active to enable (touch the file)
#   - Delete it to disable (rm the file)
#   - When active, Edit/Write to non-plan files triggers a warning
#
# Integrate with your workflow:
#   Before entering plan mode: touch ~/.claude/plan-mode-active
#   After exiting plan mode:   rm -f ~/.claude/plan-mode-active
#
# Does NOT block (warns only) because false positives during
# legitimate plan-mode file creation would be disruptive.
# Change exit 0 to exit 2 at the bottom to enforce strict blocking.
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

FLAG="$HOME/.claude/plan-mode-active"

# Only check when plan mode flag exists
[ ! -f "$FLAG" ] && exit 0

# Get the file being edited
case "$TOOL" in
    Edit)
        FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        ;;
    Write)
        FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        ;;
    *)
        exit 0
        ;;
esac

[ -z "$FILE" ] && exit 0

# Allow plan files
if echo "$FILE" | grep -qiE '\.plan\.md$|plan\.md$|/plans/|task_plan\.md|findings\.md|progress\.md'; then
    exit 0
fi

# Allow CLAUDE.md and memory files (often updated during planning)
if echo "$FILE" | grep -qiE 'CLAUDE\.md$|MEMORY\.md$|memory/|\.claude/'; then
    exit 0
fi

# Warn about non-plan file edits
echo "⚠ PLAN MODE ACTIVE: Editing non-plan file: $FILE" >&2
echo "  Plan mode should only modify plan files." >&2
echo "  Remove ~/.claude/plan-mode-active to disable this check." >&2

# Warning only (exit 0). Change to exit 2 to block.
exit 0
