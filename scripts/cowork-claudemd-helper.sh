#!/bin/bash
# ================================================================
# cowork-claudemd-helper.sh — Workaround for Cowork sessions not
#   loading ~/.claude/CLAUDE.md at session start
# ================================================================
# PURPOSE:
#   Issue #62859 reports that Cowork (the Claude desktop app's
#   sandboxed remote-control session) does not load
#   ~/.claude/CLAUDE.md or any project-scoped CLAUDE.md at
#   session start. The user-side workaround documented in the
#   issue is to manually paste the contents into the first chat
#   message. This script prints those contents pre-formatted for
#   paste, so the workaround takes one command instead of
#   navigating files in a terminal.
#
#   Cluster 11 (Cowork) in the cc-safe-setup tracker. Hooks do
#   not fire in Cowork's GUI sandbox, so this is a standalone
#   script rather than a hook.
#
# UPSTREAM REFERENCES:
#   #62859 (Cowork does not load ~/.claude/CLAUDE.md at session
#           start) — 2026-05-27
#
# USAGE:
#   bash scripts/cowork-claudemd-helper.sh           # print to stdout
#   bash scripts/cowork-claudemd-helper.sh --copy    # also copy to clipboard
#   bash scripts/cowork-claudemd-helper.sh --paths   # list files that would be included
#   bash scripts/cowork-claudemd-helper.sh PROJECT   # include PROJECT/.claude/CLAUDE.md too
#
# BEHAVIOR:
#   - Reads ~/.claude/CLAUDE.md if present.
#   - Optionally reads $1/.claude/CLAUDE.md when a project path is given.
#   - Prints both with section headers Cowork's chat can render.
#   - Exits 0 with informational stderr when nothing is found
#     (not an error — many operators don't use user-scoped CLAUDE.md).
#   - --copy uses pbcopy (macOS), xclip (Linux), or wl-copy (Wayland),
#     whichever is available. Silent fallback to stdout if none.
#
# CONFIGURATION (env vars):
#   CC_COWORK_HELPER_USER_PATH    Override ~/.claude/CLAUDE.md path
#                                 (used by tests).
#   CC_COWORK_HELPER_HEADER       Prefix string for the pasted block
#                                 (default: "Standing instructions from CLAUDE.md:")
# ================================================================

set -u

USER_PATH="${CC_COWORK_HELPER_USER_PATH:-$HOME/.claude/CLAUDE.md}"
HEADER="${CC_COWORK_HELPER_HEADER:-Standing instructions from CLAUDE.md:}"

COPY=0
LIST_PATHS=0
PROJECT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --copy) COPY=1; shift ;;
        --paths) LIST_PATHS=1; shift ;;
        -h|--help)
            sed -n '2,46p' "$0" | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *) PROJECT="$1"; shift ;;
    esac
done

USER_EXISTS=0
PROJECT_EXISTS=0
PROJECT_PATH=""

if [ -f "$USER_PATH" ] && [ -r "$USER_PATH" ]; then
    USER_EXISTS=1
fi

if [ -n "$PROJECT" ]; then
    PROJECT_PATH="${PROJECT%/}/.claude/CLAUDE.md"
    if [ -f "$PROJECT_PATH" ] && [ -r "$PROJECT_PATH" ]; then
        PROJECT_EXISTS=1
    fi
fi

if [ "$LIST_PATHS" = "1" ]; then
    if [ "$USER_EXISTS" = "1" ]; then
        echo "$USER_PATH"
    fi
    if [ "$PROJECT_EXISTS" = "1" ]; then
        echo "$PROJECT_PATH"
    fi
    exit 0
fi

if [ "$USER_EXISTS" = "0" ] && [ "$PROJECT_EXISTS" = "0" ]; then
    echo "cowork-claudemd-helper: no CLAUDE.md found at $USER_PATH${PROJECT:+ or $PROJECT_PATH}." >&2
    echo "cowork-claudemd-helper: create $USER_PATH with your standing instructions, then re-run." >&2
    exit 0
fi

build_output() {
    echo "$HEADER"
    echo ""
    if [ "$USER_EXISTS" = "1" ]; then
        echo "## User-scoped ($USER_PATH)"
        echo ""
        cat "$USER_PATH"
        echo ""
    fi
    if [ "$PROJECT_EXISTS" = "1" ]; then
        echo "## Project-scoped ($PROJECT_PATH)"
        echo ""
        cat "$PROJECT_PATH"
        echo ""
    fi
    echo "(Pasted as Cowork workaround for issue #62859 — Cowork does not auto-load CLAUDE.md.)"
}

OUTPUT=$(build_output)

if [ "$COPY" = "1" ]; then
    if command -v pbcopy >/dev/null 2>&1; then
        printf '%s\n' "$OUTPUT" | pbcopy
        echo "cowork-claudemd-helper: copied to clipboard via pbcopy." >&2
    elif command -v wl-copy >/dev/null 2>&1; then
        printf '%s\n' "$OUTPUT" | wl-copy
        echo "cowork-claudemd-helper: copied to clipboard via wl-copy." >&2
    elif command -v xclip >/dev/null 2>&1; then
        printf '%s\n' "$OUTPUT" | xclip -selection clipboard
        echo "cowork-claudemd-helper: copied to clipboard via xclip." >&2
    else
        echo "cowork-claudemd-helper: no clipboard tool found (pbcopy/wl-copy/xclip). Falling back to stdout." >&2
        printf '%s\n' "$OUTPUT"
    fi
else
    printf '%s\n' "$OUTPUT"
fi

exit 0
