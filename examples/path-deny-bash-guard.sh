#!/bin/bash
# path-deny-bash-guard.sh — Enforce path deny rules on Bash commands
#
# Solves: Bash tool bypasses settings.json path deny rules (#39987).
#         Read/Glob/Grep respect deny rules, but Bash commands like
#         `cat /denied/path/file.txt` or `grep pattern /denied/path/`
#         bypass the restriction entirely.
#
# How it works: Reads denied paths from CC_DENIED_PATHS env var or
#   a config file, then checks if any Bash command argument contains
#   a denied path.
#
# CONFIG:
#   CC_DENIED_PATHS="/path/one:/path/two:/path/three"
#   Or create ~/.claude/denied-paths.txt (one path per line)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Load denied paths
DENIED_PATHS=""

# Source 1: Environment variable (colon-separated)
if [ -n "${CC_DENIED_PATHS:-}" ]; then
    DENIED_PATHS="$CC_DENIED_PATHS"
fi

# Source 2: Config file (one path per line)
DENY_FILE="${HOME}/.claude/denied-paths.txt"
if [ -f "$DENY_FILE" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" =~ ^# ]] && continue
        if [ -n "$DENIED_PATHS" ]; then
            DENIED_PATHS="${DENIED_PATHS}:${line}"
        else
            DENIED_PATHS="$line"
        fi
    done < "$DENY_FILE"
fi

[ -z "$DENIED_PATHS" ] && exit 0

# Check command against denied paths
IFS=':'
for denied_path in $DENIED_PATHS; do
    [ -z "$denied_path" ] && continue
    # Normalize: remove trailing slash
    denied_path="${denied_path%/}"

    if echo "$COMMAND" | grep -qF "$denied_path"; then
        echo "BLOCKED: Bash command accesses denied path" >&2
        echo "  Denied: $denied_path" >&2
        echo "  Command: $(echo "$COMMAND" | head -c 100)" >&2
        echo "  Note: This path is restricted in your deny rules." >&2
        echo "        Use Read/Glob/Grep tools which respect deny rules," >&2
        echo "        or remove the path from denied-paths.txt." >&2
        exit 2
    fi
done

exit 0
