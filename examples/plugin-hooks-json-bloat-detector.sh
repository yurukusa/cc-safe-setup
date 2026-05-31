#!/bin/bash
# ================================================================
# plugin-hooks-json-bloat-detector.sh — Detect duplicated hook
#   registrations inside plugin hooks.json files (additive growth
#   from the multi-agent dispatch path).
# ================================================================
# PURPOSE:
#   Issue #64022 documents a class where a plugin's
#   `hooks/hooks.json` registrations multiply additively in
#   multi-agent sessions (observed 1× → 122× per hook). At high
#   multiples every hook fires N times per tool call and tool
#   output is corrupted. The reporter's plugin had no additive
#   writer; the only mechanism that fits is the harness re-running
#   its plugin-hook load/merge and appending instead of replacing.
#
#   The growth is silent until output corruption surfaces it. This
#   hook scans every installed plugin's hooks.json at session
#   start, counts duplicate command-string registrations within
#   each file, and warns when a single command appears more than a
#   threshold (default 5 times) — well below the 122× blowup but
#   well above any legitimate "one event, one command, multiple
#   matchers" registration shape.
#
# DETECTION MODEL:
#   SessionStart fires once per session. We walk every
#   `~/.claude/plugins/cache/**/hooks/hooks.json` (plus the canonical
#   `~/.claude/plugins/marketplace/**/hooks/hooks.json` if it exists),
#   parse each JSON, and within each file count how many times each
#   distinct command string appears across all event types. If any
#   command string appears more than CC_PLUGIN_HOOKS_BLOAT_THRESHOLD
#   times in a single hooks.json, emit a warning identifying the
#   plugin path, the command, and the duplicate count.
#
#   We deliberately ignore the cross-plugin case (the same command
#   appearing in two different plugins is legitimate) and the
#   multi-event case (the same command registered for PreToolUse
#   AND PostToolUse — count each event-bucket separately).
#
# CLUSTER:
#   Candidate cluster #21 — Plugin lifecycle integrity gap
#   Sub-axis 21A — additive hook-registration growth (#64022).
#
# TRIGGER: SessionStart  MATCHER: (any)
#
# ENV:
#   CC_PLUGIN_HOOKS_BLOAT_THRESHOLD     default 5  (warn when same command appears >5×)
#   CC_PLUGIN_HOOKS_BLOAT_DISABLE       non-empty → silent
#   CC_PLUGIN_HOOKS_BLOAT_QUIET         non-empty → silent
#   CC_PLUGIN_HOOKS_BLOAT_ROOT          default $HOME/.claude/plugins
#   CC_PLUGIN_HOOKS_BLOAT_STATE_DIR     default /tmp/cc-plugin-hooks-bloat
# ================================================================

set -u

# Disable / quiet
if [ -n "${CC_PLUGIN_HOOKS_BLOAT_DISABLE:-}" ] || [ -n "${CC_PLUGIN_HOOKS_BLOAT_QUIET:-}" ]; then
    exit 0
fi

THRESHOLD="${CC_PLUGIN_HOOKS_BLOAT_THRESHOLD:-5}"
PLUGINS_ROOT="${CC_PLUGIN_HOOKS_BLOAT_ROOT:-$HOME/.claude/plugins}"
STATE_DIR="${CC_PLUGIN_HOOKS_BLOAT_STATE_DIR:-/tmp/cc-plugin-hooks-bloat}"
WARN_FILE="$STATE_DIR/last-warn"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# If plugin root doesn't exist, nothing to scan
[ -d "$PLUGINS_ROOT" ] || exit 0

# Need jq for JSON parsing; fail-soft if missing
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Read input (Claude Code passes session context on stdin; we don't use it for
# this detector, but consume it so the harness doesn't block).
INPUT=$(cat 2>/dev/null || true)

# Track findings across all plugin hooks.json files
declare -a FINDINGS=()

# Walk every hooks.json under the plugins tree
while IFS= read -r -d '' HOOKS_FILE; do
    # Skip if not a file (broken symlink etc.)
    [ -f "$HOOKS_FILE" ] || continue

    # Skip if the file is not valid JSON (fail-soft, do not warn on broken files
    # — those are a separate problem)
    if ! jq -e . "$HOOKS_FILE" >/dev/null 2>&1; then
        continue
    fi

    # Extract every hook command string, grouped per event-bucket so that the
    # same command legitimately registered for PreToolUse AND PostToolUse
    # doesn't trip the detector. Output format: "<event>\t<command>"
    EVENT_CMDS=$(jq -r '
        (.hooks // {}) | to_entries[] |
        .key as $event |
        (.value // []) | .[] |
        ((.hooks // []) | .[]) |
        select(.command != null) |
        ($event + "\t" + (.command | tostring))
    ' "$HOOKS_FILE" 2>/dev/null) || continue

    [ -z "$EVENT_CMDS" ] && continue

    # Count duplicates per event+command pair
    DUPES=$(printf '%s\n' "$EVENT_CMDS" | sort | uniq -c | awk -v t="$THRESHOLD" '$1 > t {print $0}')

    if [ -n "$DUPES" ]; then
        # Strip the canonical install root prefix for readability in the warning
        DISPLAY_PATH="${HOOKS_FILE#$PLUGINS_ROOT/}"
        FINDINGS+=("$DISPLAY_PATH")
        FINDINGS+=("$DUPES")
        FINDINGS+=("---")
    fi
done < <(find "$PLUGINS_ROOT" -type f -name 'hooks.json' -path '*/hooks/*' -print0 2>/dev/null)

# No findings → silent exit
if [ "${#FINDINGS[@]}" -eq 0 ]; then
    exit 0
fi

# Debounce: only warn once per hour even if the session restarts repeatedly
NOW_S=$(date +%s)
LAST_WARN=0
if [ -f "$WARN_FILE" ]; then
    LAST_WARN=$(cat "$WARN_FILE" 2>/dev/null || echo 0)
fi
HOUR_AGO=$((NOW_S - 3600))
if [ "$LAST_WARN" -gt "$HOUR_AGO" ] 2>/dev/null; then
    exit 0
fi
printf '%s' "$NOW_S" > "$WARN_FILE" 2>/dev/null

# Emit advisory warning
cat >&2 <<EOF

⚠️  Plugin hooks.json bloat detected — duplicate hook registrations.

One or more installed plugins have a hooks.json file where the same command
string appears more than ${THRESHOLD} times within a single event bucket.
This is the fingerprint of the additive growth pattern documented in
anthropics/claude-code Issue #64022 — the harness's plugin-hook load/merge
path can re-run and append instead of replacing, causing each hook to fire
N times per tool call.

Findings:
EOF

for line in "${FINDINGS[@]}"; do
    printf '  %s\n' "$line" >&2
done

cat >&2 <<EOF

What to do:

  1. Restore canonical hooks.json from the plugin source (a fresh
     reinstall of the plugin from its canonical marketplace usually works).
  2. If the file regrows after restoration, file the recurrence against
     anthropics/claude-code Issue #64022 with your version and a count.
  3. Lower this hook's threshold if the false-positive rate is acceptable
     for your environment (export CC_PLUGIN_HOOKS_BLOAT_THRESHOLD=3).

This warning is advisory. Set CC_PLUGIN_HOOKS_BLOAT_DISABLE=1 to silence.
EOF

exit 0
