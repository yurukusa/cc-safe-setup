#!/bin/bash
# ================================================================
# remote-control-billing-classifier.sh — Warn at session start when
#   the parent process tree includes `claude remote-control`, so
#   the operator knows the spawned `claude --print` child will draw
#   from the new Agent SDK monthly credit (Pool 2) starting June 15,
#   2026, separate from interactive usage limits.
# ================================================================
# PURPOSE:
#   Issue #59823 documents the implementation detail that
#   `claude remote-control` spawns one `claude --print --sdk-url …`
#   child per session. The June 15, 2026 billing split routes
#   `claude --print` and Agent SDK usage to a new "automation
#   bucket" (Pool 2) on Pro $20 / Max 5x $100 / Max 20x $200 plans,
#   separate from interactive Claude Code usage. The documentation
#   does not yet classify `claude remote-control` itself, so
#   operators running automation through it can silently double-
#   consume Pool 2 once the cliff lands.
#
#   This hook reads the process tree at session start. When any
#   ancestor command line matches `claude remote-control`, it emits
#   a one-line stderr advisory naming the Pool 2 implication and
#   pointing to the two operator-side audits worth running before
#   June 15. Advisory only (exit 0); does not block the session.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# UPSTREAM:
#   #59823 [DOCS] Billing implications for `claude remote-control`
#          on June 15th (Pool 2 classification of the child
#          `claude --print` process is undocumented as of 2026-05-28)
#
# SETUP:
#   {
#     "hooks": {
#       "SessionStart": [
#         {
#           "matcher": "",
#           "hooks": [
#             { "type": "command",
#               "command": "$HOME/.claude/hooks/remote-control-billing-classifier.sh" }
#           ]
#         }
#       ]
#     }
#   }
#
# BEHAVIOR:
#   - No `claude remote-control` ancestor → silent pass.
#   - Ancestor found → stderr advisory + exit 0 (does not block).
#
# CONFIGURATION (env vars):
#   CC_REMOTE_CONTROL_DISABLE          Set to "1" to disable the hook.
#   CC_REMOTE_CONTROL_PROCESS_OVERRIDE Comma-separated cmdlines to scan
#                                      instead of live `ps` output.
#                                      Used by tests; also lets CI
#                                      simulate a remote-control parent.
#   CC_REMOTE_CONTROL_PATTERN          Override the cmdline regex
#                                      (default: "claude remote-control").
# ================================================================

set -u

if [ "${CC_REMOTE_CONTROL_DISABLE:-0}" = "1" ]; then
    exit 0
fi

PATTERN="${CC_REMOTE_CONTROL_PATTERN:-claude remote-control}"

# Read stdin (SessionStart JSON payload) but do not require its shape.
# The hook only inspects the process tree, not the payload.
if [ ! -t 0 ]; then
    cat >/dev/null 2>&1 || true
fi

# Gather candidate cmdlines: either the override (for tests) or
# the live ancestor process tree via `ps`.
CMDLINES=""
if [ -n "${CC_REMOTE_CONTROL_PROCESS_OVERRIDE:-}" ]; then
    CMDLINES="$CC_REMOTE_CONTROL_PROCESS_OVERRIDE"
else
    # Walk parent PIDs upward and collect cmdlines. We avoid `ps
    # --forest` because BusyBox does not implement it; instead we
    # follow PPID via /proc when available, falling back to ps -p.
    PID=$$
    DEPTH=0
    while [ "$PID" != "1" ] && [ "$DEPTH" -lt 20 ]; do
        if [ -r "/proc/$PID/cmdline" ]; then
            CMD=$(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null)
            CMDLINES="${CMDLINES}${CMD}
"
            PPID=$(awk '/^PPid:/ {print $2}' "/proc/$PID/status" 2>/dev/null)
        else
            CMD=$(ps -o args= -p "$PID" 2>/dev/null)
            CMDLINES="${CMDLINES}${CMD}
"
            PPID=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')
        fi
        if [ -z "$PPID" ] || [ "$PPID" = "$PID" ]; then
            break
        fi
        PID="$PPID"
        DEPTH=$((DEPTH+1))
    done
fi

# Look for the pattern in any candidate cmdline.
if printf '%s' "$CMDLINES" | grep -q -- "$PATTERN"; then
    cat >&2 <<EOF

⚠️  Session started under \`claude remote-control\`.

   Starting 2026-06-15, the child \`claude --print --sdk-url …\`
   process that remote-control spawns will draw from the new
   Agent SDK monthly credit (Pool 2), separate from interactive
   Claude Code usage. The documentation does not yet classify
   \`claude remote-control\` itself (see issue #59823), so
   automation that drives sessions through it can silently
   consume Pool 2 once the cliff lands.

   Two pre-June-15 audits worth running:
     1. \`ps --forest -p \$(pgrep -f 'claude remote-control')\`
        — confirm the children you expect, no stray sessions.
     2. Open https://support.claude.com/en/articles/15036540
        and verify the one-time Agent SDK opt-in is pressed
        for the account that owns the remote-control server.

   This is an advisory; the session continues.
   Set CC_REMOTE_CONTROL_DISABLE=1 to silence.

EOF
fi

exit 0
