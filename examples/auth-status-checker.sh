#!/bin/bash
# auth-status-checker.sh — Surface the Cluster 19 candidate (Authentication Silent Failure)
# situation at session start for operators running long sessions or 3P credential chains
#
# Background:
#   In the 17 days between 2026-05-14 and 2026-05-30, anthropics/claude-code accumulated
#   at least 39 open issues related to authentication silent failure. The unifying root
#   mechanism: the operator sees an authentication success signal at one point in time
#   and discovers — sometimes hours, sometimes days later — that the authenticated state
#   has silently lapsed. The user-side experience is identical across surfaces: log in
#   successfully, work for a while, hit a 401 / "Not logged in" / "Needs authentication"
#   / 403 error wall, with no upstream signal that re-auth was required.
#
#   This is the same structural shape as Cluster 1 (Sub-agent Observability — "done"
#   report with empty tool calls) and Cluster 11F (Cowork handoff silent failure —
#   completed result that never relays back): a positive-looking surface signal that
#   does not reflect the underlying state.
#
#   Seven sub-cluster axes documented (2026-05-30):
#     19A MCP OAuth failure paths (#59460 / #59725 / #60260 / #61139)
#     19B macOS sleep/wake invalidation (#59937 / #60104)
#     19C Session expiry silent failure (#60938 / #62354 HIGH BLOCKER /
#         #61912 / #63919 2026-05-30 fresh)
#     19D VS Code extension forced daily re-login (#61923)
#     19E Multi-window auth state inconsistency (#62790)
#     19F Cowork authentication failure (#61563, intersection with Cluster 11)
#     19G Third-party SSO silent expiry (#63185 3P Bedrock SSO day-2+ / #62103)
#
#   Cluster 19 is still a candidate; tracked at cluster-tracker.html pending full
#   promotion criteria (15+ aggregate reactions or tenth independent axis surfacing).
#
#   Reference:
#     https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f  (field guide)
#
# What this hook does:
#   On SessionStart, when CC_AUTH_STATUS_CHECKER_REMIND=1 is set, emits a stderr
#   advisory naming the five operator-side mitigations from the Cluster 19 field
#   guide. The hook is fully opt-in — silent by default. The advisory does not
#   try to detect the operator's auth surface state; auto-detection across MCP,
#   VS Code, Cowork, Bedrock, and macOS sleep/wake would be unreliable, and a
#   wrong guess is worse than no guess.
#
# When this hook does NOT emit anything:
#   - CC_AUTH_STATUS_CHECKER_REMIND is unset or empty
#   - CC_AUTH_STATUS_CHECKER_DISABLE=1
#   - CC_AUTH_STATUS_CHECKER_QUIET=1
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/auth-status-checker.sh" }]
#     }]
#   }
# }
# And in your shell rc, opt in:
#   export CC_AUTH_STATUS_CHECKER_REMIND=1
#
# Env vars:
#   CC_AUTH_STATUS_CHECKER_REMIND=1   — opt-in trigger (required to emit)
#   CC_AUTH_STATUS_CHECKER_DISABLE=1  — never emit (overrides REMIND)
#   CC_AUTH_STATUS_CHECKER_QUIET=1    — silent (overrides REMIND)
#
# Design notes:
#   - Opt-in by default. The advisory is only useful to operators with long sessions,
#     3P credential chains, multi-machine VS Code, or macOS sleep/wake patterns.
#     Defaulting silent avoids noise for short-session single-surface operators.
#   - No auto-detection of auth surface. Operators may use MCP, VS Code, Cowork,
#     Bedrock, Brave, or any combination simultaneously; detecting which surfaces
#     are active would require shell-side env var inspection and would still miss
#     in-process credential state. The advisory lets the operator self-select the
#     applicable mitigations.
#   - Candidate-cluster framing. The advisory clearly states Cluster 19 is a
#     candidate (not yet promoted) and links the field guide for the full context.
#   - Never blocks. Exit always 0.

set -u

# Hard disable path
if [ "${CC_AUTH_STATUS_CHECKER_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Quiet path
if [ "${CC_AUTH_STATUS_CHECKER_QUIET:-0}" = "1" ]; then
  exit 0
fi

# Opt-in gate
if [ "${CC_AUTH_STATUS_CHECKER_REMIND:-0}" != "1" ]; then
  exit 0
fi

cat >&2 <<'EOF'
[auth-status-checker] Cluster 19 candidate advisory: authentication state can
silently lapse across multiple Claude Code surfaces. 39+ open issues filed in
the 17 days from 2026-05-14 to 2026-05-30 document seven structural surfaces:

  19A MCP OAuth failure paths (DCR re-runs, empty accessToken, token-expired loop)
  19B macOS sleep/wake invalidation (401 persists, full reboot to clear)
  19C Session expiry silent failure (HIGH BLOCKER: #62354, fresh: #63919 2026-05-30)
  19D VS Code extension forced daily re-login on multi-machine shared accounts
  19E Multi-window /account state inconsistency after one window logs in/out
  19F Cowork authentication failure (intersection with Cluster 11)
  19G Third-party SSO silent expiry (Bedrock day-2+, Brave API credentials)

The unifying pattern: log in succeeds, the session reports success, and then
hours or days later a downstream call returns 401 / "Not logged in" / 403 with
no upstream signal that re-auth was required. Cost: the operator's productive
work that hit the silent failure mid-execution is lost, and re-auth is gated
behind a session that may itself be in the failed state (per #60938).

Five operator-side mitigations (apply the ones that match your surface):

  1) Periodic /account health check (axes 19C / 19G)
     For long sessions, run /account every 30-60 minutes. When the check
     returns "Not authenticated," re-auth before the next substantive
     operation rather than discovering the expiry mid-task.

  2) Single-window discipline for auth changes (axis 19E)
     Close all Claude Code windows before any explicit re-auth. After
     re-auth, open new windows rather than reusing existing ones.

  3) CLI preference over VS Code extension for shared accounts (axis 19D)
     If the same Anthropic account is used across multiple machines,
     prefer the CLI. The extension's refresh-token rejection on shared
     accounts is the specific failure mode.

  4) Daily re-auth checkpoint for third-party SSO (axis 19G)
     Build a daily morning checkpoint: run /account and verify any 3P
     credentials (Bedrock, Brave Search API) before the first
     substantive request. Day-2 silent expiry surfaces only when a
     downstream call fails — a deliberate checkpoint prevents that loss.

  5) Scheduled reboot for macOS sleep/wake (axis 19B)
     If your workflow has consistent overnight sleep, schedule a morning
     reboot. The 401 state persists across explicit re-auth and only
     clears on full reboot per #60104.

This is a candidate cluster — full Cluster 19 promotion happens when
cumulative reactions cross 15 or a tenth independent axis surfaces. The
cc-safe-setup tracker (cluster-tracker.html) records the current state.

To silence this advisory once you have applied the relevant mitigations:
  unset CC_AUTH_STATUS_CHECKER_REMIND
  # or
  export CC_AUTH_STATUS_CHECKER_QUIET=1

References:
  https://github.com/anthropics/claude-code/issues/63919  (2026-05-30 fresh)
  https://github.com/anthropics/claude-code/issues/63185  (3P Bedrock SSO day-2+)
  https://github.com/anthropics/claude-code/issues/62354  (HIGH BLOCKER session expiry)
  https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f  (field guide)
EOF

exit 0
