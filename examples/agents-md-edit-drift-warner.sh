#!/bin/bash
# ================================================================
# agents-md-edit-drift-warner.sh — Warn at the moment CLAUDE.md (or
#   AGENTS.md) is edited that the sibling instruction file is now
#   stale. Complements the SessionStart-only agents-md-sync-checker
#   (PR #377) with a PostToolUse signal at the actual drift event.
# ================================================================
# PURPOSE:
#   anthropics/claude-code#6235 (5,233 reactions, 13+ months open,
#   the largest single feature request in the Claude Code tracker)
#   asks Claude Code to read AGENTS.md as a fallback to CLAUDE.md.
#   The companion SessionStart hook agents-md-sync-checker (PR
#   #377) detects drift at the start of a session — but the
#   actionable moment is the edit itself. By the time the next
#   session starts the operator has often moved on; an in-the-loop
#   warning at the moment of the edit is the cheapest correction
#   point.
#
#   This PostToolUse hook fires on Edit and Write tool calls whose
#   file_path resolves to one of the candidate instruction files
#   (CLAUDE.md, AGENTS.md, .claude/CLAUDE.md, .agents/AGENTS.md).
#   It then checks whether the sibling file exists and emits a
#   one-screen advisory naming the edit and the sibling that now
#   needs reconciliation.
#
# TRIGGER: PostToolUse  MATCHER: "Edit|Write|MultiEdit"
# CLUSTER: 3 (AGENTS.md interop)
# COMPANION HOOK: agents-md-sync-checker.sh (SessionStart, PR #377)
#
# DETECTION LOGIC:
#   1. Read tool name and tool_input.file_path from PostToolUse
#      hook input.
#   2. If the tool is not Edit / Write / MultiEdit, exit silent.
#   3. If the file_path basename is not in the instruction-file
#      candidate set, exit silent.
#   4. Determine which instruction file was edited
#      (CLAUDE.md or AGENTS.md).
#   5. Locate the sibling instruction file in the same directory
#      or in the standard sibling-directory location
#      (.claude/CLAUDE.md ↔ .agents/AGENTS.md).
#   6. If the sibling exists and is not the same inode (i.e. not
#      a symlink to the same file), emit a warning. If the sibling
#      is symlinked to this file, no drift is possible — exit
#      silent.
#   7. If the sibling does not exist, emit a softer note: the
#      sibling-tool agent (Codex / Cursor / Amp / etc., or Claude
#      Code itself depending on direction) will run without these
#      instructions until the sibling is created.
#
# CONFIGURATION (env vars):
#   CC_AGENTS_MD_DRIFT_WARN_DISABLE   Set to "1" to silence.
#   CC_AGENTS_MD_DRIFT_WARN_QUIET     Set to "1" to suppress the
#                                     verbose advisory and emit
#                                     only the one-line state.
#
# UPSTREAM REFERENCES:
#   #6235 (5,233 reactions, the central feature request)
#   #31005 (community plea, six issues, 7-month silence)
#   #34235, #62371, #53223 (sibling angles)
#
# WHY POSTTOOLUSE, NOT PRETOOLUSE:
#   PreToolUse would block the edit until the operator reconciles,
#   which is wrong for this cluster — the operator is intentionally
#   editing the file and the sibling is meant to track the edit.
#   PostToolUse fires after the edit lands and surfaces the
#   sibling-file gap so the operator can decide whether to mirror
#   the change now or defer it. The hook never blocks; it advises.
# ================================================================

set -u

if [ "${CC_AGENTS_MD_DRIFT_WARN_DISABLE:-0}" = "1" ]; then
    exit 0
fi

QUIET="${CC_AGENTS_MD_DRIFT_WARN_QUIET:-0}"

INPUT=$(cat 2>/dev/null || true)
if [ -z "$INPUT" ]; then
    exit 0
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // .tool_input.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$TOOL_NAME" ] || [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Only fire on file-modifying tool families.
case "$TOOL_NAME" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

BASENAME=$(basename "$FILE_PATH")

# Only fire on the instruction-file candidates.
case "$BASENAME" in
    CLAUDE.md|AGENTS.md) ;;
    *) exit 0 ;;
esac

DIR=$(dirname "$FILE_PATH")

# Determine the sibling basename.
if [ "$BASENAME" = "CLAUDE.md" ]; then
    SIBLING_BASENAME="AGENTS.md"
    EDITED_TOOL="Claude Code"
    SIBLING_TOOLS="Codex / Cursor / Amp / Copilot / Aider / etc."
else
    SIBLING_BASENAME="CLAUDE.md"
    EDITED_TOOL="Codex / Cursor / Amp / Copilot / Aider / etc."
    SIBLING_TOOLS="Claude Code"
fi

# Look for the sibling in the same directory first.
SIBLING_PATH="${DIR}/${SIBLING_BASENAME}"

# If the sibling is not in the same directory, also check the
# cross-mounted standard location (.claude/CLAUDE.md ↔
# .agents/AGENTS.md).
SIBLING_EXISTS=0
if [ -f "$SIBLING_PATH" ]; then
    SIBLING_EXISTS=1
fi

if [ "$SIBLING_EXISTS" = "0" ]; then
    ALT_PATH=""
    case "$FILE_PATH" in
        */.claude/CLAUDE.md)
            ALT_PATH="${FILE_PATH%/.claude/CLAUDE.md}/.agents/AGENTS.md"
            ;;
        */.agents/AGENTS.md)
            ALT_PATH="${FILE_PATH%/.agents/AGENTS.md}/.claude/CLAUDE.md"
            ;;
    esac
    if [ -n "$ALT_PATH" ] && [ -f "$ALT_PATH" ]; then
        SIBLING_PATH="$ALT_PATH"
        SIBLING_EXISTS=1
    fi
fi

# If the sibling does not exist anywhere we recognize, emit a
# softer note about the sibling tool running without instructions.
if [ "$SIBLING_EXISTS" = "0" ]; then
    cat >&2 <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[agents-md-edit-drift-warner] Edited: ${FILE_PATH}
No sibling ${SIBLING_BASENAME} found in this directory.
${SIBLING_TOOLS} will read no project instructions for this repo
unless you create ${DIR}/${SIBLING_BASENAME}.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
    exit 0
fi

# If the sibling exists and is the same inode (symlink), no drift
# is possible — exit silent.
if [ "$SIBLING_PATH" -ef "$FILE_PATH" ]; then
    exit 0
fi

# If the two files are byte-identical right now, the edit may have
# just brought them in sync (or they were synced before and the
# edit was idempotent). Either way, no warning needed.
if cmp -s "$FILE_PATH" "$SIBLING_PATH" 2>/dev/null; then
    exit 0
fi

# Sibling exists, different content. Emit the drift warning.
EDITED_SIZE=$(wc -c < "$FILE_PATH" 2>/dev/null || echo 0)
SIBLING_SIZE=$(wc -c < "$SIBLING_PATH" 2>/dev/null || echo 0)

if [ "$QUIET" = "1" ]; then
    echo "[agents-md-edit-drift-warner] Drift: ${BASENAME} edited; ${SIBLING_BASENAME} now stale." >&2
    exit 0
fi

cat >&2 <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[agents-md-edit-drift-warner] Drift detected at edit time

Edited:  ${FILE_PATH} (${EDITED_SIZE} bytes)
Sibling: ${SIBLING_PATH} (${SIBLING_SIZE} bytes, NOT updated)

The sibling instruction file did not receive this edit. The next
session of ${SIBLING_TOOLS} will read the older ${SIBLING_BASENAME}
rather than what ${EDITED_TOOL} now sees.

Cluster 3 (AGENTS.md interop): #6235 has 5,233 reactions and
13+ months without an official Anthropic position. Until Claude
Code reads AGENTS.md natively, the operator-side burden is to
keep both files in sync at edit time.

Three reconciliation options at this moment:

  1. Mirror the edit now. Open ${SIBLING_PATH} and apply the same
     change while the diff is fresh in your head.

  2. Symlink the two files. \`ln -sf ${FILE_PATH} ${SIBLING_PATH}\`
     (or the reverse direction) makes future edits update both
     at once. Caveat: if you symlink at the directory level
     between .claude/ and .agents/, Claude Code writes .system/
     files into the shared directory (#20820 / #31005).

  3. Defer with intent. If you know you are mid-experiment and
     do not want the sibling to track this revision yet, the
     warning is informational only — no action required.

Silence: set CC_AGENTS_MD_DRIFT_WARN_DISABLE=1.
Compact mode: set CC_AGENTS_MD_DRIFT_WARN_QUIET=1.

Companion: agents-md-sync-checker (SessionStart, PR #377) catches
the drift at the start of the next session if you defer here.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

exit 0
