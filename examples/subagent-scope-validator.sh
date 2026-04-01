#!/bin/bash
# ================================================================
# subagent-scope-validator.sh — Warn on vague subagent delegation
# ================================================================
# PURPOSE:
#   When the main agent spawns a subagent, checks whether the
#   delegation prompt includes sufficient context: file paths,
#   specific questions, and adequate length. Warns via stderr
#   when the delegation looks vague — the #1 cause of poor
#   subagent results.
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"
#
# WHY THIS MATTERS:
#   The main agent often delegates with vague prompts like
#   "investigate the auth flow" instead of "read src/auth/login.ts
#   lines 45-80 and trace how the JWT is validated." Vague prompts
#   produce shallow, incorrect subagent results. This hook catches
#   it before the subagent wastes a context window.
#
# WHAT IT CHECKS:
#   1. Prompt length (< 100 chars is almost always too vague)
#   2. Presence of file paths (subagents need specific files)
#   3. Presence of actionable verbs (read, check, verify, find, grep)
#
# OUTPUT:
#   Warning to stderr when delegation looks vague.
#   Always exits 0 — advisory only, never blocks.
#
# CONFIGURATION:
#   CC_SUBAGENT_MIN_PROMPT_LEN — minimum prompt length (default: 100)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/40339
# ================================================================

set -u

INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)

if [ -z "$PROMPT" ]; then
    exit 0
fi

MIN_LEN="${CC_SUBAGENT_MIN_PROMPT_LEN:-100}"
WARNINGS=""

# Check 1: Prompt length
PROMPT_LEN=${#PROMPT}
if [ "$PROMPT_LEN" -lt "$MIN_LEN" ]; then
    WARNINGS="${WARNINGS}  - Prompt is only ${PROMPT_LEN} chars (minimum recommended: ${MIN_LEN})\n"
fi

# Check 2: File paths present?
if ! printf '%s' "$PROMPT" | grep -qE '(/[a-zA-Z0-9_.-]+){2,}|\.[a-z]{1,4}\b|src/|lib/|test/|docs/'; then
    WARNINGS="${WARNINGS}  - No file paths detected. Subagents need specific files to read.\n"
fi

# Check 3: Actionable verbs?
if ! printf '%s' "$PROMPT" | grep -qiE '\b(read|check|verify|find|grep|search|look at|examine|trace|compare|analyze)\b'; then
    WARNINGS="${WARNINGS}  - No actionable verbs found. Tell the subagent exactly what to do.\n"
fi

if [ -n "$WARNINGS" ]; then
    printf '\n⚠ Subagent delegation quality check:\n' >&2
    printf '%b' "$WARNINGS" >&2
    printf 'Tip: Include specific file paths, line ranges, and what a complete answer looks like.\n\n' >&2
fi

exit 0
