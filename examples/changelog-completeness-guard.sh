#!/bin/bash
# ================================================================
# changelog-completeness-guard.sh — Refuse writes to CHANGELOG/WIP/TODO
# unless the session has recently consulted git log or gh issue list.
# ================================================================
# PROBLEM (anthropics/claude-code#58715, May 13 2026):
#   When asked to "update CHANGELOG and WIP", Claude adds only the changes
#   from the current session — silently skipping ~10 real commits, leaving
#   already-completed issues in the priority queue, and reporting the work
#   as done. The user has to point out the gap twice before the correct
#   behavior fires.
#
#   The root cause is that the model treats the write as a content-emission
#   task rather than an enumerate-and-summarize task. The fix is at the
#   pre-write boundary: refuse the write unless evidence of enumeration
#   (git log / gh issue list) appears earlier in the session.
#
# HOW IT WORKS:
#   PreToolUse hook (matcher: empty, fires on every tool call).
#
#   On Bash tool calls: if the command contains `git log` with a range
#   argument, or `gh issue list` / `gh pr list`, mark the session as
#   "enumeration seen" by recording the tool-call counter.
#
#   On Write or Edit tool calls: if the target file is CHANGELOG.md /
#   CHANGELOG.rst / WIP.md / TODO.md / RELEASES.md / NEWS.md, check the
#   enumeration marker. If the marker is missing or older than the
#   freshness window (default 30 tool calls), exit 2 with an instructive
#   message that names the specific commands the model should run before
#   writing.
#
# TRIGGER: PreToolUse  MATCHER: ""
#
# CONFIGURATION:
#   CC_CHANGELOG_GUARD_WINDOW   freshness window in tool calls (default 30)
#   CC_CHANGELOG_GUARD_LOG      append guard events (default off)
#
# WHAT THIS DOES NOT CATCH:
#   The model can still write inaccurate content after running git log
#   (e.g., misreading commit messages). This hook catches the "no
#   enumeration at all" failure mode, which is what #58715 documents.
#   Content accuracy after enumeration is a separate failure mode.

set -u

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

WINDOW="${CC_CHANGELOG_GUARD_WINDOW:-30}"
STATE_DIR="/tmp/cc-changelog-guard"
COUNT_FILE="$STATE_DIR/${SESSION_ID}.count"
MARK_FILE="$STATE_DIR/${SESSION_ID}.enum-mark"

mkdir -p "$STATE_DIR" 2>/dev/null

# Increment session tool-call counter
COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

case "$TOOL" in
    Bash)
        CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        # Mark enumeration on git log with a range, gh issue list, gh pr list
        if echo "$CMD" | grep -qE '(^|[ ;&|`(])git\s+log\b.*(--since|--all|--oneline|\.\.\.|\.\.|[A-Za-z0-9_/-]+\.\.HEAD)'; then
            echo "$COUNT" > "$MARK_FILE"
        elif echo "$CMD" | grep -qE '(^|[ ;&|`(])gh\s+(issue|pr)\s+(list|status)\b'; then
            echo "$COUNT" > "$MARK_FILE"
        fi
        exit 0
        ;;
    Write|Edit|MultiEdit)
        FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        if [ -z "$FILE" ]; then
            exit 0
        fi
        BASENAME=$(basename "$FILE")
        case "$BASENAME" in
            CHANGELOG.md|CHANGELOG.rst|CHANGELOG.txt|CHANGES.md|CHANGES.txt|WIP.md|TODO.md|RELEASES.md|RELEASE_NOTES.md|NEWS.md|HISTORY.md)
                ;;
            *)
                exit 0
                ;;
        esac

        # Target is a release-notes-like file. Check enumeration marker.
        MARK=$(cat "$MARK_FILE" 2>/dev/null || echo 0)
        AGE=$((COUNT - MARK))
        if [ "$MARK" -eq 0 ] || [ "$AGE" -gt "$WINDOW" ]; then
            cat >&2 <<EOF
BLOCKED: ${BASENAME} writes need fresh enumeration evidence first.

This hook (changelog-completeness-guard.sh) blocks writes to release-notes
files unless the session has recently run \`git log\` (with a range) or
\`gh issue list\` / \`gh pr list\`. Without that step, Claude routinely
adds only the current session's changes and silently skips real commits
(see anthropics/claude-code#58715).

Run one of these first, read the output, then retry the write:
    git log <last-release-tag>..HEAD --oneline
    gh issue list --state closed --search "closed:>YYYY-MM-DD"
    gh pr list --state merged --search "merged:>YYYY-MM-DD"

Replace the tag and date with the real boundaries for this release.

Recent freshness window: ${WINDOW} tool calls. Last enumeration: ${MARK}, current call: ${COUNT}.
To override (e.g. when the changelog rewrite is unrelated to recent work),
set CC_CHANGELOG_GUARD_WINDOW=999999 for the session.
EOF
            if [ -n "${CC_CHANGELOG_GUARD_LOG:-}" ]; then
                mkdir -p "$(dirname "$CC_CHANGELOG_GUARD_LOG")" 2>/dev/null
                echo "$(date -Iseconds) session=${SESSION_ID} blocked file=${FILE} call=${COUNT} mark=${MARK}" \
                    >> "$CC_CHANGELOG_GUARD_LOG"
            fi
            exit 2
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
