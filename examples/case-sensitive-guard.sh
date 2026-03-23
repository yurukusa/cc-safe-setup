#!/bin/bash
# ================================================================
# case-sensitive-guard.sh — Case-Insensitive Filesystem Safety Guard
# ================================================================
# PURPOSE:
#   Detects case-insensitive filesystems (exFAT, NTFS, HFS+, APFS
#   case-insensitive) and warns before mkdir/rm that would collide
#   due to case folding.
#
#   Real incident: GitHub #37875 — Claude created "Content" dir on
#   exFAT drive where "content" already existed. Both resolved to
#   the same path. Claude then ran rm -rf on "content", destroying
#   all user data.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHAT IT BLOCKS (exit 2):
#   - rm -rf on case-insensitive FS when a case-variant directory
#     exists that resolves to the same inode
#   - mkdir that would silently collide with existing dir on
#     case-insensitive FS
#
# WHAT IT ALLOWS (exit 0):
#   - All commands on case-sensitive filesystems
#   - rm/mkdir where no case collision exists
#   - Commands that don't involve mkdir or rm
#
# HOW IT WORKS:
#   1. Extract target path from mkdir/rm commands
#   2. Check if filesystem is case-insensitive (create temp file,
#      check if uppercase variant exists)
#   3. If case-insensitive, check for case-variant collisions
#   4. Block if collision detected
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only check mkdir and rm commands
if ! echo "$COMMAND" | grep -qE '^\s*(mkdir|rm)\s'; then
    exit 0
fi

# Extract the target path
TARGET=""
if echo "$COMMAND" | grep -qE '^\s*mkdir'; then
    TARGET=$(echo "$COMMAND" | grep -oP 'mkdir\s+(-p\s+)?\K\S+' | tail -1)
elif echo "$COMMAND" | grep -qE '^\s*rm\s'; then
    TARGET=$(echo "$COMMAND" | grep -oP 'rm\s+(-[rf]+\s+)*\K\S+' | tail -1)
fi

if [[ -z "$TARGET" ]]; then
    exit 0
fi

# Resolve the parent directory
PARENT_DIR=$(dirname "$TARGET" 2>/dev/null)
BASE_NAME=$(basename "$TARGET" 2>/dev/null)

if [[ -z "$PARENT_DIR" ]] || [[ ! -d "$PARENT_DIR" ]]; then
    exit 0
fi

# --- Check if filesystem is case-insensitive ---
is_case_insensitive() {
    local dir="$1"
    local test_file="${dir}/.cc_case_test_$$"
    local test_upper="${dir}/.CC_CASE_TEST_$$"

    # Create lowercase test file
    if ! touch "$test_file" 2>/dev/null; then
        return 1  # Can't test, assume case-sensitive (safe default)
    fi

    # Check if uppercase variant resolves to the same file
    if [[ -f "$test_upper" ]]; then
        rm -f "$test_file" 2>/dev/null
        return 0  # Case-insensitive
    else
        rm -f "$test_file" 2>/dev/null
        return 1  # Case-sensitive
    fi
}

# --- Check for case-variant collisions ---
find_case_collision() {
    local dir="$1"
    local name="$2"
    local name_lower
    name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')

    # List directory entries and check for case variants
    while IFS= read -r entry; do
        local entry_lower
        entry_lower=$(echo "$entry" | tr '[:upper:]' '[:lower:]')
        if [[ "$entry_lower" == "$name_lower" ]] && [[ "$entry" != "$name" ]]; then
            echo "$entry"
            return 0
        fi
    done < <(ls -1 "$dir" 2>/dev/null)

    return 1
}

# Only proceed if filesystem is case-insensitive
if ! is_case_insensitive "$PARENT_DIR"; then
    exit 0
fi

# Check for collision
COLLISION=$(find_case_collision "$PARENT_DIR" "$BASE_NAME")

if [[ -n "$COLLISION" ]]; then
    if echo "$COMMAND" | grep -qE '^\s*rm\s'; then
        echo "BLOCKED: Case-insensitive filesystem collision detected." >&2
        echo "" >&2
        echo "Command: $COMMAND" >&2
        echo "" >&2
        echo "Target: $TARGET" >&2
        echo "Collides with: $PARENT_DIR/$COLLISION" >&2
        echo "" >&2
        echo "This filesystem is case-insensitive (exFAT, NTFS, HFS+, etc.)." >&2
        echo "'$BASE_NAME' and '$COLLISION' resolve to the SAME path." >&2
        echo "rm -rf would destroy the data you think you're keeping." >&2
        echo "" >&2
        echo "Verify with: ls -la \"$PARENT_DIR\" | grep -i \"$BASE_NAME\"" >&2
        exit 2
    elif echo "$COMMAND" | grep -qE '^\s*mkdir'; then
        echo "WARNING: Case-insensitive filesystem — directory already exists." >&2
        echo "" >&2
        echo "Command: $COMMAND" >&2
        echo "Existing: $PARENT_DIR/$COLLISION" >&2
        echo "" >&2
        echo "On this filesystem, '$BASE_NAME' and '$COLLISION' are the same path." >&2
        echo "mkdir will either fail or silently use the existing directory." >&2
        exit 2
    fi
fi

exit 0
