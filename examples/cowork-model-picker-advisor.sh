#!/bin/bash
# cowork-model-picker-advisor.sh — Surface the Cowork Sonnet 4.6 [1m] silent
# default at SessionStart so CLI users do not accidentally burn usage credits
#
# Solves: #62949 — Claude Cowork Desktop only presents a single Sonnet 4.6
#         option in the model picker. It silently defaults to the 1M context
#         variant, which requires usage credits even on a fresh session at
#         low plan usage on Max (5x). The documented behavior — separate
#         `sonnet` and `sonnet[1m]` entries — is missing in Cowork. CLI
#         users can use `--model` to force standard 200K context; Cowork
#         users have no workaround until the picker is fixed. Related:
#         #61869, #62100, #61692.
#
# WHO THIS PROTECTS:
#   CLI users who:
#     - leave ANTHROPIC_MODEL unset and may inherit the same silent 1M
#       default Cowork enforces;
#     - explicitly set ANTHROPIC_MODEL to a 1m variant and want a reminder
#       that this consumes usage credits separately from the plan;
#     - also use Cowork on the same machine and benefit from a clear
#       articulation of the picker bug + the CLI-only workaround.
#
# HOW IT WORKS:
#   On SessionStart:
#     1. Check $ANTHROPIC_MODEL.
#     2. If unset or contains "1m" / "[1m]" / "1M", print stderr block:
#          - explains #62949 and the silent 1M default
#          - explains how to force standard 200K context via --model
#          - links related issues
#     3. If set to a non-1m model, print a one-line confirmation (suppressible
#        with CC_COWORK_MODEL_QUIET=1).
#   Always exit 0 (advisory).
#
# TRIGGER: SessionStart  MATCHER: ""
#
# CONFIGURATION:
#   CC_COWORK_MODEL_QUIET=1       suppress the confirmation line for safe models
#   CC_COWORK_MODEL_LOG=path      append model-check events (default off)
#   CC_COWORK_MODEL_FORCE_WARN=1  always show the full warning regardless of env
#
# USAGE:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/cowork-model-picker-advisor.sh"
#       }]
#     }]
#   }
# }

INPUT=$(cat 2>/dev/null || true)

MODEL="${ANTHROPIC_MODEL:-}"

is_1m_variant=0
if [ -z "$MODEL" ]; then
    is_1m_variant=1  # unset means we may inherit Cowork's silent 1M default
elif echo "$MODEL" | grep -qiE '(\[1m\]|-1m|_1m|1m$|1M)'; then
    is_1m_variant=1
fi

if [ -n "${CC_COWORK_MODEL_FORCE_WARN:-}" ]; then
    is_1m_variant=1
fi

if [ "$is_1m_variant" -eq 1 ]; then
    cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[cowork-model-picker-advisor] SessionStart — model exposure check
ANTHROPIC_MODEL='${MODEL:-(unset)}'

Addresses #62949: Claude Cowork Desktop silently defaults to Sonnet 4.6
[1m] (1M context). The picker shows only one Sonnet 4.6 option; the
standard 200K context variant is NOT selectable. The 1M variant requires
usage credits separately from Max-plan inclusion, so a Cowork session
at ~9% plan usage can still trip:

  API Error: Usage credits required for 1M context

CLI workaround (Cowork has none until the picker is fixed):
  --model claude-sonnet-4-6      # forces standard 200K context
  --model claude-haiku-4-5       # smaller, plan-included
  Or: export ANTHROPIC_MODEL=claude-sonnet-4-6 in your shell init.

Related issues: #61869 #62100 #61692
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
else
    if [ -z "${CC_COWORK_MODEL_QUIET:-}" ]; then
        echo "[cowork-model-picker-advisor] ANTHROPIC_MODEL=${MODEL} — standard context, not 1m. No usage-credit risk from #62949." >&2
    fi
fi

if [ -n "${CC_COWORK_MODEL_LOG:-}" ]; then
    mkdir -p "$(dirname "$CC_COWORK_MODEL_LOG")" 2>/dev/null
    echo "$(date -Iseconds) model=${MODEL:-unset} is_1m=${is_1m_variant}" >> "$CC_COWORK_MODEL_LOG"
fi

exit 0
