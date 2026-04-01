#!/bin/bash
# ================================================================
# conversation-history-guard.sh — Block modifications to conversation history
# ================================================================
# PURPOSE:
#   Prevents Claude from reading or modifying its own conversation
#   history files (.jsonl transcripts). When Claude reads these
#   files, the `cch=` billing hash substitution permanently
#   invalidates prompt cache, causing 20x token inflation.
#   When Claude writes to them, it can corrupt the session.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|Read|Edit|Write"
#
# WHY THIS MATTERS:
#   Claude Code uses prompt caching to reduce token consumption.
#   The cache key is based on conversation history content.
#   If Claude reads its own transcript, the CLI substitutes
#   billing hashes (cch=), changing the content and invalidating
#   the cache prefix. This causes every subsequent turn to pay
#   full price instead of using cached tokens.
#   Measured impact: cache read ratio drops from 89-99% to 4.3%,
#   causing ~20x token inflation per turn.
#
# WHAT IT BLOCKS:
#   - Read/cat/head/tail of .claude/projects/*/*.jsonl
#   - Edit/Write to conversation transcript files
#   - Bash commands that access session JSONL files
#
# CONFIGURATION:
#   CC_ALLOW_HISTORY_ACCESS=1 — disable this guard
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/40524
#   https://github.com/anthropics/claude-code/issues/34629
#   https://github.com/anthropics/claude-code/issues/40652
#   https://github.com/anthropics/claude-code/issues/41891
# ================================================================

set -u

[ "${CC_ALLOW_HISTORY_ACCESS:-0}" = "1" ] && exit 0

INPUT=$(cat)

# Check file_path for Read/Edit/Write tools
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -n "$FILE_PATH" ]; then
    case "$FILE_PATH" in
        */.claude/projects/*.jsonl|*/.claude/projects/*/sessions/*.jsonl)
            printf 'BLOCKED: Accessing conversation history invalidates prompt cache.\n' >&2
            printf '  File: %s\n' "$FILE_PATH" >&2
            printf '  Reading session JSONL causes cch= substitution, dropping cache ratio to ~4%%.\n' >&2
            printf '  Use an external terminal to inspect session files.\n' >&2
            exit 2
            ;;
    esac
fi

# Check Bash commands
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -n "$CMD" ]; then
    if printf '%s' "$CMD" | grep -qE '\.claude/projects/.*\.jsonl' && \
       printf '%s' "$CMD" | grep -qE '(cat|head|tail|less|more|grep|jq|read|wc)'; then
        printf 'BLOCKED: Command accesses conversation history (cache poisoning risk).\n' >&2
        printf '  Command: %s\n' "$CMD" >&2
        exit 2
    fi
fi

exit 0
