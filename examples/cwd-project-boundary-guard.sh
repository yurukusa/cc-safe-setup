#!/bin/bash
# cwd-project-boundary-guard.sh — Warn when cd leaves the project directory
#
# Solves: Claude navigating to system directories or other projects
#         and making changes outside the intended scope. Especially
#         dangerous with auto-approve, where writes to /etc or
#         other projects go unchallenged.
#
# How it works: CwdChanged hook that tracks the project root and warns
#   when the working directory moves outside it.
#
# CONFIG:
#   CC_PROJECT_ROOT (auto-detected if not set)
#
# TRIGGER: CwdChanged
# MATCHER: "" (CwdChanged has no matcher support)

set -euo pipefail

INPUT=$(cat)
NEW_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$NEW_CWD" ] && exit 0

# Determine project root
PROJECT_ROOT="${CC_PROJECT_ROOT:-}"
if [ -z "$PROJECT_ROOT" ]; then
    # Auto-detect: find nearest .git directory
    PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
[ -z "$PROJECT_ROOT" ] && exit 0

# Normalize paths
PROJECT_ROOT=$(realpath "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")
NEW_CWD=$(realpath "$NEW_CWD" 2>/dev/null || echo "$NEW_CWD")

# Check if new cwd is inside project
case "$NEW_CWD" in
    "$PROJECT_ROOT"|"$PROJECT_ROOT"/*)
        # Inside project — OK
        exit 0
        ;;
    *)
        echo "WARNING: Working directory left project boundary." >&2
        echo "  Project: $PROJECT_ROOT" >&2
        echo "  New cwd: $NEW_CWD" >&2
        echo "  Changes outside the project may affect other systems." >&2
        ;;
esac

exit 0
