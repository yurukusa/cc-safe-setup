#!/bin/bash
# ================================================================
# session-plugin-pin-watch.sh — Detect when a marketplace plugin's pinned hooks silently die
# ================================================================
# PURPOSE:
#   A running session's plugin hooks are pinned to the plugin version's
#   install path at session start. When a marketplace plugin is updated
#   mid-session, re-materialization removes that old versioned path, so the
#   pinned hook commands become unreachable and silently stop firing — no
#   error, no warning (anthropics/claude-code#73952). Recovery is
#   /reload-plugins or a restart, but nothing tells you the hooks died.
#
# HOW IT WORKS:
#   settings.json hooks are NOT plugin-pinned (they are read from
#   settings.json, which re-materialization never touches), so they keep
#   firing and can watch for the plugin-level failure. Register this one
#   script on TWO events:
#     - SessionStart: snapshot the plugin version dirs that exist now.
#     - PreToolUse:   if any snapshotted dir has since vanished, the
#                     session's pinned hooks for that plugin are dead -> warn
#                     (and suggest /reload-plugins). State is refreshed after
#                     a warning so it only re-warns on the NEXT disappearance.
#   The warning is emitted via {"systemMessage": ...} so it surfaces to the
#   user without blocking the session.
#
# TRIGGER: SessionStart, and PreToolUse
# MATCHER: PreToolUse "*" (any tool call acts as the heartbeat)
#
# CONFIGURATION:
#   CC_PLUGIN_WATCH_GLOB — glob for your plugin's versioned install dirs.
#                          Default: $HOME/.claude/plugins/*/*/* (a guess;
#                          point it at your actual cache layout).
# ================================================================
set -uo pipefail

WATCH_GLOB="${CC_PLUGIN_WATCH_GLOB:-$HOME/.claude/plugins/*/*/*}"
input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
sid=$(printf '%s' "$input" | jq -r '.session_id // "nosid"' 2>/dev/null)
state="${HOME}/.claude/plugin-pin-watch/${sid}.paths"
mkdir -p "$(dirname "$state")"

# Expand the glob and keep only directories that actually exist, one per line.
list_dirs() {
    local g="$1" p
    # shellcheck disable=SC2086
    for p in $g; do [ -d "$p" ] && printf '%s\n' "$p"; done
}

case "$event" in
    SessionStart)
        list_dirs "$WATCH_GLOB" | sort -u > "$state"
        exit 0
        ;;
    *)
        [ -f "$state" ] || exit 0
        missing=""
        while IFS= read -r d; do
            [ -n "$d" ] && [ ! -d "$d" ] && missing="${missing}\n  - ${d}"
        done < "$state"
        if [ -n "$missing" ]; then
            msg="⚠ A plugin version dir present at session start is gone. Marketplace re-materialization may have silently killed this session's pinned hooks (#73952). Run /reload-plugins to rebind, or restart. Missing:$(printf '%b' "$missing")"
            jq -cn --arg m "$msg" '{systemMessage:$m}'
            list_dirs "$WATCH_GLOB" | sort -u > "$state"
        fi
        exit 0
        ;;
esac
