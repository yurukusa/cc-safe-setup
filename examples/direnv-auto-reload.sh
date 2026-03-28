#!/bin/bash
# direnv-auto-reload.sh — Auto-reload environment when directory changes
#
# Uses the CwdChanged hook event (v2.1.83+) to detect directory changes
# and source .envrc/.env files for the new directory.
#
# Solves: Claude Code doesn't automatically pick up directory-specific
#         environment variables when switching between projects.
#         This can lead to using wrong API endpoints, wrong database
#         connections, or missing required env vars.
#
# TRIGGER: CwdChanged (no matcher support — fires on every cd)
#
# INPUT: {"old_cwd": "/path/from", "new_cwd": "/path/to"}
#
# DECISION CONTROL: None (notification only — shows stderr to user)

INPUT=$(cat)
NEW_CWD=$(echo "$INPUT" | jq -r '.new_cwd // empty' 2>/dev/null)
OLD_CWD=$(echo "$INPUT" | jq -r '.old_cwd // empty' 2>/dev/null)
[ -z "$NEW_CWD" ] && exit 0

# Check for .envrc (direnv)
if [ -f "${NEW_CWD}/.envrc" ]; then
    echo "📂 Directory changed: found .envrc in ${NEW_CWD}" >&2
    if command -v direnv &>/dev/null; then
        echo "  direnv: auto-allowing and loading" >&2
        cd "$NEW_CWD" && direnv allow . 2>/dev/null && eval "$(direnv export bash 2>/dev/null)"
    else
        echo "  ⚠ direnv not installed — .envrc found but not loaded" >&2
    fi
fi

# Check for .env
if [ -f "${NEW_CWD}/.env" ]; then
    echo "📂 Directory changed: .env found in ${NEW_CWD}" >&2
    echo "  Environment variables available but not auto-sourced (security)" >&2
fi

# Check for .node-version / .nvmrc
if [ -f "${NEW_CWD}/.node-version" ] || [ -f "${NEW_CWD}/.nvmrc" ]; then
    EXPECTED=$(cat "${NEW_CWD}/.node-version" 2>/dev/null || cat "${NEW_CWD}/.nvmrc" 2>/dev/null)
    CURRENT=$(node -v 2>/dev/null | sed 's/^v//')
    if [ -n "$EXPECTED" ] && [ -n "$CURRENT" ]; then
        if [ "$EXPECTED" != "$CURRENT" ]; then
            echo "⚠ Node version mismatch: expected ${EXPECTED}, running ${CURRENT}" >&2
        fi
    fi
fi

exit 0
