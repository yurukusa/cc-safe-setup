#!/bin/bash
# memory-orphan-detector.sh — Detect Claude Code memory that may have been
# orphaned when the working directory was renamed.
#
# Solves: #61349 — "[BUG] Memory orphaned when working directory is renamed"
# Filed 2026-05-22 by adamcopley.
#
# Claude Code stores per-project memory at
#   ~/.claude/projects/<encoded-working-dir>/memory/
# where <encoded-working-dir> is the absolute working directory path with
# every `/` and `.` rewritten as `-`.
#
# When the operator renames or moves a working directory, Claude Code does
# not migrate the memory. Instead, on next session start it silently creates
# a fresh empty memory directory at the new encoded path. The old memory
# directory remains on disk forever — orphaned, not loaded by any session,
# with no notification to the operator. The accumulated investment (user
# role, project conventions, validated feedback, references to external
# systems) is effectively lost.
#
# This hook runs on SessionStart and emits a warning when:
#   (a) the CURRENT working directory's memory is empty (≤ N entries), AND
#   (b) the current working directory has substantive git history (suggesting
#       prior work in the project that would have accumulated memory), AND
#   (c) one or more OTHER memory directories on disk have substantive content
#       (≥ M entries or ≥ K bytes), making them candidate orphans
#
# All three signals together: high likelihood of an orphaning event. The hook
# does not block session start. It surfaces the candidate orphan directories
# so the operator can decide whether to migrate them manually.
#
# Path decoding is LOSSY (a `-` in the encoded path could have originated as
# either a `/` or a literal `-` in the working directory name). This hook
# does NOT attempt to decode and verify path existence; it uses encoded-form
# similarity heuristics instead.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_PROJECTS_DIR              default ~/.claude/projects
#   CC_MEMORY_ORPHAN_DISABLE     set to "1" to disable
#   CC_MEMORY_EMPTY_THRESHOLD    max entries to consider "empty" (default 1)
#   CC_MEMORY_ORPHAN_THRESHOLD   min entries for candidate orphan (default 5)
#   CC_MEMORY_ORPHAN_MIN_BYTES   min bytes for candidate orphan (default 2048)
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "SessionStart": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/memory-orphan-detector.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_MEMORY_ORPHAN_DISABLE:-0}" = "1" ] && exit 0

PROJECTS_DIR="${CC_PROJECTS_DIR:-$HOME/.claude/projects}"
EMPTY_THRESHOLD="${CC_MEMORY_EMPTY_THRESHOLD:-1}"
ORPHAN_THRESHOLD="${CC_MEMORY_ORPHAN_THRESHOLD:-5}"
ORPHAN_MIN_BYTES="${CC_MEMORY_ORPHAN_MIN_BYTES:-2048}"

[ ! -d "$PROJECTS_DIR" ] && exit 0

CWD="$(pwd)"

# Compute the encoded form of the current working directory.
encode_path() {
    # / → -, . → -
    printf '%s' "$1" | tr '/.' '--'
}
CWD_ENCODED="$(encode_path "$CWD")"
CURRENT_MEMORY_DIR="$PROJECTS_DIR/${CWD_ENCODED}/memory"

# (a) Is current memory empty?
CURRENT_COUNT=0
if [ -d "$CURRENT_MEMORY_DIR" ]; then
    CURRENT_COUNT=$(find "$CURRENT_MEMORY_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
fi

# Not empty → likely fine. Exit silently.
if [ "$CURRENT_COUNT" -gt "$EMPTY_THRESHOLD" ]; then
    exit 0
fi

# (b) Does current working directory have git history?
HAS_GIT_HISTORY=0
if [ -d "$CWD/.git" ] || git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
    COMMITS=$(git -C "$CWD" rev-list --count HEAD 2>/dev/null || echo 0)
    if [ "$COMMITS" -gt 5 ]; then
        HAS_GIT_HISTORY=1
    fi
fi

# No git history → not a strong signal of prior work. Exit silently.
if [ "$HAS_GIT_HISTORY" -eq 0 ]; then
    exit 0
fi

# (c) Find candidate orphans: other memory directories with content.
ORPHAN_CANDIDATES=()
for d in "$PROJECTS_DIR"/*/; do
    [ -d "$d" ] || continue
    base="${d%/}"
    base="${base##*/}"
    # Skip current
    if [ "$base" = "$CWD_ENCODED" ]; then continue; fi
    mem_dir="$d/memory"
    [ ! -d "$mem_dir" ] && continue
    cnt=$(find "$mem_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
    bytes=$(du -sb "$mem_dir" 2>/dev/null | awk '{print $1}')
    bytes="${bytes:-0}"
    if [ "$cnt" -ge "$ORPHAN_THRESHOLD" ] && [ "$bytes" -ge "$ORPHAN_MIN_BYTES" ]; then
        # Compute encoded-form similarity: shared prefix length / longer length
        # (very rough — but better than nothing without lossless decode)
        ORPHAN_CANDIDATES+=("$base|$cnt|$bytes")
    fi
done

# No candidate orphans → nothing to report.
if [ "${#ORPHAN_CANDIDATES[@]}" -eq 0 ]; then
    exit 0
fi

# Limit output to top 5 candidates, sorted by byte size descending.
TOP=()
while IFS= read -r line; do
    TOP+=("$line")
done < <(printf '%s\n' "${ORPHAN_CANDIDATES[@]}" | sort -t'|' -k3 -rn | head -5)

EXTRA=$(( ${#ORPHAN_CANDIDATES[@]} - ${#TOP[@]} ))

cat >&2 <<EOF
<system-reminder>
POSSIBLE MEMORY ORPHANING DETECTED — the current working directory's memory
is empty, but this project has substantive git history AND there are other
memory directories on disk with non-trivial content. One of them may be the
prior version of this project's memory that was orphaned by a directory
rename, move, or symlink change.

This is the failure mode documented in anthropics/claude-code#61349. Claude
Code derives memory location from the encoded working-directory path
(everything in / and . becomes -). Renaming the directory produces a
different encoded form, so a fresh empty memory directory is created at
the new path while the old memory stays on disk, unreferenced.

Current working directory: $CWD
Encoded form:              $CWD_ENCODED
Current memory:            $CURRENT_COUNT file(s) at $CURRENT_MEMORY_DIR

Candidate orphan memory directories (top 5 by size):
EOF
for entry in "${TOP[@]}"; do
    IFS='|' read -r b c bytes <<< "$entry"
    # Print bytes in KB for readability
    kb=$(( bytes / 1024 ))
    echo "  $PROJECTS_DIR/$b/memory/  ($c files, ${kb}KB)" >&2
done
if [ "$EXTRA" -gt 0 ]; then
    echo "  ... and $EXTRA more" >&2
fi
cat >&2 <<EOF

Recommended next actions for the operator (NOT for the model to perform
automatically):
  1. Inspect the candidate directories. The encoded path is the original
     working directory's absolute path with every / and . replaced by -.
     Note that this encoding is LOSSY — a - in the encoded form could be a
     literal - or a / in the original path. Decode by trying both.
  2. If you recognize an orphan that corresponds to a previous location of
     this project (before a rename/move), copy its memory files into the
     current memory directory: cp -r <orphan>/memory/* $CURRENT_MEMORY_DIR/
  3. To prevent future orphaning, version-control the memory directory:
     store memory in the project's git tree (e.g., .claude-memory/) and
     symlink the system memory directory to it. Renames preserve the link.

To disable this detector, set CC_MEMORY_ORPHAN_DISABLE=1.
</system-reminder>
EOF

# Exit 0 — detection-only.
exit 0
