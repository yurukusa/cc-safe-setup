#!/bin/bash
# ================================================================
# symlink-guard.sh — Detect symlink/junction traversal before rm
# ================================================================
# PURPOSE:
#   rm -rf on a directory containing symlinks can follow them and
#   delete data outside the target. NTFS junctions on WSL2 are
#   especially dangerous (#36339: entire C:\Users deleted).
#
#   This hook checks if the rm target contains symlinks pointing
#   outside the current project.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHAT IT BLOCKS:
#   - rm -rf on directories containing symlinks to outside paths
#   - rm on targets that are themselves symlinks to sensitive dirs
#
# GitHub Issues: #36339 (93r), #764 (63r), #24964 (135r)
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-symlink-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [symlink-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only check rm commands with recursive flags
if ! echo "$COMMAND" | grep -qE '^\s*rm\s+.*-[rf]'; then
    exit 0
fi

# Extract target path.
# grep -P is GNU-only; macOS ships BSD grep, which rejects -P and returns nothing.
# TARGET would then be empty and the "[[ -z ]] && exit 0" below would let every
# rm through — the guard would stop guarding without saying anything. Measured:
# with -P the hook exits 2 on a symlink pointing outside the project, without it
# it exits 0 on the same input. \K has no POSIX equivalent, so the fallback
# matches from the command word and strips that prefix afterwards.
if echo x | grep -qP x 2>/dev/null; then
    TARGET=$(echo "$COMMAND" | grep -oP 'rm\s+(-[rf]+\s+)*\K\S+' | tail -1)
else
    TARGET=$(echo "$COMMAND" \
        | grep -oE 'rm[[:space:]]+(-[rf]+[[:space:]]+)*[^[:space:]]+' \
        | tail -1 \
        | sed -E 's/^rm[[:space:]]+(-[rf]+[[:space:]]+)*//')
fi

if [[ -z "$TARGET" ]] || [[ ! -e "$TARGET" ]]; then
    exit 0
fi

# Check 1: Is the target itself a symlink?
if [ -L "$TARGET" ]; then
    REAL=$(readlink -f "$TARGET" 2>/dev/null)
    echo "WARNING: rm target is a symlink." >&2
    echo "  Target: $TARGET" >&2
    echo "  Points to: $REAL" >&2
    echo "  rm -rf will follow and delete the real path." >&2
    # Don't block, just warn — user may intend to delete the link
fi

# Check 2: Does the target directory contain symlinks to outside?
if [ -d "$TARGET" ]; then
    PROJECT_DIR=$(pwd)
    DANGEROUS_LINKS=$(find "$TARGET" -maxdepth 3 -type l 2>/dev/null | while read link; do
        REAL=$(readlink -f "$link" 2>/dev/null)
        # Check if symlink points outside the project
        if [[ -n "$REAL" ]] && [[ "$REAL" != "$PROJECT_DIR"* ]]; then
            echo "$link -> $REAL"
        fi
    done | head -3)

    if [[ -n "$DANGEROUS_LINKS" ]]; then
        echo "BLOCKED: rm target contains symlinks pointing outside project." >&2
        echo "" >&2
        echo "Command: $COMMAND" >&2
        echo "Dangerous links:" >&2
        echo "$DANGEROUS_LINKS" | while read line; do
            echo "  $line" >&2
        done
        echo "" >&2
        echo "rm -rf would follow these links and delete external data." >&2
        echo "Remove the symlinks first, then delete the directory." >&2
        exit 2
    fi
fi

exit 0
