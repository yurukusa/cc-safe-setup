#!/bin/bash
# skill-truncation-detector.sh — Restore the Skill-listing truncation
# warning that v2.1.144 silently removed.
#
# Solves: v2.1.144 (2026-05-19) release note —
#   "Skill-listing truncation is no longer shown as a startup notification
#    — run /doctor for the full breakdown."
#
# The change moved the truncation signal from passive (visible at startup,
# user is told) to active (user has to remember to run /doctor). The three
# concrete failure modes the old startup notice surfaced — skill-count
# crossing the limit, name collisions, malformed frontmatter — all now go
# silent by default.
#
# This hook fires on SessionStart, scans the user's skill directories for
# the same three failure modes, and emits a system-reminder when any are
# detected. Effectively restores the v2.1.143-and-earlier behavior at the
# hook layer.
#
# This is the "recognition-without-arrest" pattern's *opposite* failure mode:
# the harness used to surface a recognition signal, and now refuses to. The
# hook re-surfaces it.
#
# Related Issues:
#   #60226 (@suwayama, 2026-05-18) — recognition-without-arrest framework
#   Anthropic v2.1.144 release notes (2026-05-19) — the notification removal
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# CONFIGURATION (environment variables):
#   CC_SKILL_COUNT_THRESHOLD  default 80 — warn when skills exceed this count
#   CC_SKILL_DIRS             default "~/.claude/skills" — colon-separated
#                                                  list of skill directories
#                                                  to scan
#   CC_SKILL_TRUNCATION_DISABLE  set to "1" to disable the detector
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "SessionStart": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/skill-truncation-detector.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_SKILL_TRUNCATION_DISABLE:-0}" = "1" ] && exit 0

THRESHOLD="${CC_SKILL_COUNT_THRESHOLD:-80}"
DEFAULT_DIRS="${HOME}/.claude/skills"
SKILL_DIRS="${CC_SKILL_DIRS:-$DEFAULT_DIRS}"
LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="unknown-$(date +%s)"

# Once per session, even if multiple SessionStart hooks fire.
WARN_LOG="$LOG_DIR/skill-truncation-warned-$SESSION_ID"
[ -f "$WARN_LOG" ] && exit 0

# Collect skill files. Each skill is a directory containing SKILL.md, per
# the standard layout used by Anthropic and most plugin authors.
SKILL_FILES=()
IFS=':' read -ra DIRS <<< "$SKILL_DIRS"
for dir in "${DIRS[@]}"; do
    dir="${dir/#\~/$HOME}"
    [ -d "$dir" ] || continue
    while IFS= read -r f; do
        SKILL_FILES+=("$f")
    done < <(find "$dir" -maxdepth 3 -name "SKILL.md" 2>/dev/null)
done

SKILL_COUNT=${#SKILL_FILES[@]}

# Check 1: skill count near or above threshold
COUNT_WARNING=""
if [ "$SKILL_COUNT" -ge "$THRESHOLD" ]; then
    COUNT_WARNING="Skill count is $SKILL_COUNT, at or above the configured threshold of $THRESHOLD. Some skills may be truncated from the system context."
fi

# Check 2: name collisions. Read the `name:` field from frontmatter of each
# skill file. Multiple skills with the same name will collide at registration.
declare -A NAMES_SEEN
COLLISION_LIST=""
MALFORMED_LIST=""
for f in "${SKILL_FILES[@]}"; do
    # Extract name from YAML frontmatter (between first two --- lines).
    NAME=$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); print; exit}' "$f" 2>/dev/null | tr -d '"' | tr -d "'" | xargs)
    if [ -z "$NAME" ]; then
        # No name field, no frontmatter, or unreadable. Skill registration
        # falls back to directory name in some versions; in others it fails
        # silently. Either way, this is a failure mode the old notice
        # surfaced.
        MALFORMED_LIST="${MALFORMED_LIST}  - ${f/#$HOME/~}: no 'name:' field in frontmatter
"
        continue
    fi
    if [ -n "${NAMES_SEEN[$NAME]:-}" ]; then
        COLLISION_LIST="${COLLISION_LIST}  - '$NAME': ${NAMES_SEEN[$NAME]/#$HOME/~} and ${f/#$HOME/~}
"
    else
        NAMES_SEEN[$NAME]="$f"
    fi
done

# If no findings, exit silently. (The hook is a tripwire; absence of
# finding is the common case and should not be noisy.)
if [ -z "$COUNT_WARNING" ] && [ -z "$COLLISION_LIST" ] && [ -z "$MALFORMED_LIST" ]; then
    : > "$WARN_LOG"
    exit 0
fi

# Build the system-reminder.
{
    echo "<system-reminder>"
    echo "SKILL-LISTING TRUNCATION DETECTOR — restoring the startup signal"
    echo "that v2.1.144 silently removed."
    echo ""
    if [ -n "$COUNT_WARNING" ]; then
        echo "* COUNT: $COUNT_WARNING"
        echo ""
    fi
    if [ -n "$COLLISION_LIST" ]; then
        echo "* NAME COLLISIONS (one of the colliding skills will not load):"
        printf '%s' "$COLLISION_LIST"
        echo ""
    fi
    if [ -n "$MALFORMED_LIST" ]; then
        echo "* MALFORMED FRONTMATTER (skills without a 'name:' field):"
        printf '%s' "$MALFORMED_LIST"
        echo ""
    fi
    echo "Run \`/doctor\` for the full Claude Code report on skill"
    echo "registration. Fix the listed items above to ensure all skills"
    echo "register correctly."
    echo ""
    echo "To silence this detector intentionally, set"
    echo "CC_SKILL_TRUNCATION_DISABLE=1 in your environment."
    echo "</system-reminder>"
} >&2

# Mark warned so we don't double-fire in this session.
: > "$WARN_LOG"

# SessionStart hooks should not block; we surface the info and exit 0.
exit 0
