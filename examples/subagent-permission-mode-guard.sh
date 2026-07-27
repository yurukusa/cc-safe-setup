#!/bin/bash
# ================================================================
# subagent-permission-mode-guard.sh — Warn when Agent tool's mode
#                                     parameter conflicts with sub-agent
#                                     frontmatter permissionMode
# ================================================================
# PURPOSE:
#   When the main agent spawns a sub-agent via the Agent tool with a
#   `mode` parameter (e.g. `bypassPermissions`), checks whether the
#   delegation prompt acknowledges that the sub-agent's YAML frontmatter
#   `permissionMode` field can silently override the spawn-time
#   parameter. Warns when the delegation prompt assumes the spawn-time
#   parameter wins.
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"
#
# WHY THIS MATTERS:
#   Issue #55691 reported that the Agent tool's `mode` parameter does
#   not override a sub-agent's YAML frontmatter `permissionMode`. When
#   the sub-agent has no `permissionMode` declared, behaviour falls back
#   to `default` mode — and the spawn-time `mode` parameter is silently
#   a no-op. The docs read as if the Agent tool parameter wins
#   per-spawn, but empirically the frontmatter (or its absence) wins.
#
#   This is a permission-priority boundary failure. The parent agent
#   may believe it has elevated the sub-agent's permissions for a
#   specific task, while the sub-agent silently runs in default mode.
#   The work proceeds without the expected permission elevation,
#   producing wrong results.
#
# WHAT IT CHECKS:
#   1. Tool input contains a `mode` parameter (e.g.
#      `mode: "bypassPermissions"`)
#   2. If yes, prompt acknowledges that the sub-agent's frontmatter
#      may override (e.g. "if frontmatter has permissionMode", "verify
#      the sub-agent's frontmatter", "frontmatter wins")
#   3. If yes, prompt asks for explicit verification before relying on
#      the elevated mode (e.g. "verify the mode is active", "check
#      effective permissions")
#
# OUTPUT:
#   Warning to stderr when the spawn-time mode parameter is used but
#   the prompt does not acknowledge the frontmatter override risk.
#   Always exits 0 — advisory only, never blocks.
#
# CONFIGURATION:
#   CC_SUBAGENT_MODE_REQUIRE_ALL — set to "1" to block when any check
#       fails (default: warn only)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/55691
# ================================================================

set -u

INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
MODE=$(printf '%s' "$INPUT" | jq -r '.tool_input.mode // empty' 2>/dev/null)

# If no mode parameter, no check needed
if [ -z "$MODE" ]; then
    exit 0
fi

# If mode parameter present but no prompt, warn briefly
if [ -z "$PROMPT" ]; then
    printf '⚠️  Agent tool spawn with mode=%s but empty prompt:\n' "$MODE" >&2
    printf '  - The mode parameter may be silently overridden by the sub-agent frontmatter (Issue #55691).\n' >&2
    printf '  Reference: https://github.com/anthropics/claude-code/issues/55691\n' >&2
    exit 0
fi

WARNINGS=""

# Check 1: Frontmatter override acknowledgement
if ! printf '%s' "$PROMPT" | grep -qiE 'frontmatter|permissionMode|permission mode|YAML.+(field|frontmatter)|sub[- ]?agent.+(definition|YAML)'; then
    WARNINGS="${WARNINGS}  - Mode parameter '${MODE}' set, but prompt does not acknowledge the sub-agent frontmatter override risk (Issue #55691). The mode may be silently a no-op.\n"
fi

# Check 2: Explicit verification request
if ! printf '%s' "$PROMPT" | grep -qiE 'verify (the )?mode|check (the )?(effective )?permission|verify (the )?(elevated|active)|effective permission|active mode'; then
    WARNINGS="${WARNINGS}  - Mode parameter '${MODE}' set, but prompt does not request verification of the actual effective mode. Without verification, a silent fallback to default mode passes unnoticed.\n"
fi

if [ -n "$WARNINGS" ]; then
    REQUIRE_ALL="${CC_SUBAGENT_MODE_REQUIRE_ALL:-0}"
    printf '⚠️  Subagent permission mode boundary not enforced:\n' >&2
    printf '%b' "$WARNINGS" >&2
    printf '\n  Reference: https://github.com/anthropics/claude-code/issues/55691\n' >&2
    printf '  Recommended fix: acknowledge the frontmatter override, request explicit verification of the effective mode.\n' >&2
    if [ "$REQUIRE_ALL" = "1" ]; then
        exit 2
    fi
fi

exit 0
