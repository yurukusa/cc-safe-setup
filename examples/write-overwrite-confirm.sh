#!/bin/bash
# write-overwrite-confirm.sh — Warn when Write destroys content nobody looked at
#
# Solves (original): Write tool silently replacing large files with new content
#         (#34597). A 500-line file can be overwritten with 10 lines.
#
# Solves (2026-08 addition): #78273 — the agent read FIVE lines of a hand-built
#         file, confirmed it had content, then overwrote the whole file with its
#         own analysis. The original was not in git and was unrecoverable.
#         The size check below could not see this: the replacement was not
#         smaller, so nothing fired.
#
#         A user on that thread named the general shape of the gap:
#         "most guards key off the shape of a tool call rather than whether a
#         write is about to destroy pre-existing, un-backed-up content
#         (…) diffing intent against existing content before an overwrite is
#         basically missing across the board right now."
#
# WHAT THIS ADDS: before an overwrite, ask two questions instead of one.
#   1. Is the replacement much smaller?              (original check)
#   2. Was the part being destroyed ever read?       (new check)
#
#   Question 2 needs a record of what was read, which is why this hook is
#   paired with examples/record-read-coverage.sh (PostToolUse on Read).
#   Without that recorder, no read coverage is known and this check stays
#   silent rather than warning on everything — a guard that always fires is
#   the same as no guard.
#
# TRIGGER: PreToolUse
# MATCHER: "Write"
#
# TUNING (env):
#   CC_WRITE_OVERWRITE_MIN_LINES   default 20  — ignore files smaller than this
#   CC_WRITE_OVERWRITE_MAX_DESTROY default 10  — unseen lines destroyed before warning
#   CC_WRITE_OVERWRITE_BLOCK=1                 — refuse the write (exit 2) instead of warning
#   CC_READ_LOG                    default /tmp/cc-read-files

set -uo pipefail

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$FILE" ] && exit 0

# Skip if file doesn't exist (new file creation)
[ ! -f "$FILE" ] && exit 0

CURRENT_LINES=$(wc -l < "$FILE" 2>/dev/null || echo 0)
case "$CURRENT_LINES" in ''|*[!0-9]*) CURRENT_LINES=0 ;; esac

NEW_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)
# printf '%s\n' and not '%s': the original used echo, which appends a newline, so
# single-line content counted as 1. Dropping that newline made wc -l return 0 and
# silently disabled the shrink check below.
NEW_LINES=$(printf '%s\n' "$NEW_CONTENT" | wc -l 2>/dev/null || echo 0)
case "$NEW_LINES" in ''|*[!0-9]*) NEW_LINES=0 ;; esac

# ---------------------------------------------------------------
# Check 1 (original): the replacement is much smaller than the file
# ---------------------------------------------------------------
if [ "$CURRENT_LINES" -gt 50 ] && [ "$NEW_LINES" -gt 0 ]; then
  RATIO=$((NEW_LINES * 100 / CURRENT_LINES))
  if [ "$RATIO" -lt 50 ]; then
    echo "WARNING: File shrinking from $CURRENT_LINES to ~$NEW_LINES lines ($RATIO%)." >&2
    echo "File: $FILE" >&2
    echo "Consider using Edit tool for targeted changes instead of full rewrite." >&2
  fi
fi

# ---------------------------------------------------------------
# Check 2 (2026-08): the overwrite destroys lines nobody has read
# ---------------------------------------------------------------
MIN_LINES="${CC_WRITE_OVERWRITE_MIN_LINES:-20}"
MAX_DESTROY="${CC_WRITE_OVERWRITE_MAX_DESTROY:-10}"
READ_LOG="${CC_READ_LOG:-/tmp/cc-read-files}"

case "$MIN_LINES"   in ''|*[!0-9]*) MIN_LINES=20 ;; esac
case "$MAX_DESTROY" in ''|*[!0-9]*) MAX_DESTROY=10 ;; esac

[ "$CURRENT_LINES" -lt "$MIN_LINES" ] && exit 0

# No recorder installed means no coverage information at all. Staying silent is
# deliberate: warning on every overwrite would make this hook noise, which is
# exactly the failure mode read-before-edit.sh had while its recorder was missing.
[ -f "$READ_LOG" ] || exit 0

# Did the reads so far cover the whole file? Intervals are merged because a file
# is often read in pages (offset 1 limit 100, then offset 101 limit 100, ...).
# offset/limit of 0 means the Read carried no such argument, i.e. it started at
# the top and ran to the tool's own cap, so treat it as covering what existed then.
COVERED=$(awk -F'\t' -v f="$FILE" -v total="$CURRENT_LINES" '
  # n must start as a number. An uninitialised awk variable is the empty string,
  # and s[n] then writes to the subscript "" instead of 0, so every interval
  # lands in one invisible slot and the file always looks unread.
  BEGIN { n = 0 }
  $1 == f {
    off = ($2 + 0 < 1) ? 1 : $2 + 0
    lim = $3 + 0
    end = (lim > 0) ? off + lim - 1 : ($4 + 0 > 0 ? $4 + 0 : total)
    if (end > total) end = total
    if (end >= off) { s[n] = off; e[n] = end; n++ }
  }
  END {
    if (n == 0) { print 0; exit }
    for (i = 0; i < n; i++)
      for (j = i + 1; j < n; j++)
        if (s[j] < s[i]) { t=s[i];s[i]=s[j];s[j]=t; t=e[i];e[i]=e[j];e[j]=t }
    reach = 0
    for (i = 0; i < n; i++) {
      if (s[i] > reach + 1) break
      if (e[i] > reach) reach = e[i]
    }
    print (reach >= total) ? 1 : 0
  }' "$READ_LOG" 2>/dev/null || echo 0)
case "$COVERED" in ''|*[!0-9]*) COVERED=0 ;; esac

[ "$COVERED" = "1" ] && exit 0

# Count existing lines that do not appear anywhere in the replacement. This is a
# deliberately crude diff: it asks "is this content going away", not "did the
# line move". Moved lines are not destroyed, so undercounting them is correct.
TMP_NEW=$(mktemp 2>/dev/null) || exit 0
printf '%s\n' "$NEW_CONTENT" > "$TMP_NEW" 2>/dev/null || { rm -f "$TMP_NEW"; exit 0; }

if [ ! -s "$TMP_NEW" ]; then
  # Replacing a real file with nothing destroys all of it.
  DESTROYED="$CURRENT_LINES"
else
  DESTROYED=$(grep -F -x -v -f "$TMP_NEW" -- "$FILE" 2>/dev/null | grep -c '[^[:space:]]' || echo 0)
fi
rm -f "$TMP_NEW"
case "$DESTROYED" in ''|*[!0-9]*) DESTROYED=0 ;; esac

[ "$DESTROYED" -lt "$MAX_DESTROY" ] && exit 0

# The label has to match what this run actually does. A hook that prints
# "BLOCKED" and then exits 0 teaches the reader to ignore the word.
if [ "${CC_WRITE_OVERWRITE_BLOCK:-0}" = "1" ]; then
  LABEL="BLOCKED"
else
  LABEL="WARNING"
fi

echo "" >&2
echo "$LABEL: overwriting content that was never read." >&2
echo "  File:            $FILE ($CURRENT_LINES lines)" >&2
echo "  Lines destroyed: $DESTROYED (present now, absent from the replacement)" >&2
echo "  Read coverage:   the whole file was never read in this session" >&2
echo "" >&2
echo "  This is the shape of issue #78273: a few lines were read, the file was" >&2
echo "  confirmed to have content, and then all of it was replaced." >&2
echo "" >&2
echo "  Read the whole file first, or use Edit for a targeted change." >&2
echo "  To allow this once: CC_WRITE_OVERWRITE_MAX_DESTROY=$((DESTROYED + 1))" >&2
if [ "$LABEL" = "WARNING" ]; then
  echo "  To refuse writes like this instead of warning: CC_WRITE_OVERWRITE_BLOCK=1" >&2
fi

[ "$LABEL" = "BLOCKED" ] && exit 2
exit 0
