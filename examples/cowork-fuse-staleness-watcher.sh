#!/bin/bash
# cowork-fuse-staleness-watcher.sh — Warn before bash git ops in Cowork FUSE mounts
#
# Solves: #62932 (P1 critical) — In Cowork, the FUSE bridge that mounts a
#         Windows host folder into the Linux sandbox at
#         /sessions/<id>/mnt/<folder>/ caches inode metadata for the entire
#         session. After the first read, the sandbox bash environment sees
#         the file's original size, mtime, and content even when Windows
#         modifies it. The wedge is SELECTIVE:
#           - file content + stat: stale
#           - working-tree git walks (status / add / commit): return garbage
#           - ref-walking git commands (rev-parse / log / show): stay clean
#           - Cowork's first-class file tools (Read/Edit/Write): bypass FUSE
#             and are authoritative
#
#         The danger: bash `git add` / `git commit` against the working tree
#         silently commits the stale content, corrupting the repo's view of
#         the Windows-side truth. Bash `git status` returns "No commits yet"
#         on a repo with hundreds of commits.
#
# HOW IT WORKS:
#   PreToolUse hook on Bash. If the command looks like a working-tree git
#   operation (git status / add / commit / diff / restore / checkout --) AND
#   the current working directory matches the Cowork FUSE mount pattern
#   (/sessions/*/mnt/), print a stderr warning explaining:
#     - the wedge exists for THIS session and won't self-clear
#     - working-tree views are untrustworthy; ref views are still clean
#     - prefer Cowork's first-class Read/Edit/Write tools instead of bash
#     - if a parser error fires on .git/config, the file likely needs a
#       full rewrite via `cat > .git/config`
#
#   Always exit 0 (advisory only). The hook does NOT block, because the
#   user may consciously be running ref-only ops (rev-parse / log) that
#   stay clean even under the wedge.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIGURATION:
#   CC_COWORK_FUSE_PATTERN=regex  custom path regex (default Cowork sandbox)
#   CC_COWORK_FUSE_QUIET=1        suppress the recommendation block
#   CC_COWORK_FUSE_LOG=path       append warning events (default off)
#
# USAGE:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/cowork-fuse-staleness-watcher.sh"
#       }]
#     }]
#   }
# }

INPUT=$(cat 2>/dev/null || true)

# Extract the bash command. Hook input is JSON via stdin.
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
if [ -z "$CMD" ]; then
    exit 0
fi

# Detect the Cowork FUSE mount path. The pattern is /sessions/<id>/mnt/<folder>/.
# Match either CWD or any path inside the command itself.
FUSE_PATTERN="${CC_COWORK_FUSE_PATTERN:-/sessions/[^/]+/mnt/}"

cwd=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
if [ -z "$cwd" ]; then
    cwd="$PWD"
fi

in_fuse_mount=0
if echo "$cwd" | grep -qE "$FUSE_PATTERN"; then
    in_fuse_mount=1
elif echo "$CMD" | grep -qE "$FUSE_PATTERN"; then
    in_fuse_mount=1
fi

if [ "$in_fuse_mount" -eq 0 ]; then
    exit 0
fi

# Detect a working-tree git command. Ref-only ops (rev-parse, log, show, cat-file)
# are safe under the wedge, so we deliberately do NOT warn on those. Matcher
# allows arbitrary git prefix args like `git -C <path>` or `git --git-dir=...`.
is_worktree_git=0
if echo "$CMD" | grep -qE '\bgit\b[^|;&]*\b(status|add|commit|diff|restore|stash|clean|ls-files|rm|mv)\b'; then
    is_worktree_git=1
elif echo "$CMD" | grep -qE '\bgit\b[^|;&]*\bcheckout\b[^|;&]*(-- |\.\s*$|\.\s*[|;&])'; then
    # `git checkout <branch>` is safe; only warn on path-discard variants
    # like `git checkout -- file` or `git checkout .`.
    is_worktree_git=1
fi

if [ "$is_worktree_git" -eq 0 ]; then
    exit 0
fi

cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[cowork-fuse-staleness-watcher] Cowork FUSE mount detected
This bash command runs against a working-tree git view on a Cowork
Windows-host FUSE bridge (path matches ${FUSE_PATTERN}).

Known wedge (#62932, P1 critical): once a file is read in this session,
its size / mtime / content are frozen for the rest of the session even
when Windows modifies it. Working-tree git ops will see the FROZEN
content; bash 'git add' / 'git commit' will silently commit the stale
content. 'git status' may report "No commits yet" on a repo with hundreds
of commits.

What still works under the wedge:
  - ref-walking git: rev-parse, log, show, cat-file
  - Cowork's first-class Read / Edit / Write file tools (they bypass FUSE)

What does NOT work:
  - bash git status / add / commit / diff / restore / checkout / stash
  - bash file reads of any file modified by Windows in this session

If '.git/config' parsing fails with NUL bytes, rewrite the file via
'cat > .git/config' from inside the sandbox before any further git op.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

if [ -z "${CC_COWORK_FUSE_QUIET:-}" ]; then
    cat >&2 <<'EOF'
[cowork-fuse-staleness-watcher] Recommended: replace this bash git op with
the Cowork file tools (Read / Edit / Write), or use a ref-only command
(rev-parse / log / show) when you just need ref info. The wedge will NOT
clear for the rest of this session.
EOF
fi

if [ -n "${CC_COWORK_FUSE_LOG:-}" ]; then
    mkdir -p "$(dirname "$CC_COWORK_FUSE_LOG")" 2>/dev/null
    echo "$(date -Iseconds) cwd=${cwd} cmd=${CMD}" >> "$CC_COWORK_FUSE_LOG"
fi

exit 0
