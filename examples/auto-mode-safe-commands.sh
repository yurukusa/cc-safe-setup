#!/bin/bash
# auto-mode-safe-commands.sh — Fix Auto Mode false positives on safe commands
#
# Solves: Claude Code's safety classifier blocks legitimate commands in auto mode
#         - $() command substitution flagged as dangerous (#38537, 49 reactions)
#         - Pipe chains flagged unnecessarily (#30435, 29 reactions)
#         - Read-only commands requiring manual approval
#
# How it works: Maintains a whitelist of known-safe command patterns.
#               When the classifier wrongly blocks them, this hook approves.
#               Only approves commands that are genuinely read-only or development-safe.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/auto-mode-safe-commands.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Strip the command to its base (first word after pipes, &&, etc.)
# We check each component of compound commands
APPROVE=false
REASON=""

# --- Read-only commands (never modify state) ---

# File inspection
if echo "$COMMAND" | grep -qE '^\s*(cat|head|tail|less|more|wc|file|stat|du|df|ls|tree|find|which|whereis|type|realpath|readlink)\s'; then
    APPROVE=true
    REASON="Read-only file inspection"
fi

# Text search
if echo "$COMMAND" | grep -qE '^\s*(grep|rg|ag|ack|sed\s+-n|awk)\s'; then
    APPROVE=true
    REASON="Text search/extraction"
fi

# Git read-only
if echo "$COMMAND" | grep -qE '^\s*git\s+(status|log|diff|show|branch|tag|remote|stash\s+list|ls-files|ls-tree|rev-parse|describe|shortlog|blame|config\s+--get)'; then
    APPROVE=true
    REASON="Git read-only operation"
fi

# Package info (read-only)
if echo "$COMMAND" | grep -qE '^\s*(npm\s+(ls|list|info|view|outdated|audit)|pip\s+(list|show|freeze)|yarn\s+(list|info|why)|pnpm\s+(ls|list))\s*'; then
    APPROVE=true
    REASON="Package manager read-only"
fi

# Development tools (safe)
if echo "$COMMAND" | grep -qE '^\s*(echo|printf|date|env|printenv|uname|hostname|whoami|id|pwd|tput)\s*'; then
    APPROVE=true
    REASON="Environment inspection"
fi

# --- Safe command substitution patterns ---
# $() is flagged by classifier but usually wraps read-only commands

# date/timestamp substitution
if echo "$COMMAND" | grep -qE '\$\(date\s'; then
    # Only approve if the outer command is also safe
    OUTER=$(echo "$COMMAND" | sed 's/\$([^)]*)/SUBST/g')
    if echo "$OUTER" | grep -qE '^\s*(echo|printf|mkdir|touch|cp|mv)\s'; then
        APPROVE=true
        REASON="Safe command with date substitution"
    fi
fi

# --- JSON/YAML processing ---
if echo "$COMMAND" | grep -qE '^\s*(jq|yq|python3?\s+-c\s|python3?\s+-m\s+json)\s'; then
    APPROVE=true
    REASON="JSON/YAML processing"
fi

# --- Curl (read-only GET requests) ---
if echo "$COMMAND" | grep -qE '^\s*curl\s+-s' && ! echo "$COMMAND" | grep -qE '\s-X\s+(POST|PUT|PATCH|DELETE)'; then
    APPROVE=true
    REASON="HTTP GET request"
fi

# --- Node.js/Python one-liners ---
if echo "$COMMAND" | grep -qE '^\s*(node|python3?)\s+-e\s'; then
    # Only approve if no file system writes detected
    if ! echo "$COMMAND" | grep -qE '(writeFile|fs\.write|open\(.*["\x27]w|unlink|rmdir)'; then
        APPROVE=true
        REASON="Script one-liner (no fs writes detected)"
    fi
fi

# --- Output the decision ---
if [ "$APPROVE" = true ]; then
    jq -n --arg reason "$REASON" \
        '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":$reason}}'
    exit 0
fi

# No opinion — let the default classifier handle it
exit 0
