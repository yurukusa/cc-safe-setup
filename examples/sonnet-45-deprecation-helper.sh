#!/bin/bash
# sonnet-45-deprecation-helper.sh — Surface model lifecycle awareness when Claude.ai removes Sonnet 4.5
#
# Background:
#   In late May 2026, Anthropic removed Sonnet 4.5 (claude-sonnet-4-5-20250929) from the
#   Claude.ai chat UI dropdown, defaulting users to Sonnet 4.6. Users who relied on 4.5
#   for creative writing, instruction following, or its specific conversational tone
#   reported widespread dissatisfaction (r/ClaudeAI thread "Sonnet 4.5 is gone for me"
#   accumulated 75+ upvotes / 98+ comments; the companion thread "Sonnet 4.5 disappeared?
#   Claude 4.8 soon?" reached 41+ upvotes / 44+ comments within 24 hours).
#
#   Crucially, Sonnet 4.5 is NOT retired from the underlying APIs — it remains accessible
#   on api.anthropic.com, AWS Bedrock, and GCP Vertex for at least 12 months under
#   Anthropic's stated deprecation policy. The "disappearance" is a surface decision
#   (Claude.ai UI), not a model retirement. Claude Code users can recover 4.5 access by
#   pinning the model explicitly via the ANTHROPIC_MODEL env var or the --model flag.
#
#   Reference: https://gist.github.com/yurukusa/29d9c3ba62aa514450ba04fccc566161
#   (5 operator-side paths to keep using Sonnet 4.5)
#
# What this hook does:
#   On SessionStart, inspect ANTHROPIC_MODEL and emit a one-line advisory matching one
#   of four states:
#     - ANTHROPIC_MODEL pinned to a 4.5 variant     → silent (user has explicit pin)
#     - ANTHROPIC_MODEL pinned to a 4.6+ variant    → silent (user has explicit pin)
#     - ANTHROPIC_MODEL unset and CC_SONNET_45_HELPER_REMIND=1 → emit awareness note
#     - ANTHROPIC_MODEL unset and CC_SONNET_45_HELPER_REMIND unset → silent (default off)
#
#   The reminder is opt-in via CC_SONNET_45_HELPER_REMIND=1 to avoid noise for users
#   who don't care about model pinning. Once acknowledged, set CC_SONNET_45_HELPER_QUIET=1
#   to suppress permanently.
#
# When this hook does NOT fire a warning:
#   - CC_SONNET_45_HELPER_QUIET=1
#   - ANTHROPIC_MODEL is explicitly set to any value (treated as deliberate)
#   - CC_SONNET_45_HELPER_REMIND is unset (opt-in only)
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/sonnet-45-deprecation-helper.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_SONNET_45_HELPER_QUIET=1   — never emit anything
#   CC_SONNET_45_HELPER_REMIND=1  — emit reminder when ANTHROPIC_MODEL unset (opt-in)

# Silence path
if [ "${CC_SONNET_45_HELPER_QUIET:-0}" = "1" ]; then
  exit 0
fi

# If ANTHROPIC_MODEL is explicitly set, the user has made a deliberate choice. Stay silent.
if [ -n "${ANTHROPIC_MODEL:-}" ]; then
  exit 0
fi

# If the user did not opt in to reminders, stay silent.
if [ "${CC_SONNET_45_HELPER_REMIND:-0}" != "1" ]; then
  exit 0
fi

# Opt-in reminder path: ANTHROPIC_MODEL unset and user wants the awareness note.
cat >&2 <<'EOF'
[sonnet-45-deprecation-helper] ANTHROPIC_MODEL is unset; your session will use the default model selected by Claude Code (currently routes to Sonnet 4.6 family).

To pin Sonnet 4.5 explicitly (still available on the API for at least 12 months):
  export ANTHROPIC_MODEL=claude-sonnet-4-5-20250929

To pin Sonnet 4.6 explicitly (current default; suppresses this reminder):
  export ANTHROPIC_MODEL=claude-sonnet-4-6

To suppress this reminder without pinning:
  export CC_SONNET_45_HELPER_QUIET=1

Background: Sonnet 4.5 was removed from the Claude.ai chat UI in late May 2026 but remains
available on the Anthropic API, AWS Bedrock, and GCP Vertex AI. See:
https://gist.github.com/yurukusa/29d9c3ba62aa514450ba04fccc566161
EOF

exit 0
