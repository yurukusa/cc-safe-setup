#!/bin/bash
# task-integrity-guard.sh — Prevent Claude from deleting tasks to hide unfinished work
#
# Solves: Claude deleting open tasks from todo/tracking documents to
# present a false picture of project progress (#41109)
#
# How it works: When Claude edits a task-tracking file (todo.md, tasks.md,
# epic.md, etc.), this hook checks if the edit REMOVES lines containing
# task markers (- [ ], TODO, PENDING, IN PROGRESS) without replacing them
# with completion markers (- [x], DONE, COMPLETED). If tasks disappear
# without being completed, the edit is blocked.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/task-integrity-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Edit"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[[ "$TOOL" != "Edit" ]] && exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0
[[ -z "$OLD" ]] && exit 0

# Only check task-tracking files
BASENAME=$(basename "$FILE" | tr '[:upper:]' '[:lower:]')
IS_TASK_FILE=0
case "$BASENAME" in
    todo.md|tasks.md|task*.md|epic*.md|sprint*.md|backlog*.md|progress*.md|checklist*.md|mission.md)
        IS_TASK_FILE=1
        ;;
esac
# Also check if path contains task-related directories
if echo "$FILE" | grep -qiE '(tasks|todo|epic|sprint|backlog)/'; then
    IS_TASK_FILE=1
fi

[[ "$IS_TASK_FILE" -eq 0 ]] && exit 0

# Count open task markers in old_string
OLD_OPEN=$(echo "$OLD" | grep -ciE '\- \[ \]|TODO|PENDING|IN.PROGRESS|not.started' 2>/dev/null)
[[ -z "$OLD_OPEN" ]] && OLD_OPEN=0

# Count open task markers in new_string
NEW_OPEN=$(echo "$NEW" | grep -ciE '\- \[ \]|TODO|PENDING|IN.PROGRESS|not.started' 2>/dev/null)
[[ -z "$NEW_OPEN" ]] && NEW_OPEN=0

# Count completed task markers in new_string (strict patterns only)
NEW_DONE=$(echo "$NEW" | grep -ciE '\- \[x\]|\- \[X\]|^DONE$|^COMPLETED$|status:\s*done|status:\s*completed|✅|☑' 2>/dev/null)
[[ -z "$NEW_DONE" ]] && NEW_DONE=0

# If open tasks disappeared and weren't converted to completed
if [[ "$OLD_OPEN" -gt 0 ]] && [[ "$NEW_OPEN" -eq 0 ]] && [[ "$NEW_DONE" -eq 0 ]]; then
    # Tasks were deleted, not completed
    REMOVED=$OLD_OPEN
    echo "BLOCKED: $REMOVED open task(s) would be deleted from $BASENAME without being marked complete. If tasks are done, mark them as [x] instead of removing them." >&2
    exit 2
fi

# If significantly more tasks removed than completed
if [[ "$OLD_OPEN" -gt 2 ]] && [[ "$NEW_OPEN" -eq 0 ]] && [[ "$NEW_DONE" -lt "$OLD_OPEN" ]]; then
    MISSING=$((OLD_OPEN - NEW_DONE))
    if [[ "$MISSING" -gt 1 ]]; then
        echo "WARNING: $MISSING open task(s) would disappear from $BASENAME. Only $NEW_DONE were marked complete. Verify this is intentional." >&2
        # Warning only, don't block (some reorganization is legitimate)
    fi
fi

exit 0
