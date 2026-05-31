#!/bin/bash
# cli-config-pinning-detector.sh — Detect Anthropic CLI config that silently pins
# organization_id and overrides Claude Code auth routing
# (Cluster 19 candidate, axis 19H — local-side credential override)
#
# Background:
#   Cluster 19 axis 19H documents a class of authentication failures where the
#   operator appears to be logged in with the correct email, but Claude Code is
#   routed to the wrong organization (and therefore the wrong billing path).
#
#   The mechanism: Claude Code and the standalone Anthropic CLI share the
#   ~/.config/anthropic directory. If the CLI has written a config file at
#   ~/.config/anthropic/configs/default.json with a hardcoded organization_id
#   (e.g., from an "Individual Org" used briefly during testing), Claude Code
#   honors that pinned organization_id. `claude auth login` / `claude auth
#   logout` do not always clear or update this pin — so the operator ends up
#   "logged in" but routed to the wrong organization, and the failure surfaces
#   downstream as billing-path or quota-state confusion.
#
#   Anchor case: #60742 — "[BUG] Anthropic CLI Overwrites and Pins Claude Code
#   Credentials".
#
#   This hook is a SessionStart advisory that fires when:
#     - the file ~/.config/anthropic/configs/default.json (or override path) exists,
#       AND it contains a non-empty organization_id field, AND
#     - the operator has not already seen the advisory in this session
#
#   The advisory describes the pinning behavior, points at the file and the
#   pinned organization_id value, and recommends an explicit verification step.
#   The hook does not auto-delete or auto-edit the config file — that decision
#   belongs to the operator (the pinned org may be intentional).
#
#   Reference:
#     https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f (auth cluster field guide)
#
# Why a hook helps:
#   Without the advisory, the operator discovers the wrong-organization routing
#   only at billing-cycle review, or when a teammate flags that their work is
#   showing up under an unexpected org. With the advisory, the pinning is
#   surfaced at SessionStart so the operator can verify org routing before
#   substantive work attaches to the wrong billing path.
#
# When this hook does NOT emit anything:
#   - CC_AUTH_PIN_DISABLE=1
#   - CC_AUTH_PIN_QUIET=1
#   - the CLI config file does not exist
#   - the CLI config file exists but has no organization_id field
#   - the advisory has already fired in this session
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/cli-config-pinning-detector.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_AUTH_PIN_DISABLE=1            — never emit
#   CC_AUTH_PIN_QUIET=1              — silent (process but never write to stderr)
#   CC_AUTH_PIN_CONFIG=<path>        — config file path override (tests)
#   CC_AUTH_PIN_STATE_DIR=<path>     — one-shot state dir override (default ~/.claude/state)
#   CC_AUTH_PIN_SESSION_ID=<id>      — session id override (tests)
#
# Design notes:
#   - Opt-out. The pinning behavior is silent by design (no upstream signal),
#     so a one-shot stderr advisory at SessionStart is the only place this
#     surfaces before the operator commits substantive work to the wrong org.
#   - One-shot per session. The advisory fires once. The operator either
#     verifies and dismisses, or unsets the pin in the file deliberately.
#   - Never blocks. Exit always 0. The pin may be intentional (multi-org
#     setups); auto-deleting it would break those workflows.
#   - Does not require jq. The organization_id field is parsed with a portable
#     grep/sed pipeline so the hook works on bare shells.

set -u

if [[ "${CC_AUTH_PIN_DISABLE:-0}" = "1" ]]; then
    exit 0
fi

CONFIG_FILE="${CC_AUTH_PIN_CONFIG:-$HOME/.config/anthropic/configs/default.json}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    exit 0
fi

STATE_DIR="${CC_AUTH_PIN_STATE_DIR:-$HOME/.claude/state}"
mkdir -p "$STATE_DIR" 2>/dev/null

SESSION_ID="${CC_AUTH_PIN_SESSION_ID:-${CLAUDE_SESSION_ID:-default}}"
GUARD_FILE="$STATE_DIR/auth-pin-${SESSION_ID}.fired"

if [[ -f "$GUARD_FILE" ]]; then
    exit 0
fi

# Extract organization_id without requiring jq. The portable approach:
# 1) grep for the key (allowing leading whitespace and the optional underscore)
# 2) sed-strip the key, separator, quotes, and trailing comma
ORG_LINE=$(grep -E '"organization_id"[[:space:]]*:' "$CONFIG_FILE" 2>/dev/null | head -1)
if [[ -z "$ORG_LINE" ]]; then
    exit 0
fi

ORG_ID=$(echo "$ORG_LINE" \
    | sed -E 's/.*"organization_id"[[:space:]]*:[[:space:]]*"?([^",}[:space:]]+)"?.*/\1/' \
    | tr -d '[:space:]')

if [[ -z "$ORG_ID" ]] || [[ "$ORG_ID" == "null" ]] || [[ "$ORG_ID" == "$ORG_LINE" ]]; then
    exit 0
fi

# Mark one-shot guard.
touch "$GUARD_FILE" 2>/dev/null

if [[ "${CC_AUTH_PIN_QUIET:-0}" = "1" ]]; then
    exit 0
fi

cat >&2 <<EOF

────────────────────────────────────────────────────────────────────
  Auth advisory — Cluster 19 axis 19H (CLI config pinning)
────────────────────────────────────────────────────────────────────
  Anthropic CLI config detected with pinned organization_id:
    ${CONFIG_FILE}
    organization_id: ${ORG_ID}

  The Cluster 19 axis 19H pattern: Claude Code shares the
  ~/.config/anthropic directory with the standalone Anthropic CLI.
  When the CLI has written a config file with a hardcoded
  organization_id, Claude Code honors that pin — even if
  \`claude auth login\` / \`claude auth logout\` were run afterwards.
  The visible state is "logged in with the correct email," but tool
  calls are routed to the pinned org's billing path.

  Anchor case: #60742.

  Recommended verification before substantive work:

    /account

  Confirm the "Organization" field matches your intended billing org.
  If it does not match, the pin in the file above is overriding
  your interactive auth. Two recovery paths:

    1) Edit ${CONFIG_FILE} and remove the
       "organization_id" line, then run /login to re-pick the org.
    2) Delete the file entirely if the standalone CLI is not used.

  Field guide: https://gist.github.com/yurukusa/58cb17bfda4d5ab31bd804809809d22f

  (This advisory fires once per session. To disable:
   export CC_AUTH_PIN_DISABLE=1)
────────────────────────────────────────────────────────────────────

EOF

exit 0
