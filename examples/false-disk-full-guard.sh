#!/bin/bash
# false-disk-full-guard.sh — flag the #65880 false "temp filesystem is full" / ENOSPC report
#
# Why: Claude Code's Bash tool substitutes
#        "Command output was lost: the temp filesystem at <dir> is full (0MB free).
#         The child process's stdout/stderr writes failed with ENOSPC."
#      into stdout for ANY command with empty stdout AND a non-zero exit code — e.g.
#      `false`, a no-match `grep`, a failed `test -e`, `cmd 2>/dev/null` that exits
#      non-zero — even when the filesystem has terabytes free (anthropics/claude-code
#      #65880, reproduced on 2.1.150-2.1.160).
#
#      The danger is not cosmetic: the fabricated string is presented to the model AS
#      the command's output, so the model can conclude the disk is full and run
#      destructive cleanup (rm, git prune, docker prune) to "free space" that was never
#      occupied. This hook verifies the claim against real `df` and, when the disk
#      actually has room, tells the model it is the false-positive so it does NOT act
#      destructively.
#
# Event: PostToolUse   MATCHER: "*"
# Action: advisory only (stderr), never blocks, fails open.

set -u

IN=$(cat)

# tool_response may be a plain string or an object; try the common shapes.
RESP=$(printf '%s' "$IN" | jq -r '
  if (.tool_response | type) == "string" then .tool_response
  else (.tool_response.stdout // .tool_response.stderr // .tool_response.output // .tool_response.content // .tool_result // empty)
  end' 2>/dev/null)
# Fallback: scan the whole payload if structured extraction found nothing.
[ -z "$RESP" ] && RESP="$IN"

# Signature of the #65880 fabricated report.
printf '%s' "$RESP" | grep -qiE 'temp filesystem at .* is full \(0+ ?MB free\)|writes failed with ENOSPC' || exit 0

# Which directory did the message blame? Fall back to TMPDIR / /tmp.
DIR=$(printf '%s' "$RESP" | grep -oE 'temp filesystem at [^ ]+' | head -1 | sed 's/^temp filesystem at //')
[ -z "$DIR" ] && DIR="${TMPDIR:-/tmp}"
# The named session dir may already be gone; climb to an existing ancestor.
while [ -n "$DIR" ] && [ "$DIR" != "/" ] && [ ! -d "$DIR" ]; do DIR=$(dirname "$DIR"); done

AVAIL_KB=$(df -Pk "$DIR" 2>/dev/null | awk 'NR==2{print $4}')
# Can't verify → fail open, stay silent (don't second-guess a possibly-real ENOSPC).
case "$AVAIL_KB" in ''|*[!0-9]*) exit 0;; esac

# Only contradict the message when the disk genuinely has room (>100 MB).
if [ "$AVAIL_KB" -gt 102400 ]; then
  AVAIL_H=$(df -Ph "$DIR" 2>/dev/null | awk 'NR==2{print $4}')
  echo "⚠ false-disk-full-guard: the 'temp filesystem is full / ENOSPC' message above is very likely the #65880 false-positive, NOT a real disk-full." >&2
  echo "  Verified free space on ${DIR}: ${AVAIL_H:-plenty}. Claude Code substitutes that message for ANY empty-stdout + non-zero-exit command (a no-match grep, a failed test, \`false\`)." >&2
  echo "  Do NOT run rm / prune / cleanup to 'free space' — the disk is fine. The real result was: empty output, non-zero exit. Re-run as '<cmd>; echo \"[exit \$?]\"' to recover the true exit code." >&2
fi

exit 0
