#!/bin/bash
# clipboard-secret-guard.sh — Block secrets from being copied to clipboard
#
# Solves: Claude Code may pipe sensitive data (API keys, tokens, passwords)
#   to clipboard utilities (pbcopy, xclip, xsel, wl-copy). This leaks
#   secrets outside the terminal where they persist and may sync to cloud.
#
# How it works: PreToolUse hook that detects clipboard commands containing
#   secret-like patterns. Blocks the operation.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
# CATEGORY: security

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Check if command pipes to clipboard
if echo "$CMD" | grep -qiE '(pbcopy|xclip|xsel|wl-copy|clip\.exe)'; then
    # Check if the piped content looks like it contains secrets
    if echo "$CMD" | grep -qiE '(api.?key|secret|token|password|passwd|credential|private.?key|Bearer|AWS_|ANTHROPIC_|OPENAI_)'; then
        echo "BLOCKED: Attempting to copy secret-like content to clipboard." >&2
        echo "  Clipboard data may sync to cloud or persist after session." >&2
        exit 2
    fi
fi

exit 0
