#!/bin/bash
# oauth-refresh-monitor.sh — Detect OAuth refresh corruption patterns in tool output
# and warn before the operator hits the persistent 401 loop (Cluster 19 candidate, axis 19A)
#
# Background:
#   Cluster 19 candidate axis 19A documents OAuth refresh failure paths where a
#   transient upstream error during a refresh operation corrupts the credentials
#   state into a persistent broken loop. The specific anchor case:
#
#     #61912 (2026-05-23) — OAuth refresh corrupts credentials state during
#     transient upstream 5xx → persistent 401 loop. A single transient error
#     during refresh creates a permanent broken state.
#
#   The pattern is structurally distinct from straightforward 401 expiry: the
#   operator's credential state was valid just before the refresh, the upstream
#   returned 5xx on the refresh request, and now subsequent requests return 401
#   even though the user did not log out and the original session was not
#   expired. The recovery requires a full re-auth, not just a retry.
#
#   Adjacent cases in axis 19A:
#     #59460 — MCP OAuth re-runs DCR on every authenticate, orphaning prior tokens
#     #59725 — Slack MCP OAuth stores empty accessToken after flow completion
#     #60260 — MCP OAuth completes but token is not honored
#     #61139 — Shopify MCP token-expired loop after multi-shop switch
#
#   All share the structural shape: an OAuth flow surface reports success and a
#   downstream call fails with 401 / "Needs authentication" / similar. The
#   common detection signal is the appearance of one of these strings in tool
#   output AFTER a successful login or refresh signal.
#
#   Reference:
#     https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f  (field guide)
#
# What this hook does:
#   On PostToolUse, scans tool output for OAuth-refresh-corruption signatures.
#   When a signature is detected, emits a one-shot per-session stderr advisory
#   recommending the recovery path (full re-auth, not a retry) and the
#   verification steps from the auth-status-checker companion hook.
#
#   Detection signatures (case-insensitive):
#     - "needs authentication"
#     - "401 unauthorized" + "refresh" within the same tool output
#     - "oauth" + "expired" within the same tool output
#     - "refresh token rejected"
#     - "401" + "token" within the same tool output (broad fallback)
#
# When this hook does NOT emit anything:
#   - CC_OAUTH_REFRESH_MONITOR_DISABLE=1
#   - CC_OAUTH_REFRESH_MONITOR_QUIET=1
#   - tool output does not contain any of the detection signatures
#   - the same signature already fired the advisory in this session
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/oauth-refresh-monitor.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_OAUTH_REFRESH_MONITOR_DISABLE=1     — never emit
#   CC_OAUTH_REFRESH_MONITOR_QUIET=1       — silent
#   CC_OAUTH_REFRESH_MONITOR_STATE_DIR=<p> — one-shot state dir
#   CC_OAUTH_REFRESH_MONITOR_SESSION_ID=<id> — session id override (tests)
#
# Design notes:
#   - Opt-out, not opt-in. Unlike the other Cluster 19 hooks (auth-status-checker,
#     auth-expiry-reminder) which need explicit REMIND=1 to fire, this hook
#     fires automatically when the signature appears. The reasoning: the
#     signature is specific enough that a false positive is unlikely, and the
#     cost of missing the advisory (an operator entering the persistent 401 loop
#     without knowing) exceeds the cost of an occasional spurious advisory.
#   - One-shot per session. The advisory fires once per session per signature.
#     Repeating the same advisory N times in a session would itself become
#     noise.
#   - Never blocks. Exit always 0. The corruption pattern is server-side; a
#     blocking hook would only add operator pain without preventing the
#     corruption.
#
# The registration was missing from this header. The installer reads TRIGGER
# and MATCHER from here and falls back to PreToolUse / Bash when both are
# absent, so this hook was being registered at a moment where the field it
# reads is always empty: it installed, it appeared in the settings, and it
# did nothing. Measured 2026-08-04 across examples/: 14 files were like this.
# TRIGGER: PostToolUse
# MATCHER: ""

set -u

# Disable path
if [ "${CC_OAUTH_REFRESH_MONITOR_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Quiet path
if [ "${CC_OAUTH_REFRESH_MONITOR_QUIET:-0}" = "1" ]; then
  exit 0
fi

# Read PostToolUse payload from stdin
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

# Extract tool output. Try jq first; fall back to a permissive grep.
TOOL_OUTPUT=""
if command -v jq >/dev/null 2>&1; then
  TOOL_OUTPUT=$(printf '%s' "$INPUT" | jq -r '
    .tool_response.output //
    .tool_response //
    .output //
    empty
  ' 2>/dev/null)
fi
if [ -z "$TOOL_OUTPUT" ]; then
  TOOL_OUTPUT="$INPUT"
fi
[ -n "$TOOL_OUTPUT" ] || exit 0

# Lowercase for matching
LOWER=$(printf '%s' "$TOOL_OUTPUT" | tr '[:upper:]' '[:lower:]')

# Detect signatures
SIGNATURE=""
if printf '%s' "$LOWER" | grep -q "needs authentication"; then
  SIGNATURE="needs-authentication"
elif printf '%s' "$LOWER" | grep -q "refresh token rejected"; then
  SIGNATURE="refresh-token-rejected"
elif printf '%s' "$LOWER" | grep -q "401" && printf '%s' "$LOWER" | grep -q "refresh"; then
  SIGNATURE="401-after-refresh"
elif printf '%s' "$LOWER" | grep -q "oauth" && printf '%s' "$LOWER" | grep -q "expired"; then
  SIGNATURE="oauth-expired"
elif printf '%s' "$LOWER" | grep -q "401" && printf '%s' "$LOWER" | grep -q "token"; then
  SIGNATURE="401-token"
fi

# No signature → silent
[ -n "$SIGNATURE" ] || exit 0

# One-shot per session per signature
STATE_DIR="${CC_OAUTH_REFRESH_MONITOR_STATE_DIR:-$HOME/.claude}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="$STATE_DIR/oauth-refresh-monitor.fired"

SESSION_ID="${CC_OAUTH_REFRESH_MONITOR_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="${CLAUDECODE_SESSION_ID:-}"
fi
if [ -z "$SESSION_ID" ] && command -v tty >/dev/null 2>&1; then
  TTY_PATH=$(tty 2>/dev/null)
  if [ -n "$TTY_PATH" ] && [ "$TTY_PATH" != "not a tty" ]; then
    SESSION_ID=$(printf '%s' "$TTY_PATH" | tr '/' '_')
  fi
fi
[ -n "$SESSION_ID" ] || SESSION_ID="ppid-${PPID:-0}"

FIRED_KEY="${SESSION_ID}::${SIGNATURE}"
if [ -f "$STATE_FILE" ] && grep -Fq -- "$FIRED_KEY" "$STATE_FILE" 2>/dev/null; then
  exit 0
fi

# Bound state file
if [ -f "$STATE_FILE" ]; then
  tail -n 100 "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null \
    && mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
fi
printf '%s\n' "$FIRED_KEY" >> "$STATE_FILE" 2>/dev/null || true

cat >&2 <<EOF
[oauth-refresh-monitor] OAuth refresh corruption signature detected in tool
output: "$SIGNATURE".

Cluster 19 candidate axis 19A documents OAuth refresh failure paths where a
transient upstream error during a refresh operation corrupts the credentials
state into a persistent broken loop (anchor case: issue #61912). The pattern
is structurally distinct from straightforward 401 expiry — the operator's
credential state was valid just before the refresh, the upstream returned 5xx
or rejected the refresh, and now subsequent requests return 401 even though
the user did not log out and the original session was not expired.

Recovery (NOT a retry — retry compounds the corruption):
  1. Run /account to confirm the current auth state.
  2. If "Not authenticated," do a full re-auth (logout then login) rather
     than relying on automatic refresh.
  3. For MCP servers, restart the MCP connection rather than relying on
     in-session token refresh; the MCP refresh paths (#59460 / #59725 /
     #60260 / #61139) are the specific failure modes here.

Why the recovery is "full re-auth, not retry":
  The corruption is in the refresh token state itself, so subsequent
  refresh attempts fail in the same way. Only a fresh authentication
  bypasses the corrupted refresh path.

This advisory fires once per session per signature. To silence:
  export CC_OAUTH_REFRESH_MONITOR_QUIET=1

Companion hooks:
  auth-status-checker.sh — full Cluster 19 mitigation menu (SessionStart, opt-in)
  auth-expiry-reminder.sh — daily checkpoint reminder (SessionStart, opt-in)

References:
  https://github.com/anthropics/claude-code/issues/61912  (axis 19A anchor)
  https://github.com/anthropics/claude-code/issues/59460  (MCP OAuth DCR re-runs)
  https://github.com/anthropics/claude-code/issues/61923  (refresh token rejection)
  https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f  (field guide)
EOF

exit 0
