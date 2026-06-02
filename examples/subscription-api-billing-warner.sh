#!/bin/bash
# ================================================================
# subscription-api-billing-warner.sh — Warn at session start when the
#   active configuration will silently bill API / purchased credits
#   *above* a Claude Pro/Max subscription, so a subscriber does not
#   keep draining pay-per-token credits while subscription quota sits
#   unused.
# ================================================================
# PURPOSE:
#   Claude Code's credential precedence puts API-key auth ABOVE an
#   OAuth subscription: if ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN
#   is set, or settings.json defines an apiKeyHelper, every request
#   authenticates as a pay-per-token API call and bills the
#   Console/purchased credits — even when the user has a Pro/Max
#   subscription with quota to spare. Because nothing in the UI
#   surfaces this, subscribers lose real money without knowing an
#   API key is in play.
#
#   This is a recurring, money-losing pain on the issue tracker:
#     #64613  API requests consuming personal token quota when
#             subscription tokens available
#     #53638  Desktop silently uses project API keys for billing
#             instead of the subscription
#     #53728  Silent ANTHROPIC_API_KEY precedence shadows Max
#             subscription auth
#     #54677  [FR] Distinguish API key vs OAuth subscription billing
#
#   The hook inspects, at session start, the three locally-detectable
#   precedence sources (the two env vars and an apiKeyHelper in
#   user/project settings.json). If any is present it emits a one-line
#   stderr advisory naming the precedence rule and the one-command
#   confirmation (/status), then continues. Advisory only (exit 0);
#   it never blocks the session and never reads the key value.
#
#   It is deliberately conservative about noise: someone who runs on
#   API billing on purpose (no subscription, or multiple deliberate
#   API-key accounts) can silence it permanently, and it auto-skips
#   when ANTHROPIC_ACCOUNT_LABEL is set — the same signal the
#   account-routing-preflight.sh hook uses to mark intentional
#   multi-account API use.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# SETUP:
#   {
#     "hooks": {
#       "SessionStart": [
#         {
#           "matcher": "",
#           "hooks": [
#             { "type": "command",
#               "command": "$HOME/.claude/hooks/subscription-api-billing-warner.sh" }
#           ]
#         }
#       ]
#     }
#   }
#
# BEHAVIOR:
#   - No API-key env var and no apiKeyHelper → silent pass.
#   - Any precedence source present → stderr advisory + exit 0.
#   - Never blocks; never prints the key/token value.
#
# CONFIGURATION (env vars):
#   CC_SUB_BILLING_DISABLE   Set to "1" to disable the hook entirely.
#   ANTHROPIC_ACCOUNT_LABEL  If set (non-empty), the hook stays silent:
#                            an explicit account label signals the
#                            operator is managing API billing on
#                            purpose (mirrors account-routing-preflight).
#   CC_SUB_BILLING_SETTINGS_OVERRIDE
#                            Colon-separated list of settings.json paths
#                            to scan for apiKeyHelper instead of the real
#                            ~/.claude/settings.json and ./.claude/
#                            settings.json. Used by tests/CI.
# ================================================================

set -u

if [ "${CC_SUB_BILLING_DISABLE:-0}" = "1" ]; then
    exit 0
fi

# Read and discard the SessionStart JSON payload; the hook only
# inspects the environment and settings files, not the payload.
if [ ! -t 0 ]; then
    cat >/dev/null 2>&1 || true
fi

# An explicit account label means the operator is managing API-key
# billing deliberately — stay silent to avoid nagging that case.
if [ -n "${ANTHROPIC_ACCOUNT_LABEL:-}" ]; then
    exit 0
fi

REASONS=""

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    REASONS="${REASONS}   • ANTHROPIC_API_KEY is set in this environment
"
fi

if [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
    REASONS="${REASONS}   • ANTHROPIC_AUTH_TOKEN is set in this environment
"
fi

# Scan settings.json files for an apiKeyHelper, which injects a key on
# every request even when no env var is set.
if [ -n "${CC_SUB_BILLING_SETTINGS_OVERRIDE:-}" ]; then
    SETTINGS_LIST="${CC_SUB_BILLING_SETTINGS_OVERRIDE//:/
}"
else
    SETTINGS_LIST="${HOME:-/root}/.claude/settings.json
./.claude/settings.json"
fi

while IFS= read -r SETTINGS_FILE; do
    [ -z "$SETTINGS_FILE" ] && continue
    [ -r "$SETTINGS_FILE" ] || continue
    # Tolerant key-presence check (no jq dependency): a JSON object key
    # "apiKeyHelper" with a non-empty string value.
    if grep -Eq '"apiKeyHelper"[[:space:]]*:[[:space:]]*"[^"]+"' "$SETTINGS_FILE" 2>/dev/null; then
        REASONS="${REASONS}   • apiKeyHelper is configured in ${SETTINGS_FILE}
"
    fi
done <<EOF
$SETTINGS_LIST
EOF

if [ -n "$REASONS" ]; then
    cat >&2 <<EOF

⚠️  This session may bill API / purchased credits instead of your subscription.

   Claude Code's credential precedence puts API-key auth ABOVE an
   OAuth subscription. Detected:
${REASONS}
   If you have a Claude Pro/Max subscription, requests are likely
   spending pay-per-token (Console/purchased) credits even while your
   subscription quota is unused — the cause of the "subscription at 0%
   but my purchased balance is draining" reports (#64613, #53638, #53728).

   Confirm and fix:
     1. Run /status — it names the active auth method (subscription vs API).
     2. To use the subscription: unset the variable(s) above, and check the
        shell profile (.zshrc/.bashrc/.profile) and any .env / direnv .envrc
        that re-export them; remove apiKeyHelper from settings.json; and in
        /config turn off "Use custom API key".
     3. If money was already charged while a subscription was active, a
        billing review at https://support.claude.com can refund a misroute.

   This is an advisory; the session continues.
   Set CC_SUB_BILLING_DISABLE=1 (or ANTHROPIC_ACCOUNT_LABEL for deliberate
   API-key accounts) to silence it.

EOF
fi

exit 0
