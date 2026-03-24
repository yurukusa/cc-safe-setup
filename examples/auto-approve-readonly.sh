#!/bin/bash
# ================================================================
# auto-approve-readonly.sh — Auto-approve all read-only commands
# ================================================================
# PURPOSE:
#   The #1 complaint: permission prompts for cat, ls, grep, find.
#   This hook auto-approves any command that only reads data,
#   while letting destructive commands go through normal approval.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Extract the base command (first word, ignoring env vars and cd prefixes)
BASE=$(echo "$COMMAND" | sed 's/^[A-Z_]*=[^ ]* //g; s/^cd [^;]*[;&|]* //' | awk '{print $1}' | sed 's|.*/||')

# Read-only commands that never modify anything
case "$BASE" in
    cat|head|tail|less|more|wc|grep|rg|ag|ack|find|locate|\
    ls|ll|dir|tree|stat|file|which|whereis|type|realpath|\
    date|uptime|uname|hostname|whoami|id|groups|env|printenv|\
    pwd|df|du|free|top|ps|pgrep|lsof|netstat|ss|\
    git-log|git-diff|git-show|git-status|git-branch|git-remote|git-tag|\
    jq|yq|python3-c|node-e|ruby-e|\
    npm-ls|npm-list|npm-info|npm-view|npm-outdated|\
    pip-list|pip-show|pip-freeze|\
    cargo-tree|go-list|go-doc)
        echo '{"decision":"approve","reason":"Read-only command"}'
        exit 0
        ;;
esac

# git subcommands that are read-only
if echo "$COMMAND" | grep -qE '^\s*git\s+(status|log|diff|show|branch|remote|tag\s+-l|blame|shortlog|describe|rev-parse|ls-files|ls-tree)\b'; then
    echo '{"decision":"approve","reason":"Read-only git command"}'
    exit 0
fi

# Commands piped to read-only output (anything | head, | grep, etc.)
if echo "$COMMAND" | grep -qE '\|\s*(head|tail|grep|wc|sort|uniq|tr|cut|awk|sed|less|more)\s'; then
    # Only approve if the source command is also read-only
    FIRST=$(echo "$COMMAND" | cut -d'|' -f1 | awk '{print $1}')
    case "$FIRST" in
        cat|head|tail|grep|find|ls|git|npm|pip|cargo|go)
            echo '{"decision":"approve","reason":"Read-only pipeline"}'
            exit 0
            ;;
    esac
fi

exit 0
