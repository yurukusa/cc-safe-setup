#!/bin/bash
# ================================================================
# subagent-identity-leak-guard.sh — Warn when subagent delegation
#                                    lacks identity boundary enforcement
# ================================================================
# PURPOSE:
#   When the main agent spawns a subagent via the Agent tool, checks
#   whether the delegation prompt includes explicit identity boundary
#   enforcement: the subagent's own role, prohibition against
#   impersonating the parent, and prohibition against exposing parent
#   conversation history. Warns via stderr when these are missing.
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"
#
# WHY THIS MATTERS:
#   In v2.1.126, a regression was reported in Issue #55488: a spawned
#   subagent (e.g. backend) was DM'd directly via the team chat UI
#   and (1) identified itself as the parent ("team-lead") instead of
#   its assigned name (backend), and (2) showed the user the parent's
#   conversation history. This is an identity boundary failure: the
#   subagent has no persistent state separating its identity from the
#   parent's, so when queried directly it falls back to the parent's
#   identity and history.
#
#   While the root cause needs to be fixed by Anthropic, parent agents
#   can preventively reduce the failure surface by including explicit
#   identity boundary instructions in the delegation prompt. This hook
#   warns when those instructions are missing.
#
# WHAT IT CHECKS:
#   1. Prompt mentions the subagent's own role or name (e.g. "you are",
#      "your role is", "as the X agent")
#   2. Prompt prohibits impersonating the parent (e.g. "do not identify
#      as", "do not claim to be the parent")
#   3. Prompt prohibits exposing parent conversation history (e.g. "do
#      not share parent's history", "do not expose conversation log")
#
# OUTPUT:
#   Warning to stderr listing which identity boundary instructions are
#   missing. Always exits 0 — advisory only, never blocks.
#
# CONFIGURATION:
#   CC_SUBAGENT_IDENTITY_REQUIRE_ALL — set to "1" to require all 3
#       checks (default: warn on any missing check, do not require all)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/55488
# ================================================================

set -u

INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)

if [ -z "$PROMPT" ]; then
    exit 0
fi

WARNINGS=""

# Check 1: Subagent's own role or name is mentioned
if ! printf '%s' "$PROMPT" | grep -qiE 'you are |your role |your name |as the [a-z]+ (agent|subagent)|act as '; then
    WARNINGS="${WARNINGS}  - No explicit role assignment. Subagent may fall back to parent's identity (Issue #55488).\n"
fi

# Check 2: Prohibition against impersonating the parent
if ! printf '%s' "$PROMPT" | grep -qiE 'do not (identify|claim|act|pretend) (as|to be) (the )?(parent|team-lead|orchestrator|main agent)|never (identify|claim|impersonate|pretend) (as|to be) (the )?(parent|team-lead|orchestrator)'; then
    WARNINGS="${WARNINGS}  - No prohibition against impersonating the parent. Without this, the subagent may identify as the parent when DM'd directly.\n"
fi

# Check 3: Prohibition against exposing parent conversation history
if ! printf '%s' "$PROMPT" | grep -qiE 'do not (share|expose|reveal|show) (the )?(parent|main agent)\b.{0,40}(history|conversation|log|messages)|never (share|expose|reveal) (the )?(parent|main agent).{0,40}(history|conversation)'; then
    WARNINGS="${WARNINGS}  - No prohibition against exposing parent's conversation history. Without this, the subagent may show the user the parent's full chat history (Issue #55488 reproduction).\n"
fi

if [ -n "$WARNINGS" ]; then
    REQUIRE_ALL="${CC_SUBAGENT_IDENTITY_REQUIRE_ALL:-0}"
    printf '⚠️  Subagent identity boundary not enforced in delegation prompt:\n' >&2
    printf '%b' "$WARNINGS" >&2
    printf '\n  Reference: https://github.com/anthropics/claude-code/issues/55488\n' >&2
    printf '  Recommended fix: prepend the prompt with the 3 boundary instructions.\n' >&2
    if [ "$REQUIRE_ALL" = "1" ]; then
        # Strict mode: block when any check fails
        exit 2
    fi
fi

exit 0
