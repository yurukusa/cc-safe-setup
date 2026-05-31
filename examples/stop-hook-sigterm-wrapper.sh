#!/bin/bash
# ================================================================
# stop-hook-sigterm-wrapper.sh — Wrap the claude CLI so an
#   external supervisor can distinguish "completed" from "killed
#   mid-work" when SIGTERM (e.g. `timeout` exit code 124) bypasses
#   the configured Stop hook.
# ================================================================
# PURPOSE:
#   Issue #64017 documents a class where SIGTERM termination of
#   the claude process (typically by a wrapper enforcing an
#   execution timeout) kills the CLI without firing the configured
#   Stop hook. Any state the Stop hook was responsible for writing
#   is left stale — it still reflects the previous run — so a
#   supervisor reading that file cannot tell "completed" apart
#   from "killed mid-work."
#
#   The reporter's own band-aid was an outer wrapper that observes
#   the wrapped command's exit code and writes its own termination
#   marker before reading any hook output. This script ships a
#   clean, parseable version of that band-aid: it wraps the claude
#   invocation, traps SIGTERM/SIGINT, and writes a JSON state file
#   on every transition (running, completed, killed-sigterm,
#   killed-sigint, killed-timeout, killed-sigkill, error). The
#   supervisor reads the state file and can decisively
#   differentiate the termination cause.
#
#   This is not a fix for the upstream Stop-hook-on-SIGTERM gap.
#   It is the operator-side workaround that lets supervisors stop
#   misattributing prior-run completion summaries to current
#   killed runs.
#
# CLUSTER:
#   Candidate cluster #21 — Plugin lifecycle integrity gap
#   Sub-axis 21D — signal gap (Stop hook silent on SIGTERM, #64017).
#
# USAGE:
#   1. Place this script on PATH (e.g. ~/bin/claude-wrapped.sh)
#   2. Optionally alias claude='/path/to/stop-hook-sigterm-wrapper.sh'
#   3. Or invoke directly: stop-hook-sigterm-wrapper.sh -p "your prompt"
#   4. Supervisor reads $CC_STOP_SIGTERM_MARKER_DIR/state.json after
#      the wrapped invocation completes (or is killed)
#
#   The state file is JSON, one line per state transition:
#     {"state":"running","timestamp":"2026-05-31T10:00:00+0900","pid":12345}
#     {"state":"completed","timestamp":"2026-05-31T10:30:00+0900","exit_code":0,"duration_s":1800}
#
#   States:
#     running         — claude was launched, no termination signal yet
#     completed       — claude exited with code 0
#     killed-sigterm  — claude received SIGTERM (exit 143)
#     killed-sigint   — claude received SIGINT / Ctrl-C (exit 130)
#     killed-timeout  — wrapper saw exit 124 from `timeout` wrapper above us
#     killed-sigkill  — claude exited with 137 (SIGKILL, cannot be trapped)
#     error           — claude exited with any other non-zero code
#
# ENV:
#   CC_STOP_SIGTERM_MARKER_DIR   default $HOME/.claude/run-state
#   CC_STOP_SIGTERM_WRAPPER_CMD  default "claude" (override for testing or alt CLI path)
#   CC_STOP_SIGTERM_DISABLE      non-empty → wrapper passes through without writing markers
# ================================================================

set -u

# Disable pass-through
if [ -n "${CC_STOP_SIGTERM_DISABLE:-}" ]; then
    exec "${CC_STOP_SIGTERM_WRAPPER_CMD:-claude}" "$@"
fi

MARKER_DIR="${CC_STOP_SIGTERM_MARKER_DIR:-$HOME/.claude/run-state}"
WRAPPED_CMD="${CC_STOP_SIGTERM_WRAPPER_CMD:-claude}"
STATE_FILE="$MARKER_DIR/state.json"

mkdir -p "$MARKER_DIR" 2>/dev/null || {
    # If we cannot create the marker dir, fall back to pass-through
    exec "$WRAPPED_CMD" "$@"
}

# Portable ISO 8601 timestamp with timezone
timestamp() {
    if date +%Y-%m-%dT%H:%M:%S%z >/dev/null 2>&1; then
        date +%Y-%m-%dT%H:%M:%S%z
    else
        date -u +%Y-%m-%dT%H:%M:%SZ
    fi
}

write_state() {
    local state="$1"
    local extra="$2"
    local now
    now=$(timestamp)
    local payload="{\"state\":\"$state\",\"timestamp\":\"$now\",\"pid\":$$"
    if [ -n "$extra" ]; then
        payload="$payload,$extra"
    fi
    payload="$payload}"
    # Atomic write: rename from temp
    local tmp
    tmp=$(mktemp "$MARKER_DIR/.state.json.XXXXXX" 2>/dev/null) || {
        # mktemp failed; best-effort direct write
        printf '%s\n' "$payload" > "$STATE_FILE" 2>/dev/null
        return
    }
    printf '%s\n' "$payload" > "$tmp"
    mv -f "$tmp" "$STATE_FILE" 2>/dev/null
}

# Track start time for duration calculation on exit
START_S=$(date +%s)

# Initial state: running
write_state "running" ""

# Trap signals — write the killed state before exiting. We re-raise
# the same signal so the parent supervisor still sees the normal
# 128+N exit code, preserving wait() semantics.
on_sigterm() {
    local elapsed=$(( $(date +%s) - START_S ))
    write_state "killed-sigterm" "\"exit_code\":143,\"duration_s\":$elapsed"
    # Kill the child if still alive
    if [ -n "${CLAUDE_PID:-}" ] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
        kill -TERM "$CLAUDE_PID" 2>/dev/null
    fi
    exit 143
}
on_sigint() {
    local elapsed=$(( $(date +%s) - START_S ))
    write_state "killed-sigint" "\"exit_code\":130,\"duration_s\":$elapsed"
    if [ -n "${CLAUDE_PID:-}" ] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
        kill -INT "$CLAUDE_PID" 2>/dev/null
    fi
    exit 130
}
trap on_sigterm TERM
trap on_sigint INT

# Launch the wrapped command in background so we can wait() and trap.
# Pass through all args verbatim.
"$WRAPPED_CMD" "$@" &
CLAUDE_PID=$!

# Wait for completion. `wait` is interrupted by trapped signals.
wait "$CLAUDE_PID"
EXIT_CODE=$?

# Compute duration
ELAPSED=$(( $(date +%s) - START_S ))

# Map exit code to state
case $EXIT_CODE in
    0)
        write_state "completed" "\"exit_code\":0,\"duration_s\":$ELAPSED"
        ;;
    124)
        # `timeout` parent exit code — wrapped command was killed by
        # an outer `timeout` wrapper.
        write_state "killed-timeout" "\"exit_code\":124,\"duration_s\":$ELAPSED"
        ;;
    130)
        write_state "killed-sigint" "\"exit_code\":130,\"duration_s\":$ELAPSED"
        ;;
    137)
        # SIGKILL cannot be trapped, but we can record it post-mortem.
        write_state "killed-sigkill" "\"exit_code\":137,\"duration_s\":$ELAPSED"
        ;;
    143)
        write_state "killed-sigterm" "\"exit_code\":143,\"duration_s\":$ELAPSED"
        ;;
    *)
        write_state "error" "\"exit_code\":$EXIT_CODE,\"duration_s\":$ELAPSED"
        ;;
esac

exit $EXIT_CODE
