#!/bin/bash
# ================================================================
# memory-write-guard.sh — See, approve, or block silent memory writes
# ================================================================
# PURPOSE:
#   Claude Code writes to its memory without asking: it edits CLAUDE.md
#   and silently creates/updates/deletes files under
#   ~/.claude/projects/*/memory/. Users report having to re-check those
#   files after every session to find changes they never approved.
#
#   This hook gives the operator control over those writes. By default it
#   only makes them VISIBLE (logs + a stderr note), which is non-intrusive
#   and safe for automated runs. Opt in to an approval prompt — or a hard
#   block — when you want every memory change to pass through you first.
#
# WHAT COUNTS AS A "MEMORY" WRITE (Write/Edit/MultiEdit on):
#   - any CLAUDE.md / CLAUDE.local.md (project or user memory)
#   - anything under a .claude/ directory, which includes the auto-memory
#     store ~/.claude/projects/*/memory/ and ~/.claude/settings.json
#
# MODE (env var CC_MEMORY_WRITE_APPROVAL):
#   off   (default) — log + warn, never interrupt   (backward compatible)
#   ask            — require interactive approval for each memory write
#   block          — refuse all memory writes
#
# WHY OPT-IN: existing installs and headless/CI runs must keep working
#   unchanged, so the prompt is never on unless the operator asks for it.
#   CAUTION: under bypassPermissions (or --dangerously-skip-permissions)
#   an "ask" decision is silently auto-approved and does NOT gate the
#   write (#77212, open at the time of writing). Only a hard refusal is
#   always honored — use CC_MEMORY_WRITE_APPROVAL=block (exit 2) to
#   enforce in unattended runs.
#
# TRIGGER: PreToolUse  MATCHER: "Write|Edit|MultiEdit"
#
# Born from:
#   https://github.com/anthropics/claude-code/issues/38040
#     "No way to enforce approval on all file modifications"
#   https://github.com/anthropics/claude-code/issues/65064
#     "claude code writes memory without asking for permission"
# ================================================================

set -u

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Is this a memory file? Match the auto-memory/.claude store and CLAUDE.md
# files anywhere (project ./CLAUDE.md as well as ~/.claude/CLAUDE.md).
BASENAME=$(basename "$FILE")
IS_MEMORY=0
case "$FILE" in
    */.claude/*|~/.claude/*) IS_MEMORY=1 ;;
esac
case "$BASENAME" in
    CLAUDE.md|CLAUDE.local.md) IS_MEMORY=1 ;;
esac
[ "$IS_MEMORY" -eq 0 ] && exit 0

# Record every memory write so the operator can audit what was stored.
LOG="$HOME/.claude/memory-writes.log"
echo "[$(date -Iseconds)] Write to: $FILE" >> "$LOG" 2>/dev/null

MODE="${CC_MEMORY_WRITE_APPROVAL:-off}"

case "$MODE" in
    ask)
        # Emit a PreToolUse permission decision. In an interactive session
        # this surfaces an approve/deny prompt. CAUTION: under
        # bypassPermissions the "ask" is silently auto-approved and the
        # write proceeds (#77212) — use =block to enforce unattended.
        jq -n --arg f "$FILE" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "ask",
                permissionDecisionReason: ("Approve write to memory file: " + $f)
            }
        }'
        exit 0
        ;;
    block)
        echo "BLOCKED: memory write refused by memory-write-guard." >&2
        echo "File: $FILE" >&2
        echo "Set CC_MEMORY_WRITE_APPROVAL=ask to approve per-write, or =off to only log." >&2
        exit 2
        ;;
    *)
        # off (default): only make the write visible.
        echo "NOTE: Writing to Claude memory: $FILE" >&2
        case "$FILE" in
            */settings.json|*/settings.local.json)
                echo "WARNING: Modifying Claude Code settings file." >&2
                echo "Verify this change is intentional." >&2
                ;;
        esac
        exit 0
        ;;
esac
