#!/bin/bash
# disabled-plugin-spawn-detector.sh — Warn when a plugin marked enabledPlugins:false
# still has a reachable .mcp.json spawn config in any Claude path.
#
# Solves: Two confirmed code paths silently ignore enabledPlugins:false:
#   #58520 — VSCode extension keeps registering hooks from disabled plugins
#   #58806 — Claude Code spawns MCP servers from Claude Desktop's
#            local-agent-mode-sessions RPM path, bypassing every Claude Code
#            config knob. User in #58806 accumulated 22 OAuth tabs over weeks
#            after nine separate cleanup steps all failed because the spawn
#            command lived outside the Claude Code config surface.
#
# Both confirmed sites mean the disable list is not consulted at the loader
# layer — the gate has to be enforced from outside the Claude Code config
# surface, because that surface is the bypassed thing.
#
# How it works:
#   On SessionStart, parse ~/.claude/settings.json for plugins where
#   enabledPlugins[name] == false, then grep for the plugin name inside
#   .mcp.json files across the Claude Code and Claude Desktop spawn paths.
#   If a match is found, print a warning listing each surviving path.
#
#   Default behavior: advisory (exit 0). Set CC_DPSD_BLOCK=1 to fail the
#   session start (exit 2) when a disabled plugin's spawn config survives.
#   Set CC_DPSD_ALLOW=1 to suppress the check entirely.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/disabled-plugin-spawn-detector.sh" }]
#     }]
#   }
# }

[ "${CC_DPSD_ALLOW:-0}" = "1" ] && exit 0

SETTINGS="${CC_DPSD_SETTINGS:-$HOME/.claude/settings.json}"
[ -f "$SETTINGS" ] || exit 0

# Extract disabled plugin names. Prefer jq when available; fall back to a
# narrow grep+sed parse that handles the common one-line "name": false form.
extract_disabled() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.enabledPlugins // {} | to_entries[] | select(.value == false) | .key' \
            "$SETTINGS" 2>/dev/null
        return
    fi
    # jq-less fallback: only recognises lines like  "foo@bar": false
    # Multi-line value forms will be missed; that is acceptable for an
    # advisory hook running before jq is installed.
    grep -oE '"[^"]+"[[:space:]]*:[[:space:]]*false' "$SETTINGS" 2>/dev/null \
        | sed -E 's/^"([^"]+)".*/\1/'
}

DISABLED=$(extract_disabled)
[ -z "$DISABLED" ] && exit 0

# Spawn paths to scan. Each entry is a directory; the hook silently skips
# any that do not exist on the current host.
SCAN_PATHS=(
    "$HOME/.claude/plugins"
    "$HOME/Library/Application Support/Claude/local-agent-mode-sessions"
    "$HOME/.config/Claude/local-agent-mode-sessions"
    "$HOME/.config/Claude/plugins"
)
# Allow extra paths via env var (colon-separated, like PATH).
if [ -n "${CC_DPSD_EXTRA_PATHS:-}" ]; then
    IFS=':' read -r -a EXTRA <<< "$CC_DPSD_EXTRA_PATHS"
    SCAN_PATHS+=("${EXTRA[@]}")
fi

# Strip the marketplace suffix from a plugin id so we match on the plugin
# package name. "nimble@claude-plugins-official" -> "nimble".
plugin_base() {
    printf '%s\n' "$1" | sed -E 's/@.*$//'
}

WARNINGS=0
WARN_OUT=""
while IFS= read -r plugin_id; do
    [ -z "$plugin_id" ] && continue
    base=$(plugin_base "$plugin_id")
    # Escape regex metacharacters so a plugin name like "foo.bar" matches
    # literally rather than as a regex.
    escaped=$(printf '%s\n' "$base" | sed -E 's/[][\/.^$*?+(){}|]/\\&/g')
    for dir in "${SCAN_PATHS[@]}"; do
        [ -d "$dir" ] || continue
        # find -L follows symlinks for hosts where the App Support path is
        # a symlink (rare but seen). -name ".mcp.json" matches both top-level
        # and nested plugin configs.
        matches=$(find -L "$dir" -name ".mcp.json" \
                    -exec grep -lE "$escaped" {} \; 2>/dev/null)
        if [ -n "$matches" ]; then
            while IFS= read -r m; do
                [ -z "$m" ] && continue
                WARN_OUT+="  $plugin_id  →  $m"$'\n'
                WARNINGS=$((WARNINGS + 1))
            done <<< "$matches"
        fi
    done
done <<< "$DISABLED"

if [ "$WARNINGS" -gt 0 ]; then
    {
        echo "⚠ disabled-plugin-spawn-detector: $WARNINGS surviving spawn config(s):"
        printf '%s' "$WARN_OUT"
        echo "  These plugins are marked enabledPlugins:false in $SETTINGS,"
        echo "  but their .mcp.json files remain reachable. Two confirmed code"
        echo "  paths (#58520 hooks, #58806 MCP spawn) ignore the disable list."
        echo "  Remove the matching directories, or set CC_DPSD_ALLOW=1 to skip."
    } >&2
    [ "${CC_DPSD_BLOCK:-0}" = "1" ] && exit 2
fi

exit 0
