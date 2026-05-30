#!/bin/bash
# auth-expiry-reminder.sh — Daily checkpoint reminder for authentication-state verification
# in long-running Claude Code sessions (Cluster 19 candidate, axes 19C / 19G)
#
# Background:
#   Cluster 19 candidate (Authentication Silent Failure) — 39+ open Claude Code issues
#   filed 2026-05-14 through 2026-05-30 document a pattern where the operator's
#   authentication state silently lapses across multiple surfaces. Two axes within
#   the cluster are most cost-effective to address with a daily checkpoint:
#
#     19C — Session expiry silent failure
#           (#60938 / #62354 HIGH BLOCKER / #61912 / #63919 2026-05-30 fresh)
#     19G — Third-party SSO silent expiry
#           (#63185 3P Bedrock SSO day-2+ / #62103 Brave Search API)
#
#   The shared structural shape: the auth surface reports success at one point in
#   time, the operator works for a while, then a downstream call returns 401 /
#   "Not logged in" / "Needs authentication" with no upstream signal that re-auth
#   was required. The cost is the productive work that hit the silent failure
#   mid-execution — recovery is gated behind a re-auth that may itself be in the
#   failed state (per #60938).
#
#   The checkpoint pattern: at the start of each calendar day, before the first
#   substantive request, verify the auth surface state. Day-2 silent expiry
#   surfaces only when a downstream call fails — a deliberate checkpoint moves
#   the discovery from mid-task failure to a controlled boundary.
#
#   Companion hook: auth-status-checker.sh (PR #490) names the full five-mitigation
#   menu; this hook focuses on the time-based daily checkpoint specifically.
#
#   Reference:
#     https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f  (field guide)
#
# What this hook does:
#   On SessionStart, when CC_AUTH_EXPIRY_REMINDER_REMIND=1 is set, checks whether
#   the operator has already been reminded today (based on a date-stamped state
#   file). If today's reminder has not fired, emits a short stderr advisory
#   naming the two verification commands (Anthropic /account; the operator's own
#   3P credential check) and stamps the state file to suppress the reminder for
#   the rest of the calendar day.
#
#   The state file resets at the calendar-day boundary. The next morning's
#   session start fires the reminder again, before the day's first substantive
#   request.
#
# When this hook does NOT emit anything:
#   - CC_AUTH_EXPIRY_REMINDER_REMIND is unset or empty
#   - CC_AUTH_EXPIRY_REMINDER_DISABLE=1
#   - CC_AUTH_EXPIRY_REMINDER_QUIET=1
#   - Today's reminder has already been emitted (state file matches today's date)
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/auth-expiry-reminder.sh" }]
#     }]
#   }
# }
# And in your shell rc, opt in:
#   export CC_AUTH_EXPIRY_REMINDER_REMIND=1
#
# Env vars:
#   CC_AUTH_EXPIRY_REMINDER_REMIND=1   — opt-in trigger (required to emit)
#   CC_AUTH_EXPIRY_REMINDER_DISABLE=1  — never emit
#   CC_AUTH_EXPIRY_REMINDER_QUIET=1    — silent
#   CC_AUTH_EXPIRY_REMINDER_STATE_DIR=<path> — state dir (default $HOME/.claude)
#   CC_AUTH_EXPIRY_REMINDER_DATE=<YYYY-MM-DD> — date override (tests only)
#
# Design notes:
#   - One-shot per calendar day. The reminder fires at the first SessionStart of
#     the day and stays silent for the rest of the day. Multi-session operators
#     do not get the same reminder N times.
#   - Calendar-day boundary, not 24-hour rolling. A session at 23:55 followed by
#     a session at 00:05 the next day correctly fires the next-day reminder, even
#     though only 10 minutes have passed.
#   - Companion to auth-status-checker. The checker hook names the full mitigation
#     menu when the operator wants to read it; this hook is the daily-cadence
#     trigger that surfaces specifically the two checkpoint commands.
#   - Never blocks. Exit always 0.

set -u

# Hard disable path
if [ "${CC_AUTH_EXPIRY_REMINDER_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Quiet path
if [ "${CC_AUTH_EXPIRY_REMINDER_QUIET:-0}" = "1" ]; then
  exit 0
fi

# Opt-in gate
if [ "${CC_AUTH_EXPIRY_REMINDER_REMIND:-0}" != "1" ]; then
  exit 0
fi

# Resolve today's date (allow override for tests)
TODAY="${CC_AUTH_EXPIRY_REMINDER_DATE:-}"
if [ -z "$TODAY" ]; then
  TODAY=$(date '+%Y-%m-%d' 2>/dev/null) || exit 0
fi

STATE_DIR="${CC_AUTH_EXPIRY_REMINDER_STATE_DIR:-$HOME/.claude}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="$STATE_DIR/auth-expiry-reminder.last"

# Check whether today's reminder has already fired
if [ -f "$STATE_FILE" ]; then
  LAST_DATE=$(head -1 "$STATE_FILE" 2>/dev/null)
  if [ "$LAST_DATE" = "$TODAY" ]; then
    exit 0
  fi
fi

# Stamp the state file with today's date before emitting (so a hook that crashes
# mid-emit does not re-fire on the next invocation).
printf '%s\n' "$TODAY" > "$STATE_FILE" 2>/dev/null || true

cat >&2 <<EOF
[auth-expiry-reminder] Daily authentication checkpoint ($TODAY).

Cluster 19 candidate (Authentication Silent Failure) documents 39+ open Claude
Code issues where authentication state silently lapses between sessions. Day-2
silent expiry surfaces only when a downstream call fails — a deliberate
checkpoint at the day's first session moves the discovery from mid-task failure
to a controlled boundary.

Before the first substantive request of the day, verify:

  1) Anthropic auth surface — run /account and confirm authenticated state.
     If "Not authenticated," re-auth before the next operation.

  2) Third-party credential chains — for each 3P credential your workflow
     depends on (Bedrock, Brave Search API, MCP OAuth servers, etc.), run the
     credential's verification command. For Bedrock SSO this is typically
     'aws sts get-caller-identity' or equivalent. Day-2+ silent expiry is the
     specific failure mode at #63185.

References for the silent-failure patterns this checkpoint catches:
  https://github.com/anthropics/claude-code/issues/62354  (HIGH BLOCKER session expiry)
  https://github.com/anthropics/claude-code/issues/63919  (2026-05-30 fresh, macOS)
  https://github.com/anthropics/claude-code/issues/63185  (3P Bedrock SSO day-2+)
  https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f  (field guide)

This reminder fires once per calendar day. To turn it off:
  unset CC_AUTH_EXPIRY_REMINDER_REMIND
  # or
  export CC_AUTH_EXPIRY_REMINDER_QUIET=1

Companion hook: auth-status-checker.sh names the full five-mitigation menu
when you need the broader Cluster 19 context.
EOF

exit 0
