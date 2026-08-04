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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-system-dir-protection-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [system-dir-protection-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# --- Look inside wrappers -----------------------------------------------------
# The three gates below open only when the command *starts* with rm / mv /
# chmod, so a command inside a substitution, a subshell, or after a shell
# keyword was never examined. Measured 2026-08-04: this hook blocked the bare
# deletion and passed all six wrappings of it. Claude Code 2.1.221 fixed the
# same shape in its own permission check.
#
# Replace the wrapping tokens with separators and run this same script once more
# against that text. Detection only: never executed, and the message keeps the
# command the user actually sent.
if [ -n "${CC_SYSDIR_UNWRAPPED:-}" ]; then
    COMMAND="$CC_SYSDIR_UNWRAPPED"
elif [ -n "$COMMAND" ]; then
    _sysdir_unwrapped=$(printf '%s' "$COMMAND" | sed -E \
        -e 's/\$\(/ ; /g' -e 's/`/ ; /g' \
        -e 's/(^|[[:space:]])\(/\1 ; /g' -e 's/\)([[:space:]]|$)/ ; \1/g' \
        -e 's/(^|[[:space:]])(then|do|else|elif)([[:space:]])/\1 ; \3/g')
    if [ "$_sysdir_unwrapped" != "$COMMAND" ]; then
        CC_SYSDIR_UNWRAPPED="$_sysdir_unwrapped" bash "$0" </dev/null >/dev/null 2>&1
        if [ "$?" = "2" ]; then
            echo "BLOCKED: an operation on a system directory is hidden inside a wrapper." >&2
            echo "Command: $COMMAND" >&2
            echo "A substitution, a subshell or a shell keyword does not make it safe." >&2
            exit 2
        fi
    fi
fi
[ -z "$COMMAND" ] && exit 0

# Check if a path is a protected system directory
is_system_dir() {
    local path="$1"
    # Remove a trailing slash -- but never on the root itself.
    # `${path%/}` turns "/" into "", so the `/` branch in the case below (which
    # the author did write) could never be reached, and `rm -rf /`, `mv / …`
    # and `chmod -R 777 /` all walked through while `/etc` was blocked.
    # Measured 2026-08-03: the root was the one directory this guard named and
    # then erased one line before checking it.
    [ "$path" != "/" ] && path="${path%/}"

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

# The extractions below used grep -oP, which is GNU-only. BSD grep (macOS)
# rejects -P outright, so every target list came back empty, the loops below
# had nothing to iterate, and the guard exited 0 — `rm -rf /root` went through
# on macOS with no sign that the protection was off. The GNU path is unchanged;
# an equivalent is added for platforms without PCRE.
if echo x | grep -qP x 2>/dev/null; then HAS_PCRE=1; else HAS_PCRE=0; fi

# $1 = command alternation (e.g. "rm|unlink"), $2 = operand pattern.
# \K has no POSIX equivalent, so the fallback matches the whole thing and
# strips the command word and its flags afterwards.
extract_operand() {
    if [ "$HAS_PCRE" = 1 ]; then
        grep -oP "($1)\\s+(-[a-zA-Z]+\\s+)*\\K$2" 2>/dev/null || true
    else
        grep -oE "($1)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*$2" 2>/dev/null \
            | sed -E "s/^($1)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*//" || true
    fi
}

# --- rm / unlink on system directories ---
if echo "$COMMAND" | grep -qE '(^|[;&|])[[:space:]]*(sudo[[:space:]]+)?(rm|unlink)[[:space:]]'; then
    # Extract targets after rm and flags
    TARGETS=$(echo "$COMMAND" | extract_operand 'rm|unlink' '[^;|&]+')
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
if echo "$COMMAND" | grep -qE '(^|[;&|])[[:space:]]*(sudo[[:space:]]+)?mv[[:space:]]'; then
    # Get the source of the mv (first non-flag argument)
    MV_SOURCE=$(echo "$COMMAND" | extract_operand 'mv' '[^[:space:]]+')
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
if echo "$COMMAND" | grep -qE '(^|[;&|])[[:space:]]*(sudo[[:space:]]+)?(chmod|chown)[[:space:]]+.*-R'; then
    # No \K here, so plain ERE is enough (POSIX classes instead of \s).
    TARGETS=$(echo "$COMMAND" | grep -oE '(chmod|chown)[[:space:]]+[^;|&]+' 2>/dev/null | awk '{print $NF}' || true)
    for target in $TARGETS; do
        if is_system_dir "$target"; then
            echo "BLOCKED: Recursive permission change on system directory: $target" >&2
            echo "Command: $COMMAND" >&2
            exit 2
        fi
    done
fi

exit 0
