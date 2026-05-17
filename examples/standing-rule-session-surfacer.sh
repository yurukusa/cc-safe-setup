#!/bin/bash
# ================================================================
# standing-rule-session-surfacer.sh — Surface standing rules from
# user's auto-memory files on every SessionStart so the model
# cannot "load but forget" them across a long session
# ================================================================
# PURPOSE:
#   Issue #59944 documents an entire 5-hour Claude Code session
#   in which a user-stored "STANDING RULE" (marked "third strike"
#   in the operator's own memory file, indexed in MEMORY.md as
#   always-loaded) was read at session start, then violated across
#   8 backend commits, with the model only acknowledging the rule
#   existed after the operator asked a direct point-blank question
#   about it.
#
#   The structural failure: auto-memory loads files, but does not
#   bind behavior. The rule sits in the system prompt as text,
#   indistinguishable from any other text. Without a visible,
#   load-bearing surfacing at session start, "STANDING RULE" lines
#   carry no more weight than a comment.
#
#   This hook surfaces matching lines (STANDING RULE / strict /
#   third strike / MUST / NEVER / ALWAYS) from the user's memory
#   files into a SessionStart system-reminder block. Re-stating
#   the rule, in load-bearing position, on every new session is
#   the cheapest possible defense.
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# WHY THIS MATTERS:
#   - #59944 reporter's exact framing: "Claude Code read this file
#     at session start. Then it spent the entire session doing
#     backend-only curl probes on tasks the simulation doc
#     explicitly described as UI surfaces."
#   - #59938 (v2.1.128) is the same structural failure on a
#     different surface (CLAUDE.md instead of memory file), with
#     the model directly confessing after the fact: "The rule is
#     already in both CLAUDE.md and my memory file — I just failed
#     to apply it."
#   - Two independent reporters, two different versions, two
#     surfaces (auto-memory and CLAUDE.md), one structural shape.
#
# CONFIGURATION:
#   CC_STANDING_RULE_MAX_LINES  — max lines surfaced per file
#                                 (default: 8). Long memory files
#                                 must be allowed to grow without
#                                 flooding the system prompt.
#   CC_STANDING_RULE_PATTERN    — regex of rule markers to surface
#                                 (default: documented below).
#   CC_STANDING_RULE_MEMORY_DIR — alternate memory directory to
#                                 scan. Default scans every
#                                 .claude/projects/*/memory/ under
#                                 $HOME.
#
# OUTPUT:
#   A JSON object on stdout with `hookSpecificOutput.additionalContext`
#   containing the surfaced rules. Claude Code injects this as a
#   system-reminder for the new session.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/59944
#   https://github.com/anthropics/claude-code/issues/59938
# ================================================================

set -u

MAX_LINES="${CC_STANDING_RULE_MAX_LINES:-8}"
PATTERN="${CC_STANDING_RULE_PATTERN:-STANDING RULE|third strike|strict rule|MUST NOT|MUST ALWAYS|NEVER do|ALWAYS do|絶対|必ず|してはいけない|やるな}"

# Find every memory directory. Default: $HOME/.claude/projects/*/memory/
# (the auto-memory layout Claude Code uses today). Operators can override
# via CC_STANDING_RULE_MEMORY_DIR for a single explicit directory.
if [ -n "${CC_STANDING_RULE_MEMORY_DIR:-}" ]; then
    MEMORY_DIRS=("$CC_STANDING_RULE_MEMORY_DIR")
else
    mapfile -t MEMORY_DIRS < <(find "$HOME/.claude/projects" -maxdepth 2 -type d -name memory 2>/dev/null)
fi

[ ${#MEMORY_DIRS[@]} -eq 0 ] && exit 0

# Collect matching lines from every .md file in every memory dir.
# Limit to MAX_LINES per file to prevent flooding.
COLLECTED=""
SCANNED=0

for dir in "${MEMORY_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        SCANNED=$((SCANNED + 1))
        # Grab matching lines, limit, prefix with the filename.
        matches=$(grep -nE "$PATTERN" "$f" 2>/dev/null | head -n "$MAX_LINES" || true)
        if [ -n "$matches" ]; then
            relname=$(basename "$f")
            COLLECTED="${COLLECTED}
[${relname}]
${matches}
"
        fi
    done
done

# Nothing matched. Exit cleanly. The user has no standing rules
# in their memory layer; this hook produces no output.
if [ -z "$COLLECTED" ]; then
    exit 0
fi

# Build the additionalContext payload. The leading message frames
# the rules as load-bearing, not advisory. This phrasing is
# deliberate: it tells the model that these rules apply to the
# session it is about to start, not just to past conversations.
CONTEXT="===== STANDING RULES FROM AUTO-MEMORY =====
The following rules were marked as STANDING / MUST / NEVER / ALWAYS / 必ず /
絶対 etc. in your memory files, scanned at session start. They apply to this
session immediately. Read them. Apply them. If you find yourself about to
take an action that conflicts with one, stop and verify the conflict before
proceeding.

Scanned ${SCANNED} memory file(s) across ${#MEMORY_DIRS[@]} memory director(y/ies).
${COLLECTED}
===== END STANDING RULES ====="

# Emit as JSON for Claude Code to consume. The hookSpecificOutput
# schema is the documented surface for SessionStart hooks to inject
# additional context.
jq -n \
    --arg ctx "$CONTEXT" \
    '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: $ctx
        }
    }'

exit 0
