#!/bin/bash
# auth-macos-sleep-detector.sh — Detect recent macOS sleep/wake and advise auth re-verification
# (Cluster 19 candidate, axis 19B — macOS sleep/wake silent auth invalidation)
#
# Background:
#   Cluster 19 candidate axis 19B documents a class of authentication failures
#   where macOS suspends the system mid-session, the auth token times out
#   during the sleep window, and the user only sees the failure after the next
#   prompt — silent expiration without a refresh signal.
#
#   Anchor cases in axis 19B:
#     #59937 — Claude Code session loses MCP auth after macOS wake from sleep
#     #60104 — Persistent 401 after laptop close/open cycle, no visible expiry signal
#
#   The structural shape: a session that was healthy before sleep returns 401
#   or "not authenticated" on the first tool call after wake, even though the
#   visible CLI state shows the same authenticated user. The recovery requires
#   running the auth-status-checker advisory or executing `/login` manually —
#   not just retrying the failed tool call.
#
#   This hook is a SessionStart advisory that fires when:
#     - the operating system is macOS (uname -s == Darwin), AND
#     - pmset reports a Wake event within the last CC_AUTH_MACOS_SLEEP_WINDOW
#       seconds (default 1800 = 30 minutes), AND
#     - the operator has not already seen the advisory in this session
#
#   The advisory recommends running `bash ~/.claude/hooks/auth-status-checker.sh`
#   with CC_AUTH_STATUS_REMIND=1 to verify the token's freshness before the
#   first tool call of the post-wake session.
#
#   Reference:
#     https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f (auth cluster field guide)
#
# When this hook does NOT emit anything:
#   - CC_AUTH_MACOS_SLEEP_DISABLE=1
#   - CC_AUTH_MACOS_SLEEP_QUIET=1
#   - the operating system is not macOS (Linux, WSL, etc.)
#   - pmset is unavailable or returns no recent Wake event
#   - the advisory has already fired in this session
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/auth-macos-sleep-detector.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_AUTH_MACOS_SLEEP_DISABLE=1       — never emit
#   CC_AUTH_MACOS_SLEEP_QUIET=1         — silent (process but never write to stderr)
#   CC_AUTH_MACOS_SLEEP_WINDOW=<secs>   — wake-event freshness threshold (default 1800)
#   CC_AUTH_MACOS_SLEEP_STATE_DIR=<p>   — one-shot state dir override (default ~/.claude/state)
#   CC_AUTH_MACOS_SLEEP_SESSION_ID=<id> — session id override (tests)
#   CC_AUTH_MACOS_SLEEP_FORCE_OS=<os>   — uname -s override (tests; use "Darwin"/"Linux")
#   CC_AUTH_MACOS_SLEEP_PMSET_CMD=<cmd> — pmset binary override (tests; e.g. a stub script)
#
# Design notes:
#   - Opt-out. Like oauth-refresh-monitor.sh, the signal is specific (macOS +
#     recent wake event) and the cost of missing the advisory (silent 401 loop
#     until the operator manually re-auths) exceeds the cost of a false advisory.
#   - One-shot per session. The advisory fires once per session. A separate
#     wake event in a long-running session does not re-fire — that would be
#     covered by the PostToolUse oauth-refresh-monitor.sh signature scan.
#   - Never blocks. Exit always 0. The auth state recovery is operator-action;
#     a blocking hook would only add pain.
#   - Non-macOS systems exit silently. Linux/WSL/other do not have the same
#     sleep/wake auth invalidation pattern; the hook is a no-op there.
#   - Test-friendly. The OS detection and pmset command are both overridable
#     via env vars so the test harness can simulate Darwin + recent wake on
#     any platform.

set -u

# Disable switch — exit silently if disabled
if [[ "${CC_AUTH_MACOS_SLEEP_DISABLE:-0}" = "1" ]]; then
    exit 0
fi

# OS detection (overridable for tests)
OS_NAME="${CC_AUTH_MACOS_SLEEP_FORCE_OS:-$(uname -s 2>/dev/null || echo unknown)}"
if [[ "$OS_NAME" != "Darwin" ]]; then
    exit 0
fi

# pmset command resolution
PMSET_CMD="${CC_AUTH_MACOS_SLEEP_PMSET_CMD:-pmset}"
if ! command -v "$PMSET_CMD" >/dev/null 2>&1 && [[ ! -x "$PMSET_CMD" ]]; then
    exit 0
fi

# Wake-event freshness threshold in seconds (default 1800 = 30 minutes)
WINDOW="${CC_AUTH_MACOS_SLEEP_WINDOW:-1800}"
if ! [[ "$WINDOW" =~ ^[0-9]+$ ]]; then
    WINDOW=1800
fi

# State directory and one-shot guard
STATE_DIR="${CC_AUTH_MACOS_SLEEP_STATE_DIR:-$HOME/.claude/state}"
mkdir -p "$STATE_DIR" 2>/dev/null

SESSION_ID="${CC_AUTH_MACOS_SLEEP_SESSION_ID:-${CLAUDE_SESSION_ID:-default}}"
GUARD_FILE="$STATE_DIR/auth-macos-sleep-${SESSION_ID}.fired"

if [[ -f "$GUARD_FILE" ]]; then
    exit 0
fi

# Read pmset log and find the most recent Wake event
# pmset -g log emits lines like:
#   2026-05-31 18:42:15 +0900 Wake               Wake from Normal Sleep ...
# We grep for "Wake" and parse the last entry's timestamp.
PMSET_OUTPUT=$("$PMSET_CMD" -g log 2>/dev/null | grep -E '\bWake\b' | tail -1)

if [[ -z "$PMSET_OUTPUT" ]]; then
    exit 0
fi

# Extract timestamp (first two fields: "YYYY-MM-DD HH:MM:SS")
WAKE_TS_STR=$(echo "$PMSET_OUTPUT" | awk '{print $1, $2}')

# Convert wake timestamp to epoch
# macOS date: date -j -f "%Y-%m-%d %H:%M:%S" "..." +%s
# Linux date: date -d "..." +%s
WAKE_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$WAKE_TS_STR" +%s 2>/dev/null)
if [[ -z "$WAKE_EPOCH" ]] || ! [[ "$WAKE_EPOCH" =~ ^[0-9]+$ ]]; then
    # Fallback for GNU date
    WAKE_EPOCH=$(date -d "$WAKE_TS_STR" +%s 2>/dev/null)
fi

if [[ -z "$WAKE_EPOCH" ]] || ! [[ "$WAKE_EPOCH" =~ ^[0-9]+$ ]]; then
    exit 0
fi

NOW_EPOCH=$(date +%s)
GAP=$(( NOW_EPOCH - WAKE_EPOCH ))

if [[ $GAP -lt 0 ]] || [[ $GAP -gt $WINDOW ]]; then
    exit 0
fi

# Mark one-shot guard
touch "$GUARD_FILE" 2>/dev/null

# Quiet mode: process but do not write to stderr
if [[ "${CC_AUTH_MACOS_SLEEP_QUIET:-0}" = "1" ]]; then
    exit 0
fi

# Emit advisory
cat >&2 <<EOF

────────────────────────────────────────────────────────────────────
  Auth advisory — Cluster 19 axis 19B (macOS sleep/wake)
────────────────────────────────────────────────────────────────────
  macOS Wake event detected ${GAP}s ago (within ${WINDOW}s window).

  The Cluster 19 axis 19B pattern: a session healthy before sleep
  may return 401 on the first tool call after wake — the auth token
  silently expires during the sleep window with no refresh signal.

  Anchor cases: #59937, #60104.

  Recommended check (run once before the first tool call):

    CC_AUTH_STATUS_REMIND=1 bash ~/.claude/hooks/auth-status-checker.sh

  If the check reports a stale token, run:

    /login

  to refresh the auth state cleanly. A bare retry of the failing tool
  call will loop the 401 silently.

  Field guide: https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f

  (This advisory fires once per session. To disable:
   export CC_AUTH_MACOS_SLEEP_DISABLE=1)
────────────────────────────────────────────────────────────────────

EOF

exit 0
