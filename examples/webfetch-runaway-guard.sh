#!/bin/bash
# webfetch-runaway-guard.sh — Cap a runaway sequence of WebFetch tool calls that burns cost
#
# Solves: When a research subagent is told to gather many sources, denying a
# single WebFetch is treated as "skip this one" rather than "stop and
# summarize" — so the agent moves to the next URL and keeps fetching. In #65684
# this ran ~98 WebFetch calls (~$1.15) before the user force-killed it with
# Ctrl+C, and the context from the earlier fetches was lost because the agent
# never paused to synthesize.
#
# Existing hooks miss this exact shape:
#   - loop-detector.sh keys on the *same* command repeating; a runaway fetches
#     a *different* URL each call, so it never matches.
#   - api-rate-limit-tracker.sh matches Bash curl/wget/http; the WebFetch *tool*
#     is a separate tool, not a Bash command.
#   - session-rate-monitor.sh is advisory token-rate only and never blocks.
#   - webfetch-domain-allow.sh is the opposite purpose (auto-approve allowlist).
#
# This counts WebFetch *tool* calls in a rolling time window (per session) and,
# once the count crosses a threshold, blocks with a message telling the model to
# stop fetching and summarize what it already has — the behavior the operator
# wanted when they started denying calls. A hard block (not just a warning) is
# what actually caps the spend, since the runaway already ignored the denials.
#
# Defaults are generous so ordinary research is untouched: it takes 50 fetches
# inside 5 minutes to block. The window ages out on its own, so once the model
# summarizes and stops, the next genuine research run starts from zero.
#
# TRIGGER: PreToolUse  MATCHER: "WebFetch"
# Config (all optional):
#   CC_WEBFETCH_RUNAWAY_GUARD=block   block | warn | off
#   CC_WEBFETCH_RUNAWAY_BLOCK=50      block once this many fetches fall inside the window
#   CC_WEBFETCH_RUNAWAY_WARN=30       warn (stderr, non-blocking) at this many
#   CC_WEBFETCH_RUNAWAY_WINDOW=300    rolling window in seconds
#   CC_WEBFETCH_RUNAWAY_DIR           state dir (default: /tmp/cc-webfetch-runaway)
# Related: https://github.com/anthropics/claude-code/issues/65684

INPUT=$(cat)

MODE="${CC_WEBFETCH_RUNAWAY_GUARD:-block}"
[ "$MODE" = "off" ] && exit 0

# Only act on the WebFetch tool. Fail open on anything unexpected.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "WebFetch" ] && exit 0

BLOCK_AT="${CC_WEBFETCH_RUNAWAY_BLOCK:-50}"
WARN_AT="${CC_WEBFETCH_RUNAWAY_WARN:-30}"
WINDOW="${CC_WEBFETCH_RUNAWAY_WINDOW:-300}"
case "$BLOCK_AT" in ''|*[!0-9]*) exit 0;; esac
case "$WARN_AT" in ''|*[!0-9]*) exit 0;; esac
case "$WINDOW" in ''|*[!0-9]*) exit 0;; esac

# Key state per session so one session's research never trips another's guard.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
case "$SID" in ''|*[!A-Za-z0-9_-]*) SID="default";; esac

STATE_DIR="${CC_WEBFETCH_RUNAWAY_DIR:-/tmp/cc-webfetch-runaway}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE="$STATE_DIR/$SID"

NOW=$(date +%s)
CUTOFF=$((NOW - WINDOW))

# Record this call, then keep only timestamps inside the window.
echo "$NOW" >> "$STATE" 2>/dev/null
if [ -f "$STATE" ]; then
    awk -v c="$CUTOFF" '$1 ~ /^[0-9]+$/ && $1 >= c' "$STATE" > "$STATE.tmp" 2>/dev/null && mv "$STATE.tmp" "$STATE" 2>/dev/null
fi

COUNT=$(wc -l < "$STATE" 2>/dev/null | tr -d ' ')
case "$COUNT" in ''|*[!0-9]*) exit 0;; esac

MINS=$((WINDOW / 60))
MSG="This is WebFetch call ${COUNT} within ${MINS} min. A research loop is fetching URL after URL without pausing to synthesize — in #65684 this reached ~98 fetches (~\$1.15) before it was force-killed, and the earlier results were wasted. Stop fetching now and write your answer from the sources you already have; open another fetch only if a specific gap remains. To allow a deeper sweep, raise CC_WEBFETCH_RUNAWAY_BLOCK, set CC_WEBFETCH_RUNAWAY_GUARD=warn to only warn, or =off to disable. State resets after ${WINDOW}s of no fetches: ${STATE}"

if [ "$COUNT" -ge "$BLOCK_AT" ]; then
    if [ "$MODE" = "warn" ]; then
        echo "webfetch-runaway-guard: $MSG" >&2
        exit 0
    fi
    # block (default): structured decision so the model sees the reason.
    jq -n --arg r "$MSG" '{decision: "block", reason: $r}'
    exit 0
elif [ "$COUNT" -ge "$WARN_AT" ]; then
    echo "webfetch-runaway-guard: WebFetch call ${COUNT} within ${MINS} min — consider summarizing what you have before fetching more (#65684). Blocks at ${BLOCK_AT}." >&2
fi

exit 0
