#!/bin/bash
# ================================================================
# subagent-tool-allowlist-enforcer.sh — Warn when subagent prompt
#                                       lacks tool allowlist boundary
# ================================================================
# PURPOSE:
#   When the main agent spawns a subagent via the Agent tool, checks
#   whether the delegation prompt explicitly states which tools the
#   subagent is allowed to use, which tools are forbidden, and how the
#   parent should verify the subagent's claimed results. Warns via
#   stderr when these tool-boundary instructions are missing.
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"
#
# WHY THIS MATTERS:
#   Issue #55653 reported a subagent that fabricated "saved file" claims
#   while only having read-only tool access. The subagent had no
#   persistent state binding it to its allowed tool list, so when asked
#   to "save", it produced a fictional success report instead of a
#   permission-denied failure. This is a tool-list boundary failure.
#
#   While the root cause must be fixed in the agent runtime, parent
#   agents can preventively reduce the failure surface by stating the
#   allowed tool set explicitly in the delegation prompt and instructing
#   the parent to verify the result with read-only inspection (file
#   stat, git status, etc.) before trusting any "saved" or "modified"
#   claim.
#
# WHAT IT CHECKS:
#   1. Prompt names the allowed tool set (e.g. "you can use Read",
#      "allowed tools:", "tools: read, grep")
#   2. Prompt names the forbidden tools or capability boundary (e.g.
#      "do not write", "no edit", "read-only")
#   3. Prompt instructs the parent to verify results with read-only
#      inspection (e.g. "I will verify with stat", "parent checks
#      file existence", "verify before trusting")
#
# OUTPUT:
#   Warning to stderr listing which tool boundary instructions are
#   missing. Always exits 0 — advisory only, never blocks.
#
# CONFIGURATION:
#   CC_SUBAGENT_TOOL_REQUIRE_ALL — set to "1" to block when any check
#       fails (default: warn only)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/55653
# ================================================================

set -u

INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)

if [ -z "$PROMPT" ]; then
    exit 0
fi

WARNINGS=""

# Check 1: Allowed tool set is named
if ! printf '%s' "$PROMPT" | grep -qiE 'you can use|allowed tools?:|tools:|use only|use the following tools|tool(s)? you may use'; then
    WARNINGS="${WARNINGS}  - No allowed tool set named. Subagent may attempt operations outside its capability and fabricate results (Issue #55653).\n"
fi

# Check 2: Forbidden tools or capability boundary is named
if ! printf '%s' "$PROMPT" | grep -qiE 'do not (write|edit|modify|save|create|delete)|no (write|edit|modify|save)|read[-]?only|never (write|edit|modify|save|create|delete)|forbidden tools?'; then
    WARNINGS="${WARNINGS}  - No forbidden tools or read-only constraint named. Subagent may claim success on operations it cannot actually perform.\n"
fi

# Check 3: Parent's verification step is named
if ! printf '%s' "$PROMPT" | grep -qiE 'verify (with|by|using)|parent (will|should) (check|verify|inspect)|i will verify|verify (the )?result|check (the )?(file|output|result) (exists|after)'; then
    WARNINGS="${WARNINGS}  - No parent verification step. Without read-only inspection (file stat / git status), fabricated claims pass silently.\n"
fi

if [ -n "$WARNINGS" ]; then
    REQUIRE_ALL="${CC_SUBAGENT_TOOL_REQUIRE_ALL:-0}"
    printf '⚠️  Subagent tool boundary not enforced in delegation prompt:\n' >&2
    printf '%b' "$WARNINGS" >&2
    printf '\n  Reference: https://github.com/anthropics/claude-code/issues/55653\n' >&2
    printf '  Recommended fix: name allowed tools, name forbidden capabilities, name parent verification step.\n' >&2
    if [ "$REQUIRE_ALL" = "1" ]; then
        exit 2
    fi
fi

exit 0
