#!/bin/bash
# uncommitted-discard-guard.sh — Block commands that discard uncommitted changes
#
# Solves: Claude running "git checkout -- ." or "git restore ." to discard
#         hours of uncommitted work. Real incident: #37888 — 30+ files of
#         manual edits destroyed twice in one session.
#
# Detects:
#   git checkout -- <files>   (discards working tree changes)
#   git checkout .            (discards all changes)
#   git restore <files>       (same effect as checkout --)
#   git restore .             (discards all working tree changes)
#   git stash drop            (permanently deletes stashed changes)
#
# Does NOT block:
#   git checkout <branch>     (switching branches — safe)
#   git checkout -b <branch>  (creating branches — safe)
#   git restore --staged      (unstaging — non-destructive)
#   git stash                 (saving changes — safe)
#   git stash pop             (restoring changes — safe)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block: git checkout -- <files> (discard working tree changes)
# The "--" separator followed by paths means "discard changes to these files"
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s+\S'; then
    echo "BLOCKED: git checkout -- <files> discards uncommitted changes permanently." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "If you need to discard changes, commit or stash first:" >&2
    echo "  git stash        # save changes for later" >&2
    echo "  git stash pop    # restore saved changes" >&2
    exit 2
fi

# Block: git checkout . (discard ALL changes)
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+\.\s*$'; then
    echo "BLOCKED: git checkout . discards ALL uncommitted changes." >&2
    echo "" >&2
    echo "This would destroy every uncommitted modification in the working tree." >&2
    echo "Commit or stash your changes first." >&2
    exit 2
fi

# Block: git restore <files> without --staged (discards working tree changes)
if echo "$COMMAND" | grep -qE 'git\s+restore\s+' && ! echo "$COMMAND" | grep -qE 'git\s+restore\s+--staged'; then
    # Allow "git restore --staged" (just unstages, non-destructive)
    # Block "git restore <files>" and "git restore ."
    echo "BLOCKED: git restore discards uncommitted changes." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "Use 'git restore --staged <file>' to unstage without losing changes." >&2
    echo "Use 'git stash' to save changes for later." >&2
    exit 2
fi

# Block: git stash drop (permanently deletes stashed changes)
if echo "$COMMAND" | grep -qE 'git\s+stash\s+drop'; then
    echo "BLOCKED: git stash drop permanently deletes stashed changes." >&2
    echo "" >&2
    echo "If you're sure, use 'git stash pop' to apply and remove in one step." >&2
    exit 2
fi

exit 0
