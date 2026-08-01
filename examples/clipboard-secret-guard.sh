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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-clipboard-secret-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [clipboard-secret-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
