#!/bin/bash
# ================================================================
# write-empty-content-guard.sh — Block clearing an existing non-empty file with empty content
# ================================================================
# PURPOSE:
#   A Write that sends empty or whitespace-only content to a path that
#   already holds a non-empty file silently clears that file. Reported in
#   anthropics/claude-code#72666 (a tool wrote null/empty content and wiped
#   the file with no safety confirmation). Almost every real edit has real
#   content, so an empty write over a non-empty file is nearly always an
#   accident — this blocks exactly that case and nothing else.
#
# HOW IT WORKS:
#   PreToolUse on Write. If the target file exists and is non-empty, and the
#   incoming `content` is empty or only whitespace, exit 2 (block) with a
#   message. New files, and writes that carry real content, pass through.
#   This is narrower than a generic overwrite warning: it does not fire on
#   normal edits, only on the truncate-to-empty case.
#
# TRIGGER: PreToolUse
# MATCHER: "Write"
#
# CONFIGURATION:
#   none
# ================================================================
set -uo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-write-empty-content-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [write-empty-content-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# No path -> not our case.
[ -z "$FILE" ] && exit 0
# Target does not exist -> creating a (possibly empty) new file is fine.
[ -f "$FILE" ] || exit 0
# Target is already empty -> nothing to lose.
[ -s "$FILE" ] || exit 0

# `content` is absent for a Write only in odd cases; treat absent as empty.
CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null)

# Is the incoming content empty or whitespace-only?
if printf '%s' "$CONTENT" | grep -q '[^[:space:]]'; then
    # Has at least one non-whitespace character -> real content, allow.
    exit 0
fi

exist_lines=$(wc -l < "$FILE" 2>/dev/null | tr -d ' ')
cat >&2 <<EOF
BLOCKED: Write would clear an existing non-empty file with empty content.
  file: $FILE (currently ~${exist_lines} lines)
  incoming content is empty or whitespace-only — this silently wipes the file (#72666).
If you really mean to empty it, do it explicitly (e.g. ': > "$FILE"') or write the
intended content. If this was an accidental empty/null write, re-issue with real content.
EOF
exit 2
