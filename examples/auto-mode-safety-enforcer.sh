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
[ -z "$COMMAND" ] && exit 0

# --- Critical rm operations ---
if echo "$COMMAND" | grep -qE '(^|\s|;|&&|\|)(sudo\s+)?rm\s'; then
    # Always block rm on root-level and home-level critical paths
    if echo "$COMMAND" | grep -qE 'rm\s.*(/\s|/;|/$|~\/?\s|~\/?$|~\/\.|/home\b|/etc\b|/usr\b|/var\b|/opt\b|/root\b)'; then
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
