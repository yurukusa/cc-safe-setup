#!/bin/bash
# ================================================================
# cross-product-mcp-spawn-detector.sh — Warn when MCP server spawn
#                                       configs exist in cross-product
#                                       state paths outside Claude Code
# ================================================================
# PURPOSE:
#   On session start, scans known cross-product application-support
#   paths (where Claude Desktop or other Anthropic products store
#   plugin metadata) for .mcp.json files that contain user-blocklisted
#   plugin names. If found, warns that those MCP servers will spawn
#   on the next Claude Code session regardless of any
#   `enabledPlugins: false` or `blocklist.json` state in
#   ~/.claude/, because the spawn loader reads from the cross-product
#   path as a separate surface.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# WHY THIS MATTERS:
#   Issue #58806 documented a case where a user disabled a plugin
#   ("nimble") via every config knob Claude Code exposes — disabling
#   it in settings, removing it from installed_plugins.json, adding it
#   to blocklist.json, removing its cache directory — and the plugin
#   kept spawning its MCP server (and opening OAuth tabs in the
#   browser) on every session start.
#
#   Root cause: Claude Desktop's RPM plugin install path
#     ~/Library/Application Support/Claude/local-agent-mode-sessions/
#       <session-uuid-1>/<session-uuid-2>/rpm/plugin_<ULID>/.mcp.json
#   is read by Claude Code as a separate spawn surface, and none of
#   the ~/.claude/ config knobs gate that read. The user only found
#   the path after three sessions of manual investigation.
#
#   This is a structurally different problem from a single-loader
#   gate bug: it is a cross-product state leakage where one product's
#   state files affect another product's runtime spawn decisions. The
#   underlying fix has to come from Anthropic (unify plugin state, or
#   make `claude-code mcp list` reflect the full source-path set).
#   Until then, the operator-side mitigation is to detect the
#   presence of blocklisted plugin spawn configs before the session
#   starts using them.
#
#   This hook does that detection. A one-shot `find … rm` is
#   point-in-time and gets defeated the next time Claude Desktop
#   recreates the session directory under a fresh UUID. Running the
#   same scan at every Claude Code SessionStart closes the recurrence
#   window.
#
# WHAT IT CHECKS:
#   For each path in the candidate cross-product roots
#   (macOS / Linux / Windows-via-WSL), if the path exists, finds all
#   .mcp.json files and greps for any plugin name in the user's
#   blocklist (configured via CC_CROSS_PRODUCT_BLOCKLIST, comma- or
#   newline-separated). Reports every match.
#
# OUTPUT:
#   For each match: the blocked plugin name and the .mcp.json path
#   that will spawn it. Exits 0 by default (advisory). If
#   CC_CROSS_PRODUCT_REQUIRE_CLEAN=1 is set, exits 2 to block the
#   session until the operator removes the stale spawn config.
#
# CONFIGURATION:
#   CC_CROSS_PRODUCT_BLOCKLIST
#     Comma- or newline-separated plugin name fragments to match
#     against .mcp.json contents. Empty (the default) means the hook
#     skips entirely — opt-in only, so installations without a
#     blocklist incur no startup cost or false positives.
#     Example: CC_CROSS_PRODUCT_BLOCKLIST="nimble,wix,serena"
#
#   CC_CROSS_PRODUCT_REQUIRE_CLEAN
#     Set to "1" to exit 2 (block) when any match is found. Default
#     is exit 0 (advisory).
#
#   CC_CROSS_PRODUCT_EXTRA_ROOTS
#     Newline-separated extra paths to scan in addition to the
#     built-in macOS / Linux / WSL candidates. Useful for non-default
#     install locations.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/58806
#   https://github.com/anthropics/claude-code/issues/58520
# ================================================================

set -u

BLOCKLIST_RAW="${CC_CROSS_PRODUCT_BLOCKLIST:-}"
if [ -z "$BLOCKLIST_RAW" ]; then
    # Opt-in: no blocklist configured, skip silently.
    exit 0
fi

# Normalize blocklist: replace commas and whitespace runs with newlines, drop empties.
BLOCKLIST=$(printf '%s' "$BLOCKLIST_RAW" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' || true)
if [ -z "$BLOCKLIST" ]; then
    exit 0
fi

# Build candidate cross-product roots.
CANDIDATE_ROOTS=""
add_root() {
    [ -n "$1" ] || return 0
    CANDIDATE_ROOTS="${CANDIDATE_ROOTS}${1}
"
}

# macOS: Claude Desktop application-support tree.
add_root "$HOME/Library/Application Support/Claude/local-agent-mode-sessions"
add_root "$HOME/Library/Application Support/Claude/plugins"

# Linux: XDG config / data trees.
add_root "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/local-agent-mode-sessions"
add_root "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/plugins"
add_root "${XDG_DATA_HOME:-$HOME/.local/share}/Claude/local-agent-mode-sessions"
add_root "${XDG_DATA_HOME:-$HOME/.local/share}/Claude/plugins"

# Windows via WSL: APPDATA / LOCALAPPDATA exposed through /mnt/c.
if [ -n "${APPDATA:-}" ]; then
    add_root "$APPDATA/Claude/local-agent-mode-sessions"
    add_root "$APPDATA/Claude/plugins"
fi
if [ -n "${LOCALAPPDATA:-}" ]; then
    add_root "$LOCALAPPDATA/Claude/local-agent-mode-sessions"
    add_root "$LOCALAPPDATA/Claude/plugins"
fi

# Operator-specified extras.
if [ -n "${CC_CROSS_PRODUCT_EXTRA_ROOTS:-}" ]; then
    while IFS= read -r extra; do
        add_root "$extra"
    done <<EOF
${CC_CROSS_PRODUCT_EXTRA_ROOTS}
EOF
fi

# Scan each existing root for .mcp.json files containing any blocked name.
MATCHES=""
while IFS= read -r root; do
    [ -n "$root" ] || continue
    [ -d "$root" ] || continue

    # Iterate every .mcp.json under this root.
    while IFS= read -r -d '' mcpfile; do
        # Iterate every blocked name.
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            if grep -qF -- "$name" "$mcpfile" 2>/dev/null; then
                MATCHES="${MATCHES}  - blocked plugin '${name}' is spawnable from: ${mcpfile}
"
            fi
        done <<EOF
${BLOCKLIST}
EOF
    done < <(find "$root" -type f -name '.mcp.json' -print0 2>/dev/null)
done <<EOF
${CANDIDATE_ROOTS}
EOF

if [ -n "$MATCHES" ]; then
    printf '⚠️  Cross-product MCP spawn config detected (Issue #58806):\n' >&2
    printf '%s' "$MATCHES" >&2
    printf '\n  These files live outside ~/.claude/ and are read by Claude Code as a\n' >&2
    printf '  separate spawn surface. Disabling the plugin via enabledPlugins / blocklist /\n' >&2
    printf '  installed_plugins.json in ~/.claude/ will NOT prevent the next session from\n' >&2
    printf '  spawning the MCP server from the path above.\n' >&2
    printf '\n  Mitigations:\n' >&2
    printf '    1. Remove the .mcp.json (or the enclosing plugin_ directory) listed above.\n' >&2
    printf '    2. Set MCP_REMOTE_NO_OPEN=1 in this shell to neutralize browser-open behavior\n' >&2
    printf '       if removal is not yet possible.\n' >&2
    printf '    3. Add a PreToolUse hook matching mcp__<plugin-prefix>* to refuse calls.\n' >&2
    printf '\n  Reference: https://github.com/anthropics/claude-code/issues/58806\n' >&2

    if [ "${CC_CROSS_PRODUCT_REQUIRE_CLEAN:-0}" = "1" ]; then
        exit 2
    fi
fi

exit 0
