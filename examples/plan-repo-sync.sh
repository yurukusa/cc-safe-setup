#!/bin/bash
# plan-repo-sync.sh — Sync plan files from ~/.claude/ into your repo
#
# Solves: Plan files being stored in ~/.claude/plans/ with meaningless
#         random names, far from the project they belong to (#12619, 163+)
#
# How it works: After Write tool creates/updates a plan file in ~/.claude/,
#   this hook copies it into ./plans/ in the current repo with a meaningful
#   name derived from the plan's title/content.
#
# Result: Plans are versioned, searchable, and referenceable in your repo.
#   Example: ~/.claude/plans/abc123.md -> ./plans/PLAN-0001-api-refactor.md
#
# Customize: Change PLAN_DIR to your preferred directory.
#            Change NAME_PATTERN for different naming conventions.
#
# TRIGGER: PostToolUse  MATCHER: "Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only act on Write
[[ "$TOOL" != "Write" ]] && exit 0

# Get the file path that was written
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0

# Only sync files from ~/.claude/ plan-related locations
if ! echo "$FILE" | grep -qE "$HOME/\.claude.*(plan|PLAN)"; then
    exit 0
fi

# Must be in a git repo
git rev-parse --git-dir &>/dev/null || exit 0

# Configurable plan directory (relative to repo root)
PLAN_DIR="plans"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[[ -z "$REPO_ROOT" ]] && exit 0

mkdir -p "$REPO_ROOT/$PLAN_DIR"

# Extract a meaningful name from the plan content
# Uses first heading or first non-empty line as the description
if [ -f "$FILE" ]; then
    # Try to get title from first markdown heading
    TITLE=$(grep -m1 '^#' "$FILE" 2>/dev/null | sed 's/^#\+\s*//' | head -c 60)

    # Fallback: first non-empty line
    if [ -z "$TITLE" ]; then
        TITLE=$(grep -m1 '.' "$FILE" 2>/dev/null | head -c 60)
    fi

    # Sanitize title for filename: lowercase, spaces to hyphens, strip special chars
    SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g' | sed 's/--\+/-/g' | sed 's/^-\|-$//g' | head -c 40)

    # Fallback to source filename if no content
    if [ -z "$SLUG" ]; then
        SLUG=$(basename "$FILE" .md)
    fi

    # Find next available number
    LAST_NUM=$(ls "$REPO_ROOT/$PLAN_DIR"/PLAN-*.md 2>/dev/null | sed 's/.*PLAN-\([0-9]\+\).*/\1/' | sort -n | tail -1)
    NEXT_NUM=$(printf "%04d" $(( ${LAST_NUM:-0} + 1 )))

    DEST="$REPO_ROOT/$PLAN_DIR/PLAN-${NEXT_NUM}-${SLUG}.md"

    # Check if this plan already exists (same source file synced before)
    # Use a tracking comment at the end of the file
    EXISTING=$(grep -rl "<!-- source: $FILE -->" "$REPO_ROOT/$PLAN_DIR" 2>/dev/null | head -1)

    if [ -n "$EXISTING" ]; then
        # Update existing synced plan
        cp "$FILE" "$EXISTING"
        echo "<!-- source: $FILE -->" >> "$EXISTING"
        echo "plan-repo-sync: Updated $(basename "$EXISTING")" >&2
    else
        # Create new synced plan
        cp "$FILE" "$DEST"
        echo "<!-- source: $FILE -->" >> "$DEST"
        echo "plan-repo-sync: Synced to $PLAN_DIR/$(basename "$DEST")" >&2
    fi
fi

exit 0
