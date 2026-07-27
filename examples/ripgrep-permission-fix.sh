#!/bin/bash
# ================================================================
# ripgrep-permission-fix.sh — Auto-fix ripgrep execute permission on start
# ================================================================
# PURPOSE:
#   After Claude Code upgrades, the vendored ripgrep binary
#   sometimes loses its execute permission (installed as 644
#   instead of 755). This silently breaks custom commands,
#   skills discovery, and file search. This hook auto-fixes
#   the permission on every session start.
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# WHY THIS MATTERS:
#   Claude Code uses ripgrep internally to scan .claude/commands/
#   and .claude/skills/ for .md files. Without execute permission,
#   it silently returns empty results, making all custom commands
#   and skills invisible. Multiple users hit this on v2.1.88/89.
#
# WHAT IT DOES:
#   Finds the vendored ripgrep binary and adds +x if missing.
#   No-op if ripgrep already has execute permission.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/41933
#   https://github.com/anthropics/claude-code/issues/41882
#   https://github.com/anthropics/claude-code/issues/41243
# ================================================================

# Find the Claude Code installation directory
CLAUDE_BIN=$(command -v claude 2>/dev/null)
[ -z "$CLAUDE_BIN" ] && exit 0

# Resolve symlinks to find the actual installation
CLAUDE_REAL=$(readlink -f "$CLAUDE_BIN" 2>/dev/null || realpath "$CLAUDE_BIN" 2>/dev/null)
[ -z "$CLAUDE_REAL" ] && exit 0

CLAUDE_DIR=$(dirname "$CLAUDE_REAL")

# Search for vendored ripgrep
for rg_path in \
    "${CLAUDE_DIR}/../vendor/ripgrep/"*/rg \
    "${CLAUDE_DIR}/../lib/node_modules/@anthropic-ai/claude-code/vendor/ripgrep/"*/rg \
    "$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/vendor/ripgrep/"*/rg; do

    # Expand glob
    for rg in $rg_path; do
        [ -f "$rg" ] || continue

        if [ ! -x "$rg" ]; then
            chmod +x "$rg" 2>/dev/null
            printf 'Fixed ripgrep permission: %s\n' "$rg" >&2
        fi
    done
done

exit 0
