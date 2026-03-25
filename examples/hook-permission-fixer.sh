#!/bin/bash
# ================================================================
# hook-permission-fixer.sh — Auto-fix missing execute permissions on hooks
# ================================================================
# PURPOSE:
#   Claude Code's plugin manager and some extraction tools strip
#   execute permissions from shell scripts. This hook runs at session
#   start and ensures all .sh files in the hooks directory are executable.
#
#   Without this, hooks fail with "Permission denied" errors.
#   See: github.com/anthropics/claude-code/issues/38901
#
# TRIGGER: SessionStart  MATCHER: ""
# ================================================================

HOOKS_DIR="$HOME/.claude/hooks"
PLUGINS_DIR="$HOME/.claude/plugins"
FIXED=0

# Fix hooks directory
if [ -d "$HOOKS_DIR" ]; then
  for f in "$HOOKS_DIR"/*.sh; do
    [ -f "$f" ] || continue
    if [ ! -x "$f" ]; then
      chmod +x "$f"
      FIXED=$((FIXED + 1))
    fi
  done
fi

# Fix plugin hooks
if [ -d "$PLUGINS_DIR" ]; then
  while IFS= read -r -d '' f; do
    if [ ! -x "$f" ]; then
      chmod +x "$f"
      FIXED=$((FIXED + 1))
    fi
  done < <(find "$PLUGINS_DIR" -name "*.sh" -print0 2>/dev/null)
fi

if [ "$FIXED" -gt 0 ]; then
  echo "Fixed execute permissions on $FIXED hook script(s)" >&2
fi

exit 0
