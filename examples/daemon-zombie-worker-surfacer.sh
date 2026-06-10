#!/bin/bash
# ================================================================
# daemon-zombie-worker-surfacer.sh — Surface orphaned / zombie
# background workers at session start via `claude daemon status`.
# ================================================================
# PURPOSE:
#   Detect background workers that are still registered (and may still
#   be consuming tokens) from PRIOR sessions, and surface them at the
#   start of a new session — when the operator can actually act.
#
# WHY THIS MATTERS:
#   Background subagents/workers can keep running after the operator
#   stops them. The "Background tasks" panel showing "Stopped" is not
#   always terminal, and the zombie state is INVISIBLE unless you run
#   `claude daemon status`. Real reports:
#     #66339 — two background subagents resurrected after being stopped
#              multiple times, ran 21+ hours, consumed ~160k tokens,
#              burned a 4-hour usage limit and triggered overage charges;
#              deleting the PARENT session was the only thing that stopped
#              them.
#     #66358 — after an auto-update the daemon orphaned the prior version's
#              workers (control-key version skew): alive but unreachable.
#   The harness fix is provider-side. This hook is the operator-side
#   detector: it runs `claude daemon status` at session start and, if any
#   workers are still registered or a version skew is present, surfaces an
#   advisory so the operator can inspect (`claude agents --json`) or restart.
#
# TRIGGER: SessionStart
# MATCHER: "" (SessionStart has no matcher)
# DECISION CONTROL: none — advisory only, non-blocking, fail-open.
#
# CONFIGURATION (environment variables):
#   CC_DAEMON_SURFACER_DISABLE   set "1" to disable the hook entirely
#   CC_DAEMON_STATUS_TIMEOUT     seconds to wait for `claude daemon status`
#                                (default 8)
#   CC_DAEMON_STATUS_CMD         override the status command (used by tests
#                                to inject canned output)
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "SessionStart": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/daemon-zombie-worker-surfacer.sh"
#         }]
#       }]
#     }
#   }
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/66339
#   https://github.com/anthropics/claude-code/issues/66358
# ================================================================

set -uo pipefail

[ "${CC_DAEMON_SURFACER_DISABLE:-0}" = "1" ] && exit 0

TIMEOUT="${CC_DAEMON_STATUS_TIMEOUT:-8}"

# Obtain the daemon status text. Tests inject canned output via
# CC_DAEMON_STATUS_CMD; otherwise call the real CLI (fail-open if absent).
if [ -n "${CC_DAEMON_STATUS_CMD:-}" ]; then
    STATUS=$(eval "$CC_DAEMON_STATUS_CMD" 2>/dev/null)
else
    command -v claude >/dev/null 2>&1 || exit 0
    STATUS=$(timeout "$TIMEOUT" claude daemon status 2>/dev/null)
fi

# Empty output (timeout, error, no such subcommand) → fail-open silently.
[ -z "$STATUS" ] && exit 0

# Background-worker count. The status prints a line such as:
#   bg workers:   8 running (control.sock), 8 in roster.json
#   bg workers:   0 in roster.json (control unreachable)
# Take the largest integer on the "bg workers:" line as the count.
WORKER_LINE=$(printf '%s\n' "$STATUS" | grep -iE 'bg workers:' | head -1)
WORKERS=$(printf '%s' "$WORKER_LINE" | grep -oE '[0-9]+' | sort -nr | head -1)
WORKERS="${WORKERS:-0}"

# Version skew = workers orphaned by an auto-update, locked to an old
# control key (e.g. "5 from a different CLI version").
SKEW_LINE=$(printf '%s\n' "$STATUS" | grep -iE 'from a different (CLI )?version' | head -1)
SKEW=$(printf '%s' "$SKEW_LINE" | grep -oE '[0-9]+' | head -1)
SKEW="${SKEW:-0}"

# Healthy / common case: nothing registered, no skew → silent no-op.
if [ "$WORKERS" -eq 0 ] && [ "$SKEW" -eq 0 ]; then
    exit 0
fi

DETAIL=""
[ "$WORKERS" -gt 0 ] && DETAIL="${DETAIL}  - ${WORKERS} background worker(s) still registered (from a prior session).\n"
[ "$SKEW" -gt 0 ] && DETAIL="${DETAIL}  - ${SKEW} of them are from a different CLI version — orphaned by an auto-update, alive but unreachable.\n"

cat >&2 <<EOF
<system-reminder>
BACKGROUND WORKER CHECK — possible zombie / orphaned background work detected.

$(printf '%b' "$DETAIL")
Background workers can keep running (and consuming tokens) after you stop them
— the "Background tasks" panel showing "Stopped" is not always terminal
(#66339: ~160k tokens burned over 21h after repeated stops; #66358: auto-update
orphans). If you did NOT intend these to be running:

  1. Inspect them:        claude agents --json
  2. The stop that worked in #66339 was deleting the PARENT session — the
     panel "Stop" alone did not stop them.
  3. Orphans from a version skew (#66358) cannot be re-attached; restart the
     daemon / Claude Code fully to clear them.

Advisory only — nothing is blocked. Set CC_DAEMON_SURFACER_DISABLE=1 to silence.
</system-reminder>
EOF

exit 0
