#!/bin/bash
# ================================================================
# core-file-protect-guard.sh — Block edits to core/config/rules files
# ================================================================
# PURPOSE:
#   Claude Code sometimes makes unprompted architectural changes to
#   game rules, configuration files, and core logic files. This hook
#   blocks modifications to files matching configurable glob patterns.
#
# Protects files matching CC_PROTECTED_FILES patterns (colon-separated).
# Default: "*rules*:*config*:*core*"
#
# Catches:
#   - Edit/Write tool targeting protected files
#   - Bash commands using sed -i or awk -i on protected files
#
# See: https://github.com/anthropics/claude-code/issues/40788
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write|Bash"
#
# Configuration:
#   CC_PROTECTED_FILES — colon-separated glob patterns
#   Default: "*rules*:*config*:*core*"
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-core-file-protect-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [core-file-protect-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Configurable protected file patterns (colon-separated globs)
PROTECTED="${CC_PROTECTED_FILES:-*rules*:*config*:*core*}"

# Convert colon-separated globs to a function that checks a filename
matches_protected() {
    local filepath="$1"
    local basename
    basename=$(basename "$filepath")

    IFS=':' read -ra PATTERNS <<< "$PROTECTED"
    for pattern in "${PATTERNS[@]}"; do
        # Use bash glob matching (case-insensitive via shopt)
        if [[ "$basename" == $pattern ]] || [[ "$filepath" == *$pattern* ]]; then
            return 0
        fi
    done
    return 1
}

# Handle Edit/Write tools
if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]]; then
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [ -z "$FILE" ] && exit 0

    if matches_protected "$FILE"; then
        echo "BLOCKED: Cannot modify protected file: $FILE" >&2
        echo "" >&2
        echo "Protected patterns: $PROTECTED" >&2
        echo "Configure with CC_PROTECTED_FILES env var." >&2
        echo "" >&2
        echo "See: https://github.com/anthropics/claude-code/issues/40788" >&2
        exit 2
    fi
    exit 0
fi

# Handle Bash tool — check for sed -i / awk -i targeting protected files
if [[ "$TOOL" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$COMMAND" ] && exit 0

    # Skip echo/printf
    echo "$COMMAND" | grep -qE '^\s*(echo|printf)\s' && exit 0

    # Check for sed -i or awk -i inplace targeting protected files
    if echo "$COMMAND" | grep -qE '(sed\s+-i|awk\s+-i\s+inplace)'; then
        # Extract potential file arguments from the command
        IFS=':' read -ra PATTERNS <<< "$PROTECTED"
        for pattern in "${PATTERNS[@]}"; do
            if echo "$COMMAND" | grep -qE "$pattern"; then
                echo "BLOCKED: In-place edit targets protected file pattern: $pattern" >&2
                echo "" >&2
                echo "Command: $COMMAND" >&2
                echo "Protected patterns: $PROTECTED" >&2
                echo "" >&2
                echo "See: https://github.com/anthropics/claude-code/issues/40788" >&2
                exit 2
            fi
        done
    fi
fi

exit 0
