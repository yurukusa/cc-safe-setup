#!/bin/bash
# ================================================================
# pre-compact-transcript-export.sh — Export conversation before compaction
# ================================================================
# PURPOSE:
#   After compaction, the pre-compaction conversation is inaccessible
#   in the TUI. This hook exports the conversation to a human-readable
#   markdown file before compaction happens, so you can review it later.
#
#   Reads transcript.jsonl and extracts:
#   - User messages (prompts)
#   - Assistant messages (responses)
#   - Tool calls and results (summarized)
#
# TRIGGER: PreCompact
# MATCHER: (none — PreCompact has no matcher)
#
# OUTPUT: .claude/conversation-snapshots/TIMESTAMP.md
#
# See: https://github.com/anthropics/claude-code/issues/27242
# ================================================================

set -euo pipefail

# Find the current session transcript
SESSION_DIR="${HOME}/.claude/projects"
TRANSCRIPT=""

# Try to find transcript from input
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# Fallback: find most recent transcript.jsonl
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(find "$SESSION_DIR" -name "transcript.jsonl" -newer /tmp/.claude-session-start 2>/dev/null | head -1)
fi

# If still not found, try the current working directory
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(find "$SESSION_DIR" -name "transcript.jsonl" -mmin -60 2>/dev/null | sort -t/ -k1 | tail -1)
fi

[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# Create snapshot directory
SNAPSHOT_DIR="${HOME}/.claude/conversation-snapshots"
mkdir -p "$SNAPSHOT_DIR"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
OUTPUT="$SNAPSHOT_DIR/${TIMESTAMP}.md"

# Extract human-readable conversation
{
    echo "# Conversation Snapshot"
    echo "Exported: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Source: $TRANSCRIPT"
    echo ""
    echo "---"
    echo ""

    # Parse JSONL and extract messages
    while IFS= read -r line; do
        ROLE=$(echo "$line" | jq -r '.message.role // empty' 2>/dev/null)
        case "$ROLE" in
            user)
                CONTENT=$(echo "$line" | jq -r '.message.content // empty' 2>/dev/null)
                if [ -n "$CONTENT" ] && [ "$CONTENT" != "null" ]; then
                    echo "## User"
                    echo "$CONTENT" | head -20
                    echo ""
                fi
                ;;
            assistant)
                TEXT=$(echo "$line" | jq -r '[.message.content[]? | select(.type=="text") | .text] | join("\n")' 2>/dev/null)
                if [ -n "$TEXT" ] && [ "$TEXT" != "null" ]; then
                    echo "## Assistant"
                    echo "$TEXT" | head -50
                    echo ""
                fi
                ;;
        esac
    done < "$TRANSCRIPT"
} > "$OUTPUT" 2>/dev/null

LINES=$(wc -l < "$OUTPUT" 2>/dev/null || echo 0)
echo "Conversation snapshot saved: $OUTPUT ($LINES lines)" >&2

exit 0
