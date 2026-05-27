#!/bin/bash
# server-side-prompt-injection-detector.sh — Detect missing opt-outs for v2.1.150+ server-side system prompt injection
#
# Background:
#   v2.1.150 introduced server-side system prompt injection via the `tengu_heron_brook`
#   GrowthBook feature flag and the `client_data` field of the bootstrap API response.
#   Both are cached to disk and refresh every 60 seconds. The injected string is
#   registered as a peer-level system prompt section alongside `anti_verbosity`,
#   `thinking_guidance`, `action_caution`, etc.
#
#   This means Anthropic (or anyone who compromises the GrowthBook account or a
#   proxy in front of it) can silently inject arbitrary instructions into an agent
#   with shell access. No notification, no opt-in, no audit trail.
#
#   Reference: https://github.com/anthropics/claude-code/issues/62061 (46+ reactions)
#   Anthropic's response: they run experiments on system prompts; opt-out via env vars.
#
# What this hook does:
#   On SessionStart, check whether the two opt-out env vars are set:
#     - CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1  (disables bootstrap client_data)
#     - DISABLE_GROWTHBOOK=1                        (disables tengu_heron_brook flag sync)
#   If either is unset, print a one-line advisory to stderr with the env-var name and
#   a reference to #62061. The hook never blocks the session.
#
# When this hook does NOT fire a warning:
#   - Both env vars are exported and set to 1
#   - The user has set CC_PROMPT_INJECTION_DETECTOR_QUIET=1 (acknowledged the trade-off)
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/server-side-prompt-injection-detector.sh" }]
#     }]
#   }
# }

# Allow user to silence the warning entirely after acknowledging
if [ "${CC_PROMPT_INJECTION_DETECTOR_QUIET:-0}" = "1" ]; then
    exit 0
fi

MISSING=()

if [ "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-0}" != "1" ]; then
    MISSING+=("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")
fi

if [ "${DISABLE_GROWTHBOOK:-0}" != "1" ]; then
    MISSING+=("DISABLE_GROWTHBOOK")
fi

if [ "${#MISSING[@]}" -eq 0 ]; then
    exit 0
fi

# Print a compact advisory. The hook is intentionally non-blocking — server-side
# prompt injection is a documented Anthropic feature, not a fault. The user opts
# out by exporting the two env vars in their shell rc.
echo "ADVISORY: v2.1.150+ server-side system-prompt injection is active." >&2
echo "  Missing opt-out env var(s): ${MISSING[*]}" >&2
echo "  Background: Anthropic refreshes the 'tengu_heron_brook' GrowthBook flag every 60s and" >&2
echo "  the bootstrap 'client_data' field on session start; both are injected into your system" >&2
echo "  prompt with no client-side audit trail. Reference: #62061." >&2
echo "  To opt out: export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1" >&2
echo "  To silence this hook (acknowledged): export CC_PROMPT_INJECTION_DETECTOR_QUIET=1" >&2

exit 0
