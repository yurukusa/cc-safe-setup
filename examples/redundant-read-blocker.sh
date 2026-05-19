#!/bin/bash
# redundant-read-blocker.sh — Prevent the model from re-reading files it has
# already read recently in the same session.
#
# Solves: #60283 — "Excessive token consumption — task halted mid-execution
# with zero output (macOS)" — where Claude re-read in-context files 10+ times
# before being interrupted, with zero deliverable. Confirmed at scale by
# yurukusa/quota-leakage-audit.sh — across multiple sessions on a single
# operator, individual files were observed Read 3-5 times even when their
# content had not changed.
#
# Background:
#   https://gist.github.com/yurukusa/303431f8e32fed5081b6b2b89712c991 (cluster)
#   https://gist.github.com/yurukusa/0dbe97df416c53c43dd699b72f439060 (audit)
#
# How it works:
#   Maintains a per-session set of recently-read files at
#   $STATE_DIR/<session>/reads.log. On each PreToolUse for Read, checks if
#   the file was already read within the configured window of tool calls.
#   If so, emits a system reminder advising the model to use what's already
#   in context, and (in strict mode) refuses the call.
#
#   The hook respects mtime: if the file has been modified since the previous
#   read, it is NOT considered redundant and the new read passes.
#
# TRIGGER: PreToolUse
# MATCHER: Read
#
# CONFIGURATION:
#   CC_REDUNDANT_READ_WINDOW=20    # how many recent reads to keep tracking
#   CC_REDUNDANT_READ_THRESHOLD=1  # warn after N prior reads (default 1 = the first re-read of an unchanged file fires)
#   CC_REDUNDANT_READ_STRICT=0     # 1 = exit 2 (hard block), 0 = stderr warning (default)
#   CC_REDUNDANT_READ_STATE_DIR    # default /tmp/cc-redundant-read
#
# Usage in settings.json:
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Read",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/redundant-read-blocker.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Read" ] && exit 0

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

WINDOW="${CC_REDUNDANT_READ_WINDOW:-20}"
THRESHOLD="${CC_REDUNDANT_READ_THRESHOLD:-1}"
STRICT="${CC_REDUNDANT_READ_STRICT:-0}"
STATE_DIR="${CC_REDUNDANT_READ_STATE_DIR:-/tmp/cc-redundant-read}/$SESSION_ID"

mkdir -p "$STATE_DIR" 2>/dev/null || true
READS_LOG="$STATE_DIR/reads.log"

# Get current mtime of the target file (may not exist yet, that's fine)
CUR_MTIME=$(stat -c '%Y' "$FILE_PATH" 2>/dev/null || echo "0")

# Count how many times this path has been read within the window, accounting
# for mtime: an entry only counts as a "previous read" if the file has NOT
# been modified since.
PREVIOUS=0
LAST_MTIME=""
if [ -f "$READS_LOG" ]; then
    # Tail the last N lines, then filter for matching paths
    while IFS=$'\t' read -r p m; do
        if [ "$p" = "$FILE_PATH" ]; then
            # If the recorded mtime equals the current mtime, the file is unchanged
            if [ "$m" = "$CUR_MTIME" ]; then
                PREVIOUS=$((PREVIOUS + 1))
            fi
        fi
    done < <(tail -n "$WINDOW" "$READS_LOG" 2>/dev/null)
fi

# Append this read to the log (always — even on block, since the model may
# choose to override and we want to track that)
printf '%s\t%s\n' "$FILE_PATH" "$CUR_MTIME" >> "$READS_LOG"

# Trim log to the window
tail -n "$WINDOW" "$READS_LOG" > "$READS_LOG.tmp" && mv "$READS_LOG.tmp" "$READS_LOG"

# Decide based on threshold
if [ "$PREVIOUS" -ge "$THRESHOLD" ]; then
    cat >&2 <<EOF
<system-reminder>
REDUNDANT READ — $FILE_PATH has already been read $PREVIOUS time(s) in this
session without modification since the last read. The file content is already
in the conversation context.

If you genuinely need to verify the content, use Grep with a specific pattern
rather than re-reading the entire file. If you are reading to refresh memory,
use what is already in context — re-reading consumes input tokens for content
the model already has.

Background: #60283 (excessive token consumption with re-reads of in-context
files). Audit: https://gist.github.com/yurukusa/0dbe97df416c53c43dd699b72f439060

To disable this gate: set CC_REDUNDANT_READ_STRICT=0 and CC_REDUNDANT_READ_THRESHOLD
higher, or remove the hook from settings.json.
</system-reminder>
EOF
    if [ "$STRICT" = "1" ]; then
        exit 2
    fi
fi

exit 0
