#!/bin/bash
# bulk-file-delete-guard.sh — Block commands that delete many files at once
#
# Solves: Agent deleting thousands of untracked files without user consent
#         (#23913 — 2,229 files deleted with rm -rf and Remove-Item)
#
# How it works: Detects recursive delete patterns and estimates the number
#   of files that would be affected. Blocks if above threshold.
#
# Default threshold: 10 files. Change THRESHOLD below.
#
# Patterns detected:
#   - rm -rf / rm -r with wildcards or broad paths
#   - find ... -delete / find ... -exec rm
#   - Remove-Item -Recurse (PowerShell)
#   - git clean -fd (removes untracked files)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-bulk-file-delete-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [bulk-file-delete-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

THRESHOLD=10

# Check for recursive delete patterns
IS_BULK=0
TARGET=""

# Normalise a target so it can actually be counted.
# Measured 2026-09-18: the same 25-file directory was let through when the path
# was quoted, reached via `cd`, or written as a glob - only a bare absolute path
# was blocked. Every one of those is an ordinary way to write the command, so the
# guard was warning instead of blocking on the shapes people use most.
resolve_target() {
    local t="$1"
    # Strip surrounding quotes - the counting test below is a literal -d check
    t="${t%\"}"; t="${t#\"}"
    t="${t%\'}"; t="${t#\'}"
    # `cd <dir> && rm -rf <name>`: count relative to the directory we cd into
    if [[ "$t" != /* ]]; then
        local cd_dir
        cd_dir=$(echo "$COMMAND" | grep -oE '^[[:space:]]*cd[[:space:]]+[^&;|]+' | sed 's/^[[:space:]]*cd[[:space:]]\+//')
        # Trim trailing whitespace BEFORE unquoting - `cd "dir" && rm -rf x`
        # leaves a space after the closing quote, and stripping quotes first
        # then silently does nothing (measured 2026-09-18).
        cd_dir="${cd_dir%"${cd_dir##*[![:space:]]}"}"
        cd_dir="${cd_dir%\"}"; cd_dir="${cd_dir#\"}"
        cd_dir="${cd_dir%\'}"; cd_dir="${cd_dir#\'}"
        [[ -n "$cd_dir" ]] && t="${cd_dir%/}/$t"
    fi
    # A trailing glob still names a real parent - count that instead
    if [[ "$t" == *[\*\?]* ]]; then
        local parent="${t%/*}"
        [[ "$parent" != "$t" ]] && t="$parent"
    fi
    printf '%s' "${t%/}"
}

# rm -rf / rm -r with wildcards or broad directory paths
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f?|(-[a-zA-Z]*f[a-zA-Z]*r))\s'; then
    # Extract the target path
    TARGET=$(echo "$COMMAND" | grep -oE 'rm\s+-[a-zA-Z]+\s+(.+)' | sed 's/rm\s\+-[a-zA-Z]\+\s\+//')
    TARGET=$(resolve_target "$TARGET")
    IS_BULK=1
fi

# find ... -delete
if echo "$COMMAND" | grep -qE 'find\s+.*-delete'; then
    TARGET=$(echo "$COMMAND" | grep -oE 'find\s+(\S+)' | sed 's/find\s\+//')
    TARGET=$(resolve_target "$TARGET")
    IS_BULK=1
fi

# find ... -exec rm
if echo "$COMMAND" | grep -qE 'find\s+.*-exec\s+rm'; then
    TARGET=$(echo "$COMMAND" | grep -oE 'find\s+(\S+)' | sed 's/find\s\+//')
    TARGET=$(resolve_target "$TARGET")
    IS_BULK=1
fi

# Remove-Item -Recurse (PowerShell)
if echo "$COMMAND" | grep -qiE 'Remove-Item.*-Recurse|Remove-Item.*-r\b'; then
    IS_BULK=1
fi

# git clean -fd (removes untracked files)
if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*[fd]'; then
    IS_BULK=1
    # Count untracked files
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
    if [[ "$UNTRACKED" -gt "$THRESHOLD" ]]; then
        echo "BLOCKED: git clean would delete $UNTRACKED untracked files (threshold: $THRESHOLD)" >&2
        echo "Command: $COMMAND" >&2
        echo "" >&2
        echo "Review files first: git ls-files --others --exclude-standard" >&2
        exit 2
    fi
    exit 0
fi

if [[ "$IS_BULK" -eq 1 ]]; then
    # Try to count affected files
    if [[ -n "$TARGET" ]] && [[ -d "$TARGET" ]]; then
        COUNT=$(find "$TARGET" -type f 2>/dev/null | head -$((THRESHOLD + 1)) | wc -l)
        if [[ "$COUNT" -gt "$THRESHOLD" ]]; then
            echo "BLOCKED: Recursive delete would affect $COUNT+ files (threshold: $THRESHOLD)" >&2
            echo "Command: $COMMAND" >&2
            echo "Target: $TARGET" >&2
            echo "" >&2
            echo "Delete specific files instead of using recursive patterns." >&2
            exit 2
        fi
    else
        # Can't count files (target doesn't exist or is a glob), warn
        echo "WARNING: Recursive delete detected but can't estimate impact." >&2
        echo "Command: $COMMAND" >&2
    fi
fi

exit 0
