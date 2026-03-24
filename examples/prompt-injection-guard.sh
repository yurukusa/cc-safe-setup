#!/bin/bash
# ================================================================
# prompt-injection-guard.sh — Detect prompt injection in tool output
# ================================================================
# PURPOSE:
#   When Claude reads files or fetches web content, malicious
#   instructions can be injected. This hook warns when tool output
#   contains common prompt injection patterns.
#
# TRIGGER: PostToolUse  MATCHER: ""
#
# Born from: https://github.com/anthropics/claude-code/issues/38046
#   "Prompt Injection in /insights output"
# ================================================================

INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null)
[ -z "$OUTPUT" ] && exit 0

# Check for common prompt injection patterns
SUSPICIOUS=0

# "Ignore previous instructions" pattern
if echo "$OUTPUT" | grep -qiE 'ignore\s+(all\s+)?previous\s+instructions'; then
    echo "WARNING: Possible prompt injection detected: 'ignore previous instructions'" >&2
    SUSPICIOUS=1
fi

# "You are now" role reassignment
if echo "$OUTPUT" | grep -qiE 'you\s+are\s+now\s+(a|an)\s+'; then
    echo "WARNING: Possible prompt injection detected: role reassignment" >&2
    SUSPICIOUS=1
fi

# "System prompt" manipulation
if echo "$OUTPUT" | grep -qiE '(new|updated|override)\s+system\s+prompt'; then
    echo "WARNING: Possible prompt injection detected: system prompt override" >&2
    SUSPICIOUS=1
fi

# Hidden instructions in HTML comments or zero-width chars
if echo "$OUTPUT" | grep -qP '<!--.*(?:execute|run|delete|remove).*-->'; then
    echo "WARNING: Possible prompt injection in HTML comment" >&2
    SUSPICIOUS=1
fi

if [ "$SUSPICIOUS" -eq 1 ]; then
    echo "Review the output carefully before acting on it." >&2
fi

exit 0
