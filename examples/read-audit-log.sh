#!/bin/bash
# ================================================================
# read-audit-log.sh — Log all file read operations for forensics
# ================================================================
# PURPOSE:
#   Creates a searchable audit trail of every file Claude reads.
#   Useful for:
#   - Post-incident forensics ("what did Claude access?")
#   - Detecting prompt injection (tracking reads of untrusted files)
#   - Understanding context consumption (which files cost tokens)
#
# TRIGGER: PostToolUse
# MATCHER: "Read"
#
# OUTPUT: ~/.claude/read-audit.jsonl (append-only)
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Read" ] && exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

AUDIT_FILE="${CC_READ_AUDIT:-$HOME/.claude/read-audit.jsonl}"
mkdir -p "$(dirname "$AUDIT_FILE")"

# Get file metadata
SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE" 2>/dev/null || echo 0)
LINES=$(wc -l < "$FILE" 2>/dev/null || echo 0)

echo "{\"time\":\"$(date -Iseconds)\",\"file\":\"$FILE\",\"size\":$SIZE,\"lines\":$LINES,\"cwd\":\"$(pwd)\"}" >> "$AUDIT_FILE"

exit 0
