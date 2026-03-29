#!/bin/bash
# ================================================================
# monorepo-scope-guard.sh — Restrict edits to the current package
# in a monorepo
#
# Solves: Claude editing files in sibling packages when working on
# a specific package in a monorepo. Cross-package edits without
# understanding dependencies can break builds.
#
# Detects monorepo root (packages/, apps/, libs/) and warns when
# editing outside the current working package.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Edit|Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/monorepo-scope-guard.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0

# Detect monorepo structure
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[[ -z "$REPO_ROOT" ]] && exit 0

# Check for common monorepo patterns
MONOREPO_DIRS=""
for dir in packages apps libs modules services; do
    [[ -d "$REPO_ROOT/$dir" ]] && MONOREPO_DIRS="$MONOREPO_DIRS $dir"
done

[[ -z "$MONOREPO_DIRS" ]] && exit 0

# Determine current package from CWD
CWD=$(pwd)
CURRENT_PKG=""
for dir in $MONOREPO_DIRS; do
    if [[ "$CWD" == "$REPO_ROOT/$dir/"* ]]; then
        CURRENT_PKG=$(echo "$CWD" | sed "s|$REPO_ROOT/$dir/||" | cut -d/ -f1)
        CURRENT_DIR="$dir"
        break
    fi
done

[[ -z "$CURRENT_PKG" ]] && exit 0

# Check if the file being edited is in a different package
FILE_ABS=$(realpath "$FILE" 2>/dev/null || echo "$FILE")
for dir in $MONOREPO_DIRS; do
    if [[ "$FILE_ABS" == "$REPO_ROOT/$dir/"* ]]; then
        FILE_PKG=$(echo "$FILE_ABS" | sed "s|$REPO_ROOT/$dir/||" | cut -d/ -f1)
        if [[ "$FILE_PKG" != "$CURRENT_PKG" ]] || [[ "$dir" != "$CURRENT_DIR" ]]; then
            echo "WARNING: Cross-package edit detected in monorepo." >&2
            echo "Current package: $CURRENT_DIR/$CURRENT_PKG" >&2
            echo "Editing: $dir/$FILE_PKG/$(basename "$FILE")" >&2
            echo "Cross-package changes may break sibling builds." >&2
        fi
        break
    fi
done

exit 0
