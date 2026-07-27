#!/bin/bash
# ================================================================
# subagent-spawn-verification-enforcer.sh — Warn when subagent prompt
#                                            lacks output verification
# ================================================================
# PURPOSE:
#   When the main agent spawns a subagent via the Agent tool, checks
#   whether the delegation prompt names a concrete artifact the
#   subagent must produce (file path, commit hash, process id, etc.)
#   and whether the parent will verify that artifact with a read-only
#   inspection. Warns when the contract is missing — the parent will
#   then accept any "spawned successfully" reply at face value.
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"
#
# WHY THIS MATTERS:
#   Issue #55666 reported that named Agent spawns under
#   CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 reply "Spawned successfully.
#   The agent is now running." while no actual process is created. The
#   inbox is set up but the work never runs. Without an artifact-based
#   verification step in the parent, the parent trusts the textual
#   "success" reply and proceeds — silently dropping the requested work.
#
#   The root cause must be fixed in the runtime, but parent agents can
#   preventively catch this class of failure by (1) requiring the
#   subagent to produce a concrete artifact (file write / commit / log
#   line / stdout marker) and (2) verifying that artifact exists before
#   trusting the success reply.
#
# WHAT IT CHECKS:
#   1. Prompt names a concrete artifact (e.g. "write to /tmp/X",
#      "create file at", "commit with message", "produce output line",
#      "log to")
#   2. Prompt includes a verification step (e.g. "verify by", "check
#      that the file exists", "read back", "parent will inspect")
#   3. Prompt warns against trusting textual success without artifact
#      (optional, recommended for high-stakes delegation)
#
# OUTPUT:
#   Warning to stderr listing which artifact / verification instructions
#   are missing. Always exits 0 — advisory only, never blocks.
#
# CONFIGURATION:
#   CC_SUBAGENT_VERIFY_REQUIRE_ALL — set to "1" to block when any check
#       fails (default: warn only)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/55666
# ================================================================

set -u

INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)

if [ -z "$PROMPT" ]; then
    exit 0
fi

WARNINGS=""

# Check 1: Concrete artifact named (file path, commit, marker, etc.)
if ! printf '%s' "$PROMPT" | grep -qiE 'write (to |the )?[/~]|create (a )?file|commit (with|the)|produce (an? )?output|log (to|the)|/tmp/|/var/|\.txt|\.md|\.json|\.log'; then
    WARNINGS="${WARNINGS}  - No concrete artifact named. Subagent's textual 'success' reply is unverifiable (Issue #55666 surface).\n"
fi

# Check 2: Verification step named
if ! printf '%s' "$PROMPT" | grep -qiE 'verify (by|with|that|the)|check (that|the file|the artifact|exists|after)|read back|parent (will|should) (inspect|verify|check)|i will (check|verify|inspect)'; then
    WARNINGS="${WARNINGS}  - No artifact verification step. Without read-only inspection, fabricated success replies are silently trusted.\n"
fi

# Check 3: Distrust of textual success (warning, not strictly required)
if ! printf '%s' "$PROMPT" | grep -qiE 'do not trust|do not (rely on|believe|reply)|require (the|an) artifact|artifact[- ]based|reply[- ]only|without producing'; then
    WARNINGS="${WARNINGS}  - Recommended: prompt does not warn the subagent against 'reply-only' success. Adding 'do not reply success without producing the artifact' reduces fabrication risk.\n"
fi

if [ -n "$WARNINGS" ]; then
    REQUIRE_ALL="${CC_SUBAGENT_VERIFY_REQUIRE_ALL:-0}"
    printf '⚠️  Subagent output verification not enforced in delegation prompt:\n' >&2
    printf '%b' "$WARNINGS" >&2
    printf '\n  Reference: https://github.com/anthropics/claude-code/issues/55666\n' >&2
    printf '  Recommended fix: name a concrete artifact, name parent verification step, warn the subagent against reply-only success.\n' >&2
    if [ "$REQUIRE_ALL" = "1" ]; then
        exit 2
    fi
fi

exit 0
