#!/bin/bash
# sandbox-denywrite-enforcer.sh — Enforce denyWrite rules for Write/Edit tools
#
# Solves: Write/Edit tools bypass sandbox.filesystem.denyWrite (#52325, #33681, #29048).
#         Bash tool correctly enforces denyWrite via bubblewrap/sandbox-exec,
#         but Write/Edit run in-process via fs.writeFile, skipping sandbox entirely.
#         This hook replicates denyWrite/allowWrite checks for Write/Edit.
#
# How it works: Reads allowWrite paths from environment or config,
#   then blocks Write/Edit operations targeting paths outside those allowed.
#
# Configuration: Set CC_ALLOW_WRITE_PATHS as colon-separated paths, or
#   the hook reads from .claude/settings.json sandbox config.
#
# TRIGGER: PreToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Resolve to absolute path
FILE=$(realpath -m "$FILE" 2>/dev/null || echo "$FILE")

# Source 1: Environment variable (colon-separated)
if [ -n "$CC_ALLOW_WRITE_PATHS" ]; then
    IFS=':' read -ra ALLOWED <<< "$CC_ALLOW_WRITE_PATHS"
else
    # Source 2: Read from .claude/settings.json
    SETTINGS=""
    for cfg in ".claude/settings.json" "$HOME/.claude/settings.json"; do
        [ -f "$cfg" ] && SETTINGS="$cfg" && break
    done

    if [ -n "$SETTINGS" ]; then
        ALLOWED=()
        while IFS= read -r p; do
            [ -n "$p" ] && ALLOWED+=("$p")
        done < <(jq -r '.sandbox.filesystem.allowWrite[]? // empty' "$SETTINGS" 2>/dev/null)
    fi
fi

# If no allowWrite config found, skip enforcement
[ ${#ALLOWED[@]} -eq 0 ] && exit 0

# Check if file path is within any allowed path
for allowed in "${ALLOWED[@]}"; do
    allowed=$(realpath -m "$allowed" 2>/dev/null || echo "$allowed")
    case "$FILE" in
        "$allowed"/*|"$allowed") exit 0 ;;
    esac
done

# /tmp is always allowed (common for temp files)
case "$FILE" in
    /tmp/*|/tmp) exit 0 ;;
esac

echo "BLOCKED: Write to $FILE denied by sandbox policy" >&2
echo "  sandbox.filesystem.denyWrite does not apply to Write/Edit tools (bug #52325)." >&2
echo "  This hook enforces the restriction. Allowed paths:" >&2
for allowed in "${ALLOWED[@]}"; do
    echo "    - $allowed" >&2
done
echo "  Set CC_ALLOW_WRITE_PATHS or update .claude/settings.json to add paths." >&2
exit 2
