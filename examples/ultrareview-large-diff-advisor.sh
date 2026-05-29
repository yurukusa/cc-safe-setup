#!/bin/bash
# ================================================================
# ultrareview-large-diff-advisor.sh — SessionStart advisory for
# Cluster 18 candidate (/ultrareview crash burns credit on large PRs)
# ================================================================
# PURPOSE:
#   Between 2026-05-27 and 2026-05-29, six independent issues
#   reported the same shape of failure: invoking /ultrareview on a
#   large PR causes a server-side crash with no findings returned,
#   yet the user's daily credit counter is still decremented.
#
#   The shared error: `Review crashed before producing findings.
#   See session logs for details.`
#
#   Issues:
#     #62696  3rd crash burns credit (v2.1.150)
#     #62709  PR #7 review crashed, 0 findings
#     #62787  2 consecutive crashes, 2/3 credits burned
#             (21 files / 84KB diff)
#     #62876  Find phase crash, Setup phase complete
#     #63117  1 crash decrements credit
#             (6 files / 2,185 insertions)
#     #63522  same-branch 2 consecutive crashes, 2/3 credits burned
#
#   Common structural traits:
#     1. Large PRs crash at a noticeably higher rate
#     2. Find phase is the failure point
#     3. Retrying on the same branch produces the same crash
#
#   The crash is server-side. A user-side hook cannot prevent it.
#   This hook surfaces the advisory at SessionStart so the operator
#   knows the size thresholds and the three-axis defense BEFORE
#   they invoke /ultrareview against a large PR. It does not block.
#
# DETECTION:
#   At SessionStart, the hook measures the current branch's diff
#   against a base branch (default "main") using
#   `git diff --shortstat <base>...HEAD`. It extracts file count
#   and insertion count and compares against thresholds.
#
#   - file count >= BLOCK threshold OR
#     lines insertions >= BLOCK threshold
#     → elevated crash rate advisory
#   - file count >= WARN threshold OR
#     lines insertions >= WARN threshold
#     → caution advisory
#   - otherwise → silent (fail open)
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# OUTPUT:
#   Advisory only, never blocks. Prints to stderr.
#
# CONFIGURATION:
#   CC_ULTRAREVIEW_ADVISOR_DISABLE=1     — disable entirely
#   CC_ULTRAREVIEW_ADVISOR_QUIET=1       — silence after
#                                          acknowledgment
#   CC_ULTRAREVIEW_FILES_WARN            — file count caution
#                                          threshold (default 6)
#   CC_ULTRAREVIEW_FILES_BLOCK           — file count elevated
#                                          threshold (default 16)
#   CC_ULTRAREVIEW_LINES_WARN            — insertion line caution
#                                          threshold (default 500)
#   CC_ULTRAREVIEW_LINES_BLOCK           — insertion line elevated
#                                          threshold (default 1500)
#   CC_ULTRAREVIEW_BRANCH_BASE           — base branch for diff
#                                          (default "main")
#   CC_ULTRAREVIEW_GIT_DIR               — override working tree
#                                          (default: current dir)
#
# RELATED:
#   Cluster 18 candidate entry, tracked since 2026-05-29
#   English field guide:
#     https://gist.github.com/yurukusa/f7363d83e3f4bcbb1bd7cf66a1c64752
#   Anchor case for resolution tracking:
#     https://github.com/anthropics/claude-code/issues/62696
#
# DESIGN NOTES:
#   - The hook does NOT block /ultrareview. The operator decides.
#     Many large PRs do succeed; the elevated rate is not a
#     guarantee of failure. The hook surfaces the trade-off.
#   - When the working tree is not a git repository, or when the
#     base branch does not exist, the hook fails open (exit 0
#     silent). It does NOT warn that detection failed.
#   - The hook reads the stdin JSON envelope but does not use it;
#     SessionStart hooks receive context that is not relevant
#     here. The stdin is consumed to avoid SIGPIPE on the caller.

set -u

if [ "${CC_ULTRAREVIEW_ADVISOR_DISABLE:-0}" = "1" ]; then
    exit 0
fi
if [ "${CC_ULTRAREVIEW_ADVISOR_QUIET:-0}" = "1" ]; then
    exit 0
fi

# Consume stdin if provided (SessionStart hooks receive JSON input)
if [ ! -t 0 ]; then
    cat >/dev/null 2>&1 || true
fi

FILES_WARN="${CC_ULTRAREVIEW_FILES_WARN:-6}"
FILES_BLOCK="${CC_ULTRAREVIEW_FILES_BLOCK:-16}"
LINES_WARN="${CC_ULTRAREVIEW_LINES_WARN:-500}"
LINES_BLOCK="${CC_ULTRAREVIEW_LINES_BLOCK:-1500}"
BRANCH_BASE="${CC_ULTRAREVIEW_BRANCH_BASE:-main}"

# Validate integer thresholds; fall back to defaults silently
validate_int() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}
validate_int "$FILES_WARN"  || FILES_WARN=6
validate_int "$FILES_BLOCK" || FILES_BLOCK=16
validate_int "$LINES_WARN"  || LINES_WARN=500
validate_int "$LINES_BLOCK" || LINES_BLOCK=1500

GIT_DIR="${CC_ULTRAREVIEW_GIT_DIR:-$PWD}"

# Detect repo + base branch presence; fail open on any missing
if ! command -v git >/dev/null 2>&1; then
    exit 0
fi
if ! git -C "$GIT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi
if ! git -C "$GIT_DIR" rev-parse --verify "$BRANCH_BASE" >/dev/null 2>&1; then
    exit 0
fi

# Get the merge-base diff stat between the base branch and HEAD
SHORTSTAT=$(git -C "$GIT_DIR" diff --shortstat "$BRANCH_BASE"...HEAD 2>/dev/null) || exit 0

# Parse: " N files changed, M insertions(+), K deletions(-)"
# Some outputs omit insertions or deletions; handle both.
if [ -z "$SHORTSTAT" ]; then
    exit 0
fi

FILES=$(echo "$SHORTSTAT" | grep -oE '[0-9]+ file' | head -n 1 | grep -oE '[0-9]+' || echo 0)
INSERTIONS=$(echo "$SHORTSTAT" | grep -oE '[0-9]+ insertion' | head -n 1 | grep -oE '[0-9]+' || echo 0)

# Default to 0 if extraction fails
[ -z "$FILES" ] && FILES=0
[ -z "$INSERTIONS" ] && INSERTIONS=0

# Decide severity
SEVERITY=""
if [ "$FILES" -ge "$FILES_BLOCK" ] || [ "$INSERTIONS" -ge "$LINES_BLOCK" ]; then
    SEVERITY="elevated"
elif [ "$FILES" -ge "$FILES_WARN" ] || [ "$INSERTIONS" -ge "$LINES_WARN" ]; then
    SEVERITY="caution"
fi

if [ -z "$SEVERITY" ]; then
    exit 0
fi

{
    echo "ADVISORY: Current branch diff vs $BRANCH_BASE is $FILES files / $INSERTIONS insertions."
    if [ "$SEVERITY" = "elevated" ]; then
        echo "  Cluster 18 candidate: /ultrareview crashes at an elevated rate above"
        echo "    ${FILES_BLOCK} files or ${LINES_BLOCK} insertions. Six issues over three days"
        echo "    (#62696 #62709 #62787 #62876 #63117 #63522) burned credits with no findings."
    else
        echo "  Cluster 18 candidate: /ultrareview enters the caution range above"
        echo "    ${FILES_WARN} files or ${LINES_WARN} insertions. Crash rate climbs as size grows."
    fi
    echo "  Three user-side defenses before invoking /ultrareview:"
    echo "    1. Split the PR into logical chunks (git rebase -i + git checkout -b)"
    echo "    2. Do not retry on the same branch; the same crash burns a second credit"
    echo "    3. Fall back to /code-review (local, no cloud crash exposure)"
    echo "  Anchor case to subscribe for the upstream fix signal:"
    echo "    https://github.com/anthropics/claude-code/issues/62696"
    echo "  Field guide (six issues, three structural traits, defenses):"
    echo "    https://gist.github.com/yurukusa/f7363d83e3f4bcbb1bd7cf66a1c64752"
    echo "  Silence after acknowledgment: export CC_ULTRAREVIEW_ADVISOR_QUIET=1"
} >&2

exit 0
