#!/bin/bash
# ================================================================
# protect-claudemd.sh — Block edits to CLAUDE.md and settings files
# ================================================================
# PURPOSE:
#   Claude Code sometimes modifies CLAUDE.md, settings.json, or
#   other configuration files without permission. This hook blocks
#   Edit/Write to these critical files.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-protect-claudemd-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [protect-claudemd]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]]; then
    exit 0
fi

if [[ -z "$FILE" ]]; then
    exit 0
fi

BASENAME=$(basename "$FILE")

# Protected files
case "$BASENAME" in
    CLAUDE.md|.claude.json|settings.json|settings.local.json)
        echo "BLOCKED: Cannot modify configuration file: $BASENAME" >&2
        echo "File: $FILE" >&2
        echo "" >&2
        echo "Configuration files should be edited manually, not by Claude." >&2
        exit 2
        ;;
esac

# Protected directories
if echo "$FILE" | grep -qE '\.claude/(hooks|settings|plugins)/'; then
    echo "BLOCKED: Cannot modify .claude system directory: $FILE" >&2
    exit 2
fi

exit 0
