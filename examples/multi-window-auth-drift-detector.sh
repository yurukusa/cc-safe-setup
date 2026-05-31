#!/bin/bash
# multi-window-auth-drift-detector.sh — Detect on-disk credentials drift mid-session
# (Cluster 19 candidate, axis 19E — multi-window /account state inconsistency)
#
# Background:
#   Cluster 19 axis 19E documents a class of authentication failures unique to
#   operators running multiple Claude Code windows in parallel. The structural
#   shape: Window A authenticates with Account X and starts a long session.
#   While Window A is mid-session, Window B either (a) logs in with Account Y,
#   (b) logs out, or (c) re-authenticates — any action that rewrites the
#   on-disk credential store. Window A keeps working from the cached in-memory
#   token, but `/account` in Window A now reports "Not authenticated" while
#   the same dialog's USAGE panel still shows real quota consumption.
#
#   Anchor case: #62790 — "/account shows 'Not authenticated' in older windows
#   after another window logs in/out, while Usage bars still populate".
#
#   The contradiction is observable: same dialog, "Not authenticated" + live
#   session quota bars. The operator does not know if their next substantive
#   tool call will succeed or fail.
#
#   This hook is a PostToolUse advisory that fires when:
#     - the credentials file has been modified since the session start, AND
#     - the operator has not already seen the advisory in this session
#
#   The advisory does not block the tool call. It surfaces the drift so the
#   operator can run /account, decide whether the in-memory auth is still the
#   intended account, and re-auth deliberately if needed.
#
#   Reference:
#     https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f (auth cluster field guide)
#
# Why a hook helps:
#   Without the advisory, the failure mode is: Window A operator continues
#   working, hits a 401 mid-task hours later, loses the in-flight work. With
#   the advisory, the operator learns at the next tool call that the on-disk
#   credentials have drifted, and can verify deliberately rather than discover
#   the lapse during a costly task.
#
# When this hook does NOT emit anything:
#   - CC_AUTH_DRIFT_DISABLE=1
#   - CC_AUTH_DRIFT_QUIET=1
#   - no credentials file exists at any known path
#   - the credentials file mtime is older than the session start
#   - the advisory has already fired in this session
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/multi-window-auth-drift-detector.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_AUTH_DRIFT_DISABLE=1          — never emit
#   CC_AUTH_DRIFT_QUIET=1            — silent (process but never write to stderr)
#   CC_AUTH_DRIFT_CRED_FILE=<path>   — credentials file path override (tests)
#   CC_AUTH_DRIFT_SESSION_START=<ep> — session start epoch override (tests)
#   CC_AUTH_DRIFT_STATE_DIR=<path>   — one-shot state dir override (default ~/.claude/state)
#   CC_AUTH_DRIFT_SESSION_ID=<id>    — session id override (tests)
#
# Design notes:
#   - Opt-out. The advisory is specific (credentials file changed since
#     session start) and the cost of a missed advisory (silent 401 mid-task)
#     exceeds the cost of a false positive (one stderr advisory the operator
#     dismisses).
#   - One-shot per session. The advisory fires once. Further drifts in the
#     same session do not re-fire — the operator already knows.
#   - Never blocks. Exit always 0. The auth recovery is operator-action.
#   - Looks at multiple known credential file paths. The exact path varies
#     across Claude Code versions and platforms; the hook checks each in
#     order and uses the first that exists.

set -u

if [[ "${CC_AUTH_DRIFT_DISABLE:-0}" = "1" ]]; then
    exit 0
fi

CRED_FILE="${CC_AUTH_DRIFT_CRED_FILE:-}"
if [[ -z "$CRED_FILE" ]]; then
    for candidate in \
        "$HOME/.config/claude/auth.json" \
        "$HOME/.config/anthropic/configs/default.json" \
        "$HOME/.claude/credentials.json" \
        "$HOME/.claude/.credentials.json"; do
        if [[ -f "$candidate" ]]; then
            CRED_FILE="$candidate"
            break
        fi
    done
fi

if [[ -z "$CRED_FILE" ]] || [[ ! -f "$CRED_FILE" ]]; then
    exit 0
fi

STATE_DIR="${CC_AUTH_DRIFT_STATE_DIR:-$HOME/.claude/state}"
mkdir -p "$STATE_DIR" 2>/dev/null

SESSION_ID="${CC_AUTH_DRIFT_SESSION_ID:-${CLAUDE_SESSION_ID:-default}}"
GUARD_FILE="$STATE_DIR/auth-drift-${SESSION_ID}.fired"
START_FILE="$STATE_DIR/auth-drift-${SESSION_ID}.start"

if [[ -f "$GUARD_FILE" ]]; then
    exit 0
fi

# Read or record session start epoch. The first hook firing of a session
# records the start time; subsequent firings compare the credentials mtime
# against it.
SESSION_START="${CC_AUTH_DRIFT_SESSION_START:-}"
if [[ -z "$SESSION_START" ]]; then
    if [[ -f "$START_FILE" ]]; then
        SESSION_START=$(cat "$START_FILE" 2>/dev/null)
    fi
    if [[ -z "$SESSION_START" ]] || ! [[ "$SESSION_START" =~ ^[0-9]+$ ]]; then
        date +%s > "$START_FILE" 2>/dev/null
        exit 0
    fi
fi

# Get credentials file mtime in epoch seconds. Linux uses stat -c %Y;
# macOS uses stat -f %m. Try both for portability.
CRED_MTIME=$(stat -c %Y "$CRED_FILE" 2>/dev/null)
if [[ -z "$CRED_MTIME" ]] || ! [[ "$CRED_MTIME" =~ ^[0-9]+$ ]]; then
    CRED_MTIME=$(stat -f %m "$CRED_FILE" 2>/dev/null)
fi
if [[ -z "$CRED_MTIME" ]] || ! [[ "$CRED_MTIME" =~ ^[0-9]+$ ]]; then
    exit 0
fi

# If credentials were not modified since the session started, no drift.
if (( CRED_MTIME <= SESSION_START )); then
    exit 0
fi

# Drift detected. Mark one-shot guard.
touch "$GUARD_FILE" 2>/dev/null

if [[ "${CC_AUTH_DRIFT_QUIET:-0}" = "1" ]]; then
    exit 0
fi

GAP=$(( CRED_MTIME - SESSION_START ))

cat >&2 <<EOF

────────────────────────────────────────────────────────────────────
  Auth advisory — Cluster 19 axis 19E (multi-window drift)
────────────────────────────────────────────────────────────────────
  Credentials file modified ${GAP}s after this session started:
    ${CRED_FILE}

  The Cluster 19 axis 19E pattern: when another Claude Code window
  logs in/out or re-authenticates, this window's in-memory token may
  silently diverge from on-disk state. /account in this window can
  report "Not authenticated" while the USAGE quota bars still show
  live consumption. The next substantive tool call may 401 mid-task.

  Anchor case: #62790.

  Recommended check before the next costly tool call:

    /account

  If "Auth method" reports "Not authenticated" but USAGE bars are
  populated, the in-memory token is stale. Close all Claude Code
  windows, then re-authenticate in a single window and start fresh
  sessions — re-using the existing window will re-surface the drift.

  Field guide: https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f

  (This advisory fires once per session. To disable:
   export CC_AUTH_DRIFT_DISABLE=1)
────────────────────────────────────────────────────────────────────

EOF

exit 0
