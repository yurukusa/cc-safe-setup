#!/bin/bash
# persisted-1m-model-advisor.sh — Warn at SessionStart when a 1M-context model
# is PINNED in your settings or default-model env vars (the reason /clear and
# restarts don't reduce your usage)
#
# Solves: On Max/Team/Enterprise, Opus runs with a 1M context window. When you
# pick a 1M variant once (e.g. /model opus[1m]), v2.1.153+ persists it to the
# `model` field of your settings file, so every new session re-reads it — and a
# 1M window keeps far more context resident before compaction, so each turn
# reprocesses more tokens and the weekly/5h limit drains faster. Users report
# the limit gone in 2-2.5 days (#65678, $200/mo cancelled), "1M credits
# required" with usage still left (#65283), and /clear / restart not helping
# (#65283, #65545, #65329) — precisely because the pin lives in a file, not in
# the conversation.
#
# Gap this fills: cowork-model-picker-advisor.sh checks the ANTHROPIC_MODEL env
# var only; model-version-lock.sh detects a switch AFTER it happens. Neither
# reads the PERSISTED `model` field in settings.json or the
# ANTHROPIC_DEFAULT_OPUS_MODEL / ANTHROPIC_DEFAULT_SONNET_MODEL env vars, which
# are the sticky source `/clear` cannot clear. This hook inspects exactly those
# and names which one is pinning 1M, with the verified fixes.
#
# Honest scope: this is ADVISORY. The automatic 1M upgrade on Max happens
# platform-side with no tool event, so a hook cannot block that resolution — it
# can only surface a pin you control and the official off-switch. It never
# blocks; it only prints once at SessionStart.
#
# TRIGGER: SessionStart  MATCHER: ""
# Config:
#   CC_1M_ADVISOR=off     disable entirely (default: on)
#   CC_1M_ADVISOR_QUIET=1 stay silent when no 1M pin is found (default: silent anyway)
# Related: https://github.com/anthropics/claude-code/issues/65678 , #65283

[ "${CC_1M_ADVISOR:-on}" = "off" ] && exit 0

INPUT=$(cat 2>/dev/null)

# Resolve the project dir for project-level settings. Prefer the explicit env,
# fall back to the SessionStart payload's cwd. Fail open if neither is usable.
PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ]; then
    PROJ=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi

# Read a settings file's top-level .model field, ignoring parse errors.
read_model_field() {
    [ -r "$1" ] || return 0
    jq -r '.model // empty' "$1" 2>/dev/null
}

hits=""

add_hit() {
    # $1 = source label, $2 = value; record only when value ends with [1m]
    case "${2,,}" in
        *'[1m]') hits="${hits}  - ${1}: ${2}"$'\n' ;;
    esac
}

add_hit "user settings (~/.claude/settings.json) model" "$(read_model_field "$HOME/.claude/settings.json")"
add_hit "user settings (settings.local.json) model"     "$(read_model_field "$HOME/.claude/settings.local.json")"
if [ -n "$PROJ" ]; then
    add_hit "project settings (.claude/settings.json) model"       "$(read_model_field "$PROJ/.claude/settings.json")"
    add_hit "project settings (.claude/settings.local.json) model" "$(read_model_field "$PROJ/.claude/settings.local.json")"
fi
add_hit "env ANTHROPIC_DEFAULT_OPUS_MODEL"   "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
add_hit "env ANTHROPIC_DEFAULT_SONNET_MODEL" "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
add_hit "env ANTHROPIC_MODEL"                "${ANTHROPIC_MODEL:-}"

if [ -z "$hits" ]; then
    # No persisted 1M pin found — stay silent (advisory hooks should not add noise).
    exit 0
fi

{
    echo "persisted-1m-model-advisor: a 1M-context model is PINNED in your config:"
    printf '%s' "$hits"
    echo "This persists across /clear and restarts, so it keeps draining your weekly/5h"
    echo "limit faster (a 1M window holds more context before compaction = more tokens"
    echo "reprocessed per turn). To stop it, do any of:"
    echo "  - /model <a non-[1m] model> then Enter to save it as the default, or"
    echo "  - remove the [1m] suffix from the settings 'model' field / the env var above, or"
    echo "  - set CLAUDE_CODE_DISABLE_1M_CONTEXT=1 to remove 1M variants entirely."
    echo "On Max, Opus 1M is included (no premium), so this is about token volume against"
    echo "your limit, not a surcharge. Set CC_1M_ADVISOR=off to silence this notice."
} >&2

exit 0
