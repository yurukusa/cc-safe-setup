#!/bin/bash
# hook-tamper-guard.sh — Prevent Claude from modifying its own hooks
#
# Solves: Claude can rewrite its own hooks to weaken enforcement
#         (#32376 — "Who watches the watchmen?")
#
# Blocks Edit/Write to:
#   ~/.claude/hooks/     (hook scripts)
#   ~/.claude/settings.json  (hook registration)
#   .claude/hooks/       (project-level hooks)
#
# Also blocks Bash commands that modify these paths:
#   mv/cp/rm on hook files
#   sed/awk that edit hook files
#   echo/cat/tee that overwrite hook files
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write|Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Edit|Write|Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/hook-tamper-guard.sh" }]
#     }]
#   }
# }

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-hook-tamper-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [hook-tamper-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# --- Check Edit/Write tools ---
if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
    [ -z "$FILE" ] && exit 0

    # Expand ~ to $HOME
    FILE=$(echo "$FILE" | sed "s|^~|$HOME|")

    # Block writes to hook directories and settings
    if echo "$FILE" | grep -qE '\.claude/hooks/|\.claude/settings\.json|\.claude/settings\.local\.json'; then
        echo "BLOCKED: Cannot modify hook files or settings. This protects the integrity of your safety hooks." >&2
        echo "If you need to modify hooks, do it manually outside Claude Code." >&2
        exit 2
    fi
fi

# --- Check Bash commands ---
if [ "$TOOL" = "Bash" ]; then
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$CMD" ] && exit 0

    # Block commands that modify hook files
    if echo "$CMD" | grep -qE '(mv|cp|rm|sed|awk|tee|cat\s*>)\s.*\.claude/(hooks/|settings\.json|settings\.local\.json)'; then
        echo "BLOCKED: Cannot modify hook files via shell commands." >&2
        exit 2
    fi

    # Block chmod on hook files (could remove execute permission)
    if echo "$CMD" | grep -qE 'chmod\s.*\.claude/hooks/'; then
        echo "BLOCKED: Cannot change hook file permissions." >&2
        exit 2
    fi
fi

exit 0
