#!/bin/bash
# edit-write-deny-list-guard.sh — Mirror permissions.deny enforcement to Edit/Write/MultiEdit
#
# Solves: Edit/Write tool calls silently bypass `permissions.deny` rules
#         in ~/.claude/settings.json. Only Bash deny rules are enforced
#         at the tool layer (#59099). An operator who configures
#         `permissions.deny: ["Edit(/path/to/protected.md)"]` discovers
#         after-the-fact that the edit happened anyway — no block,
#         no permission prompt, no error.
#
# How it works: Reads `permissions.deny` patterns from
#   ~/.claude/settings.json and ~/.claude/settings.local.json, then
#   blocks Edit/Write/MultiEdit tool calls whose file_path matches
#   any Edit(...) / Write(...) / MultiEdit(...) deny pattern.
#
# Pattern shapes supported:
#   "Edit(/absolute/path/file.md)"     — exact path match
#   "Edit(/path/with/*.md)"            — basic glob (matches via case statement)
#   "Edit(/dir/**)"                    — recursive glob (matches via case statement)
#   "Write(...)"                       — same shapes for Write
#   "MultiEdit(...)"                   — same shapes for MultiEdit
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write|MultiEdit"
#
# References:
#   - Issue #59099 (Edit/Write deny list bypass)
#   - Issue #59006 (Bash deny rule bypass via -C flag) — same family
#   - Issue #58373 (silent /goal hang) — same claim-vs-reality pattern

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only check Edit/Write/MultiEdit; let other tools pass.
case "$TOOL" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Load deny patterns from settings.json and settings.local.json
SETTINGS_GLOBAL="${HOME}/.claude/settings.json"
SETTINGS_LOCAL="${HOME}/.claude/settings.local.json"

extract_deny_patterns() {
    local file="$1"
    [ -f "$file" ] || return 0
    jq -r '.permissions.deny // [] | .[]' "$file" 2>/dev/null
}

DENY_PATTERNS=$(
    {
        extract_deny_patterns "$SETTINGS_GLOBAL"
        extract_deny_patterns "$SETTINGS_LOCAL"
    } | sort -u
)

[ -z "$DENY_PATTERNS" ] && exit 0

# Check each deny pattern. We only block patterns scoped to the current
# tool (Edit / Write / MultiEdit) — Bash() patterns are handled by the
# native enforcement layer.
while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue

    # Match the leading tool name in the pattern. Skip patterns that
    # don't target the current tool.
    case "$pattern" in
        "${TOOL}("*")")
            # Extract the path/glob inside the parentheses.
            inner="${pattern#${TOOL}(}"
            inner="${inner%)}"

            # Case statement supports basic glob (*) and recursive glob (**).
            # Bash case patterns treat ** as just *, which is fine for our
            # purposes — paths starting with the prefix match either way.
            case "$FILE_PATH" in
                $inner)
                    echo "BLOCKED: ${TOOL} attempts to access path matching deny rule" >&2
                    echo "  Tool:    ${TOOL}" >&2
                    echo "  Path:    ${FILE_PATH}" >&2
                    echo "  Rule:    ${pattern}" >&2
                    echo "  Source:  permissions.deny in ~/.claude/settings.json or settings.local.json" >&2
                    echo "" >&2
                    echo "  Note: Edit/Write/MultiEdit currently bypass deny rules at the" >&2
                    echo "        tool layer (Issue #59099). This hook mirrors the rule" >&2
                    echo "        enforcement at the hook layer until the tool layer ships" >&2
                    echo "        uniform enforcement." >&2
                    exit 2
                    ;;
            esac
            ;;
    esac
done <<< "$DENY_PATTERNS"

exit 0
