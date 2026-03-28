#!/bin/bash
# subagent-scope-validator.sh — Validate subagent task scope before launch
#
# Solves: Main agent's subagent delegation produces poor scoping (#40339).
#         Subagents are launched with vague prompts, missing context,
#         and no result verification criteria.
#
# How it works: PreToolUse hook on "Agent" that checks the prompt
#   for minimum scope requirements:
#   1. Prompt must be longer than 50 characters (not just "do X")
#   2. Must contain file paths or specific identifiers
#   3. Warns if no success criteria are mentioned
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Agent" ] && exit 0

PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

PROMPT_LEN=${#PROMPT}
WARNINGS=""

# Check 1: Minimum prompt length
if [ "$PROMPT_LEN" -lt 50 ]; then
    WARNINGS="${WARNINGS}\n  - Prompt is only ${PROMPT_LEN} chars. Subagents need detailed context (50+ chars recommended)"
fi

# Check 2: Contains specific identifiers (files, functions, paths)
if ! echo "$PROMPT" | grep -qE '/[a-zA-Z]|\.ts|\.py|\.js|\.md|\.json|\.sh|function |class |def |const |let |var '; then
    WARNINGS="${WARNINGS}\n  - No file paths or code identifiers found. Subagent may lack context"
fi

# Check 3: Success criteria
if ! echo "$PROMPT" | grep -qiE 'verify|confirm|test|check|ensure|must|should|expect|return|report'; then
    WARNINGS="${WARNINGS}\n  - No success criteria detected. Consider adding verification steps"
fi

# Output warnings (don't block — just inform)
if [ -n "$WARNINGS" ]; then
    echo "⚠ Subagent scope review:" >&2
    echo -e "$WARNINGS" >&2
    echo "  Prompt preview: $(echo "$PROMPT" | head -c 100)..." >&2
fi

exit 0
