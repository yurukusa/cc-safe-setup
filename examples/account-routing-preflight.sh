#!/bin/bash
# ================================================================
# account-routing-preflight.sh — Refuse session when the active
#                                Anthropic account doesn't match
#                                the project's declared expectation
# ================================================================
# PURPOSE:
#   Operators running multiple Anthropic accounts (work + personal,
#   multiple clients, multiple organizations) routinely launch
#   Claude Code from the wrong shell context and accidentally bill
#   the wrong account. This hook catches that mistake at session
#   start by comparing ANTHROPIC_ACCOUNT_LABEL against a per-project
#   declaration in .claude/expected-account.
#
#   The hook does NOT set the account. Hooks run as subprocesses
#   and cannot modify the parent claude process's environment.
#   Account switching must happen via shell alias or direnv before
#   `claude` is launched. This hook is the safety net: if the wrong
#   account is loaded when the session starts, it refuses the session
#   with an explicit error rather than billing silently.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# OPERATOR-SIDE BRIDGE FOR (1,178 cumulative reactions):
#   #18435 Desktop multi-account profile switcher (542 reactions)
#   #27302 Web app per-Connector multi-account (327 reactions)
#   #36151 Mobile app multi-account switching (309 reactions)
#
# SETUP:
#   1. Set ANTHROPIC_ACCOUNT_LABEL alongside ANTHROPIC_API_KEY in
#      your account-switching mechanism (alias / direnv / wrapper):
#
#      alias cc-work='ANTHROPIC_API_KEY=$WORK_KEY ANTHROPIC_ACCOUNT_LABEL=work claude'
#
#   2. In each project root that should be tied to a specific
#      account, create .claude/expected-account with the label:
#
#      echo "work" > ~/projects/work-monorepo/.claude/expected-account
#      echo "client-a" > ~/projects/clients/client-a/.claude/expected-account
#
#   3. Wire the hook in settings.json:
#
#      {
#        "hooks": {
#          "SessionStart": [
#            {
#              "matcher": "",
#              "hooks": [
#                { "type": "command",
#                  "command": "$HOME/.claude/hooks/account-routing-preflight.sh" }
#              ]
#            }
#          ]
#        }
#      }
#
# BEHAVIOR:
#   - No .claude/expected-account in $PWD → pass through silently.
#   - File exists, label matches ANTHROPIC_ACCOUNT_LABEL → pass.
#   - File exists, label mismatch → exit 2 with explicit message
#     showing expected vs active account.
#
# CONFIGURATION (env vars):
#   ANTHROPIC_ACCOUNT_LABEL   the active session's account label;
#                              defaults to "unknown" if unset.
#   CC_ACCOUNT_PREFLIGHT_DISABLE  set to "1" to disable the gate.
#
# RELATED ISSUES:
#   #18435, #27302, #36151 (the 1,178-reaction cluster)
# ================================================================

set -u

if [ "${CC_ACCOUNT_PREFLIGHT_DISABLE:-0}" = "1" ]; then
    exit 0
fi

EXPECTED_FILE="$PWD/.claude/expected-account"
if [ ! -f "$EXPECTED_FILE" ]; then
    # No declared expectation for this project — silent pass-through
    exit 0
fi

EXPECTED=$(cat "$EXPECTED_FILE" 2>/dev/null | tr -d '[:space:]')
if [ -z "$EXPECTED" ]; then
    # File exists but is empty — silent pass-through
    exit 0
fi

ACTIVE="${ANTHROPIC_ACCOUNT_LABEL:-unknown}"

if [ "$ACTIVE" = "$EXPECTED" ]; then
    # Match — proceed silently
    exit 0
fi

# Mismatch — refuse the session
cat >&2 <<EOF

⛔ Account mismatch detected at session start.

   Project path:    $PWD
   Project expects: $EXPECTED
   Active account:  $ACTIVE

The active Anthropic account does not match what this project
declares in .claude/expected-account. Launching claude under
the active account would bill the wrong account.

Fix:
  1. Exit this claude session.
  2. Switch accounts via your shell alias or direnv:
       cc-${EXPECTED} ...
  3. Verify ANTHROPIC_ACCOUNT_LABEL is set to "${EXPECTED}":
       echo "\$ANTHROPIC_ACCOUNT_LABEL"
  4. Relaunch claude from this directory.

To disable this gate temporarily, export
CC_ACCOUNT_PREFLIGHT_DISABLE=1.

EOF
exit 2
