#!/bin/bash
# git-rm-orphan-wipe-guard.sh — Block whole-working-tree deletion via git
#
# Solves: Claude Code (or a careless one-liner it runs) wiping an entire
#         working tree — and its recovery path — with git itself, slipping
#         past the rm-based guards.
#
# The #70687 pattern (real loss of 3 years of work + .git history):
#         git checkout --orphan wipe && git rm -rf . --quiet
#   1. "git checkout --orphan" starts a branch with NO parent commit, so
#      there is no prior commit to restore the files from afterwards.
#   2. "git rm -rf ." then removes every tracked file from the index AND
#      the working tree.
#   Together the project is gone with no commit to recover from.
#
# Why existing guards miss it:
#   - rm-safety-net.sh only fires on a command that STARTS with "rm"
#     (^rm). "git rm ..." starts with "git", so it slips through.
#   - git-checkout-safety-guard.sh Check 1 matches "checkout <letter>";
#     "git checkout --orphan" starts with "-", so it is not matched.
#   - bulk-file-delete-guard.sh only blocks "git rm -rf ." when the file
#     count crosses its threshold, so a small-but-total wipe passes.
#
# Detects:
#   git checkout --orphan <name>     (detaches from all history)
#   git switch --orphan <name>       (same, newer syntax)
#   git rm -r / -rf / --recursive    (recursive removal of the tree)
#   git rm . / git rm *              (whole-tree target)
#
# Does NOT block (no on-disk data loss / normal use):
#   git rm <file>                    (single tracked file)
#   git rm --cached ...              (untracks only; disk files survive)
#   git checkout <branch> / -- file  (covered by git-checkout-safety-guard)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-git-rm-orphan-wipe-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [git-rm-orphan-wipe-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# === Check 1: git checkout/switch --orphan (removes the recovery path) ===
if echo "$COMMAND" | grep -qE '\bgit\s+(checkout|switch)\b[^|;&]*--orphan\b'; then
    echo "BLOCKED: git checkout --orphan starts a branch with no parent commit." >&2
    echo "  Followed by 'git rm -rf .' this leaves no commit to recover from (#70687)." >&2
    echo "  If you really need an orphan branch, run it yourself outside the agent." >&2
    exit 2
fi

# === git rm handling: only the destructive (whole-tree) forms ===
if echo "$COMMAND" | grep -qE '\bgit\s+rm\b'; then
    # --cached removes from the index only; working-tree files survive. Safe.
    if echo "$COMMAND" | grep -qE '\bgit\s+rm\b[^|;&]*--cached\b'; then
        exit 0
    fi

    # Check 2: recursive removal (-r / -R / -rf / --recursive)
    if echo "$COMMAND" | grep -qE '\bgit\s+rm\s+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)\b'; then
        echo "BLOCKED: git rm -r removes every tracked file in the tree from disk." >&2
        echo "  rm-safety-net does not catch this (the command starts with 'git', not 'rm')." >&2
        echo "  Delete specific files by name, or use 'git rm --cached' to untrack only." >&2
        exit 2
    fi

    # Check 3: whole-tree target ( . or * ) even without -r
    if echo "$COMMAND" | grep -qE '\bgit\s+rm\b[^|;&]*(\s\.(\s|$)|\s\./(\s|$)|\s\*(\s|$))'; then
        echo "BLOCKED: git rm targeting '.' or '*' removes the whole working tree." >&2
        echo "  Delete specific files by name, or use 'git rm --cached' to untrack only." >&2
        exit 2
    fi
fi

exit 0
