#!/bin/bash
# hook-self-disable-detector.sh — Detect when previously-active hooks have been silently removed
# Trigger: SessionStart
# Matcher: (empty — runs once at every session start)
#
# Background: Claude Code sessions can edit settings.json and remove hooks
# that were previously active. Over weeks of accumulation this can silently
# disable safeguards. One documented case: a Claude Code session disabled
# its own early-detection hook, and 193 GB of WSL bloat accumulated before
# the operator noticed. See drafts/active/2026-05-16-self-disabled-safeguard-wsl-bloat.md
# in cc-loop for the source incident.
#
# This hook complements settings-integrity-monitor.sh:
#   settings-integrity-monitor: warns when settings.json checksum changes
#   hook-self-disable-detector: warns which specific hooks were removed
#
# Behavior:
#   1. On every SessionStart, capture the current set of (event, matcher, command) triples
#      from ~/.claude/settings.json and .claude/settings.json.
#   2. Compare against the most recent snapshot in ~/.claude/.hook-state-snapshots/.
#   3. If a hook present in the previous snapshot is missing from the current state,
#      print a warning to stderr listing which event/matcher/command was removed.
#   4. Save the current state as a new snapshot regardless.
#
# Environment overrides (mainly for tests):
#   CC_HOOK_STATE_DIR     — directory for snapshots (default: $HOME/.claude/.hook-state-snapshots)
#   CC_USER_SETTINGS      — user settings.json path (default: $HOME/.claude/settings.json)
#   CC_PROJECT_SETTINGS   — project settings.json path (default: .claude/settings.json)
#   CC_HOOK_DISABLE_QUIET — if "1", suppress the informational first-run message

set -u

STATE_DIR="${CC_HOOK_STATE_DIR:-$HOME/.claude/.hook-state-snapshots}"
USER_SETTINGS="${CC_USER_SETTINGS:-$HOME/.claude/settings.json}"
PROJECT_SETTINGS="${CC_PROJECT_SETTINGS:-.claude/settings.json}"
QUIET="${CC_HOOK_DISABLE_QUIET:-0}"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Extract the (event, matcher, command) triples from a settings.json file.
# Each line is "<event>|<matcher>|<command>". Missing fields become empty strings.
extract_hooks() {
    local file="$1"
    [ -f "$file" ] || return 0
    jq -r '
        (.hooks // {})
        | to_entries[]
        | .key as $event
        | .value[]?
        | ($event + "|" + (.matcher // "") + "|" + ((.hooks // [])[]? | (.command // "")))
    ' "$file" 2>/dev/null
}

# Build current state: lines prefixed with origin (user/project) for clarity.
CURRENT=$(
    {
        extract_hooks "$USER_SETTINGS" | sed 's/^/user|/'
        extract_hooks "$PROJECT_SETTINGS" | sed 's/^/project|/'
    } | sort -u
)

# Locate the most recent prior snapshot (lexicographic timestamp order) and
# read its contents BEFORE writing the new snapshot, so the comparison is not
# polluted by the file we are about to create.
PREV_SNAPSHOT=$(ls -1 "$STATE_DIR"/snapshot-*.txt 2>/dev/null | sort | tail -n 1)
PREVIOUS=""
if [ -n "$PREV_SNAPSHOT" ] && [ -f "$PREV_SNAPSHOT" ]; then
    PREVIOUS=$(cat "$PREV_SNAPSHOT" 2>/dev/null)
fi

# Use nanosecond precision so rapid successive invocations get distinct files.
NEW_SNAPSHOT="$STATE_DIR/snapshot-$(date +%Y%m%d-%H%M%S-%N).txt"
printf '%s\n' "$CURRENT" > "$NEW_SNAPSHOT"

if [ -z "$PREV_SNAPSHOT" ]; then
    if [ "$QUIET" != "1" ]; then
        COUNT=$(printf '%s' "$CURRENT" | grep -c '^' || true)
        echo "ℹ hook-self-disable-detector: first run, snapshot of $COUNT hook entries saved." >&2
    fi
    exit 0
fi

# Lines that were in the previous snapshot but are missing from the current state.
REMOVED=$(comm -23 <(printf '%s\n' "$PREVIOUS" | sort -u) <(printf '%s\n' "$CURRENT" | sort -u) | grep -v '^$' || true)

if [ -n "$REMOVED" ]; then
    REMOVED_COUNT=$(printf '%s\n' "$REMOVED" | grep -c '^' || true)
    echo "⚠ hook-self-disable-detector: $REMOVED_COUNT hook entries were active in the previous session but are absent now." >&2
    echo "  This can mask self-disabled safeguards. Review each entry:" >&2
    printf '%s\n' "$REMOVED" | while IFS='|' read -r origin event matcher command; do
        # Truncate command to keep the warning readable.
        short_cmd=$(printf '%s' "$command" | head -c 120)
        echo "    [$origin] event=$event matcher='$matcher' command='$short_cmd'" >&2
    done
    echo "  Previous snapshot: $PREV_SNAPSHOT" >&2
    echo "  Current snapshot:  $NEW_SNAPSHOT" >&2
fi

exit 0
