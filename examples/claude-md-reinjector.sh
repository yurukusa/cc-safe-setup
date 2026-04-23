#!/bin/bash
# claude-md-reinjector.sh — Re-inject CLAUDE.md to counter instruction drift
#
# Solves: #49244 — Opus 4.6 quality regression starting ~April 15, 2026.
#         Users report Claude Code ignoring CLAUDE.md instructions, failing
#         to update memory files, and making repeated mistakes.
#
#         Root cause (community-documented): Claude Code wraps CLAUDE.md in
#         a framing that marks it as "may or may not be relevant", which
#         reduces its salience after ~50+ tool calls as the conversation
#         grows. Reported by Microsoft research manager, Fortune, The Register
#         (April 2026).
#
# HOW IT WORKS:
#   Counts tool calls per session. Every N calls (default 50), prints the
#   project's CLAUDE.md to stderr. Claude Code reads PreToolUse stderr as
#   additional context, so this effectively re-injects the instructions
#   at a cadence the user controls.
#
#   Prints a short header marking the injection as a hook-triggered reminder,
#   so Claude treats the content as an explicit re-statement of rules rather
#   than part of the current file being edited.
#
# WHY THIS MATTERS:
#   Without re-injection, long sessions drift: Claude "forgets" that the
#   project bans comments, forgets the test command, forgets naming rules.
#   The user then has to re-paste CLAUDE.md manually — burning their own
#   tokens on work the hook can do deterministically.
#
# TRIGGER: PreToolUse  MATCHER: ""
#
# CONFIGURATION:
#   CC_MD_REINJECT_EVERY=50       re-inject every N tool calls (default 50)
#   CC_MD_REINJECT_PATH=path      override CLAUDE.md search (default auto)
#   CC_MD_REINJECT_MAX_CHARS=2000 truncate long CLAUDE.md (default 2000 chars)
#   CC_MD_REINJECT_LOG=path       append injection events (default off)
#
# SEARCH ORDER for CLAUDE.md:
#   1. $CC_MD_REINJECT_PATH (if set)
#   2. $PWD/CLAUDE.md
#   3. git repo root CLAUDE.md (if inside a git repo)
#   4. $HOME/CLAUDE.md
#   5. $HOME/.claude/CLAUDE.md

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

EVERY="${CC_MD_REINJECT_EVERY:-50}"
MAX_CHARS="${CC_MD_REINJECT_MAX_CHARS:-2000}"
STATE_DIR="/tmp/cc-md-reinject"
COUNT_FILE="$STATE_DIR/${SESSION_ID}.count"

mkdir -p "$STATE_DIR" 2>/dev/null

# Increment counter
COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

# Only fire on the N-th, 2N-th, 3N-th ... call
if [ "$((COUNT % EVERY))" -ne 0 ]; then
    exit 0
fi

# Locate CLAUDE.md
find_claude_md() {
    if [ -n "${CC_MD_REINJECT_PATH:-}" ]; then
        # Explicit override: respect it. If missing, skip silently (no fallback).
        [ -f "$CC_MD_REINJECT_PATH" ] && echo "$CC_MD_REINJECT_PATH"
        return 0
    fi
    if [ -f "./CLAUDE.md" ]; then
        echo "./CLAUDE.md"; return 0
    fi
    # Walk up to find git repo root
    dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/CLAUDE.md" ]; then
            echo "$dir/CLAUDE.md"; return 0
        fi
        if [ -d "$dir/.git" ]; then
            break
        fi
        dir=$(dirname "$dir")
    done
    if [ -f "$HOME/CLAUDE.md" ]; then
        echo "$HOME/CLAUDE.md"; return 0
    fi
    if [ -f "$HOME/.claude/CLAUDE.md" ]; then
        echo "$HOME/.claude/CLAUDE.md"; return 0
    fi
    return 1
}

MD_FILE=$(find_claude_md)
if [ -z "$MD_FILE" ]; then
    # No CLAUDE.md to re-inject — silently skip
    exit 0
fi

# Read and truncate
CONTENT=$(head -c "$MAX_CHARS" "$MD_FILE")
ACTUAL_SIZE=$(wc -c < "$MD_FILE")

# Print re-injection to stderr (Claude reads this as pre-tool context)
cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[claude-md-reinjector] Tool call #${COUNT} — re-injecting ${MD_FILE}
Addresses #49244: Claude Code drifting from CLAUDE.md after long sessions.
These are the rules you already agreed to follow. Re-read and comply.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CONTENT}
EOF

if [ "$ACTUAL_SIZE" -gt "$MAX_CHARS" ]; then
    echo "" >&2
    echo "[...truncated at ${MAX_CHARS} chars of ${ACTUAL_SIZE}. Full file: ${MD_FILE}]" >&2
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

# Optional log
if [ -n "${CC_MD_REINJECT_LOG:-}" ]; then
    mkdir -p "$(dirname "$CC_MD_REINJECT_LOG")" 2>/dev/null
    echo "$(date -Iseconds) session=${SESSION_ID} count=${COUNT} file=${MD_FILE} size=${ACTUAL_SIZE}" >> "$CC_MD_REINJECT_LOG"
fi

exit 0
