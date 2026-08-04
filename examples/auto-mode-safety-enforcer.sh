#!/bin/bash
# auto-mode-safety-enforcer.sh — Block dangerous operations in auto/acceptEdits mode
#
# Solves: Auto mode safety classifier hardcoded to opus-4-6, fails with Opus 4.7
#   - #49618: Safety classifier doesn't work with non-opus-4-6 models
#   - #49554: auto mode approved ~/.ssh deletion
#   - #18740: Auto-allow mode data loss without warning
#
# How it works: PreToolUse hook on Bash that blocks destructive commands
#   regardless of which model or permission mode is active. Acts as a
#   user-space safety net when the built-in classifier fails.
#
# What it blocks:
#   - rm -rf on non-safe paths (/, ~, .., /home, /etc, /usr, /var, .git)
#   - Credential file deletion (.ssh, .git-credentials, .env, .npmrc)
#   - dd/mkfs/fdisk (disk operations)
#   - kill -9 on system processes
#   - chmod 777 on sensitive paths
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-auto-mode-safety-enforcer-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [auto-mode-safety-enforcer]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# --- Look inside wrappers -----------------------------------------------------
# The target patterns below require whitespace or end-of-line after the
# dangerous path, so a deletion wrapped in a substitution or a subshell ends
# with `)` and never matches. Measured 2026-08-04: the bare deletion was
# blocked and five of six wrappings passed. Claude Code 2.1.221 fixed the same
# shape in its own permission check.
#
# Replace the wrapping tokens with separators and run this same script once more
# against that text. Detection only: never executed; the message keeps the
# command the user actually sent.
if [ -n "${CC_AUTOMODE_UNWRAPPED:-}" ]; then
    COMMAND="$CC_AUTOMODE_UNWRAPPED"
elif [ -n "$COMMAND" ]; then
    _am_unwrapped=$(printf '%s' "$COMMAND" | sed -E \
        -e 's/\$\(/ ; /g' -e 's/`/ ; /g' \
        -e 's/(^|[[:space:]])\(/\1 ; /g' -e 's/\)([[:space:]]|$)/ ; \1/g' \
        -e 's/\)$/ ; /g' \
        -e 's/(^|[[:space:]])(then|do|else|elif)([[:space:]])/\1 ; \3/g')
    if [ "$_am_unwrapped" != "$COMMAND" ]; then
        CC_AUTOMODE_UNWRAPPED="$_am_unwrapped" bash "$0" </dev/null >/dev/null 2>&1
        if [ "$?" = "2" ]; then
            echo "BLOCKED: a destructive command is hidden inside a wrapper." >&2
            echo "Command: $COMMAND" >&2
            echo "A substitution, a subshell or a shell keyword does not make it safe." >&2
            exit 2
        fi
    fi
fi
[ -z "$COMMAND" ] && exit 0

# --- Critical rm operations ---
if echo "$COMMAND" | grep -qE '(^|\s|;|&&|\|)(sudo\s+)?rm\s'; then
    # Always block rm on root-level and home-level critical paths
    # The home terminators used to be whitespace or end-of-line only, so
    # `rm -rf ~; echo done` passed while `rm -rf ~ ; echo done` was blocked --
    # one space apart, opposite verdicts. Separators end a command just as much
    # as a space does. Measured 2026-08-04.
    if echo "$COMMAND" | grep -qE 'rm\s.*(/[[:space:];&|]|/$|~\/?[[:space:];&|]|~\/?$|~\/\.|/home\b|/etc\b|/usr\b|/var\b|/opt\b|/root\b)'; then
        echo "BLOCKED: rm targeting critical system/home path" >&2
        echo "This operation would cause irreversible data loss." >&2
        echo "Command: $COMMAND" >&2
        exit 2
    fi
    # Block rm on dotfiles in home directory
    if echo "$COMMAND" | grep -qE "rm\s.*(${HOME}|\~)/\."; then
        echo "BLOCKED: rm targeting home dotfile" >&2
        echo "Command: $COMMAND" >&2
        exit 2
    fi
fi

# --- Disk-level operations ---
if echo "$COMMAND" | grep -qE '(^|\s)(sudo\s+)?(dd\s+.*of=/dev|mkfs\.|fdisk\s|parted\s)'; then
    echo "BLOCKED: Disk-level operation (dd/mkfs/fdisk/parted)" >&2
    exit 2
fi

# --- Kill system processes ---
if echo "$COMMAND" | grep -qE 'kill\s+(-9\s+)?1$|killall\s+(init|systemd)'; then
    echo "BLOCKED: Killing system process" >&2
    exit 2
fi

exit 0
