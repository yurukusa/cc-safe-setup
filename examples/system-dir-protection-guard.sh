#!/bin/bash
# system-dir-protection-guard.sh — Block destructive operations on system directories
#
# Solves: Agent deleting or moving system-level directories in auto mode
#   - #49554: Auto mode approved deletion of system directories
#   - #49129: rm -rf on /home subdirectories causing 50GB data loss
#
# Difference from existing hooks:
#   rm-safety-net.sh:    Blocks rm on critical paths, but only rm commands
#   home-critical-bash-guard.sh: Protects ~/dotfiles only
#   This hook: Blocks rm, mv, chmod -R, chown -R on ALL system directories
#              including /home/*, /usr, /etc, /var, /opt, /root, /boot, /srv
#              Also blocks mv of system dirs (not covered by rm-safety-net)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Check if a path is a protected system directory
is_system_dir() {
    local path="$1"
    # Remove trailing slash
    path="${path%/}"

    # Expand ~ to $HOME
    if [[ "$path" == "~"* ]]; then
        path="${HOME}${path#\~}"
    fi

    # Top-level system directories
    case "$path" in
        /|/home|/etc|/usr|/var|/opt|/root|/boot|/srv|/sys|/proc)
            return 0 ;;
    esac

    # /home/<username> (1 level deep)
    if echo "$path" | grep -qE '^/home/[^/]+$'; then
        return 0
    fi

    # System subdirectories (e.g., /etc/nginx, /usr/local, /var/lib)
    if echo "$path" | grep -qE '^/(etc|usr|var|opt|root|boot|srv|sys|proc)/'; then
        return 0
    fi

    # Critical home directories: ~/.ssh, ~/.config, ~/.local, ~/.gnupg, ~/.cache
    if echo "$path" | grep -qE "^${HOME}/\.(ssh|config|local|gnupg|cache)(/[^/]*)?$"; then
        return 0
    fi

    return 1
}

# --- rm / unlink on system directories ---
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?(rm|unlink)\s'; then
    # Extract targets after rm and flags
    TARGETS=$(echo "$COMMAND" | grep -oP '(rm|unlink)\s+(-[a-zA-Z]+\s+)*\K[^;|&]+' 2>/dev/null || true)
    for target in $TARGETS; do
        if is_system_dir "$target"; then
            echo "BLOCKED: Destructive operation on system directory: $target" >&2
            echo "Command: $COMMAND" >&2
            echo "" >&2
            echo "System directories must not be deleted. Use specific file paths instead." >&2
            echo "See: https://github.com/anthropics/claude-code/issues/49554" >&2
            exit 2
        fi
    done
fi

# --- mv (moving system directories) ---
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?mv\s'; then
    # Get the source of the mv (first non-flag argument)
    MV_SOURCE=$(echo "$COMMAND" | grep -oP 'mv\s+(-[a-zA-Z]+\s+)*\K\S+' 2>/dev/null || true)
    if is_system_dir "$MV_SOURCE"; then
        echo "BLOCKED: Moving system directory: $MV_SOURCE" >&2
        echo "Command: $COMMAND" >&2
        echo "" >&2
        echo "System directories must not be moved." >&2
        echo "See: https://github.com/anthropics/claude-code/issues/49554" >&2
        exit 2
    fi
fi

# --- chmod -R / chown -R on system directories ---
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?(chmod|chown)\s+.*-R'; then
    TARGETS=$(echo "$COMMAND" | grep -oP '(chmod|chown)\s+[^;|&]+' 2>/dev/null | awk '{print $NF}' || true)
    for target in $TARGETS; do
        if is_system_dir "$target"; then
            echo "BLOCKED: Recursive permission change on system directory: $target" >&2
            echo "Command: $COMMAND" >&2
            exit 2
        fi
    done
fi

exit 0
