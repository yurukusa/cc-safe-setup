#!/bin/bash
# subscription-bypass-detector.sh — SessionStart hook
# Trigger: SessionStart
# Matcher: ""
#
# Solves: anthropics/claude-code#60093 — operator with an active Max/Pro
#         subscription accumulated approximately USD 1,050 in API charges
#         across nine auto-refills over three days (2026-05-05 to 2026-05-07)
#         because a dotenv-loaded ANTHROPIC_API_KEY silently overrode the
#         subscription path. The UI displayed "Sonnet" throughout while
#         billing routed through API-key Opus pricing. The operator had no
#         in-session signal that the billing path had switched.
#
#         The official support response was that this behavior is
#         "intentional functionality" (the env var taking precedence over
#         the subscription credential is documented somewhere but not on
#         the path operators read), making operator-side detection the only
#         reliable prevention.
#
#         Earlier related case: a separate operator lost USD 187 in May
#         2026 from the same structural pattern (dotenv ANTHROPIC_API_KEY
#         silently bypassing the subscription). The pattern is recurring.
#
# Class of failure: claim-vs-reality divergence at the billing-routing layer.
#         The operator's mental model ("I subscribed, therefore I pay the
#         subscription rate") and the runtime behavior ("API key in env
#         takes precedence, so charges flow through metered API pricing")
#         have diverged silently. The status surface (UI showing the
#         expected model) reinforces the wrong mental model.
#
# HOW IT WORKS:
#   At session start, inspect the resolved environment for ANTHROPIC_API_KEY
#   (or related vendor-key env vars). If any are present, emit a SessionStart
#   warning that explicitly states: (1) the env var was detected, (2) this
#   bypasses subscription billing on the affected path, (3) the operator's
#   choices are to unset the env var (subscription billing) or to
#   acknowledge the API-key billing path explicitly.
#
#   The hook reads the dotenv-style files Claude Code is known to load
#   (~/.claude/.env, project .env, $HOME/.env) and surfaces which file is
#   the source of the key, so the operator can disable the right line.
#
# WHY THIS MATTERS:
#   Issue #60093 is one of the largest single-incident dollar losses in the
#   May 2026 claim-vs-reality cluster (USD 1,050 across 9 auto-refills before
#   the operator noticed). The cost is concentrated and irreversible at the
#   billing layer (charges already accrued cannot be reversed by adjusting
#   settings). Pre-session detection is the only reliable defense; in-session
#   detection happens too late.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# CONFIGURATION:
#   CC_SUBSCRIPTION_BYPASS_DISABLE=1   disable this hook entirely
#   CC_SUBSCRIPTION_BYPASS_ACK=1       acknowledge API-key billing is intended
#                                       (suppresses the warning but keeps the
#                                        detection log entry)
#   CC_SUBSCRIPTION_BYPASS_LOG=path    append detection events to this file
#                                       (default off)
#
# SAFETY:
#   - Read-only on the environment and on .env files.
#   - Does not modify, unset, or interact with the keys themselves.
#   - Emits a warning to stderr; does not block the session.
#   - Exit 0 always.
#
# REFERENCES:
#   - anthropics/claude-code#60093 (2026-05-18, USD 1,050 case)
#   - Earlier May 2026 case: USD 187 dotenv-bypass incident (community report,
#     surfaced via a Qiita writeup published 2026-05-15)
set -euo pipefail

[ "${CC_SUBSCRIPTION_BYPASS_DISABLE:-}" = "1" ] && exit 0

# Collect signal sources. Each signal is reported only if the value is
# non-empty after the env var resolves.
declare -a SOURCES=()

# Direct env var check
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    SOURCES+=("process environment (ANTHROPIC_API_KEY is set in the shell that launched this session)")
fi

# Look for the key in the standard dotenv search paths Claude Code is
# documented to consult.
check_dotenv_for_key() {
    local path="$1"
    local label="$2"
    [ ! -f "$path" ] && return 0
    if grep -qE '^[[:space:]]*ANTHROPIC_API_KEY[[:space:]]*=' "$path" 2>/dev/null; then
        SOURCES+=("$label ($path)")
    fi
}

check_dotenv_for_key "$HOME/.claude/.env" "Claude per-user dotenv"
check_dotenv_for_key "$HOME/.env" "user home dotenv"
check_dotenv_for_key "$PWD/.env" "project working-directory dotenv"

# Git-repo root dotenv (if we're inside a repo and it's different from cwd)
if command -v git >/dev/null 2>&1; then
    GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$GIT_ROOT" ] && [ "$GIT_ROOT" != "$PWD" ]; then
        check_dotenv_for_key "$GIT_ROOT/.env" "git repository root dotenv"
    fi
fi

# If no sources were found, exit silently.
if [ "${#SOURCES[@]}" -eq 0 ]; then
    exit 0
fi

# Build the warning body
SOURCE_LIST=""
for src in "${SOURCES[@]}"; do
    SOURCE_LIST="${SOURCE_LIST}\n  - ${src}"
done

WARNING_BODY="ANTHROPIC_API_KEY detected at session start. Source(s):${SOURCE_LIST}

Implication: if an ANTHROPIC_API_KEY is resolved in the environment, Claude Code routes billing through metered API-key pricing rather than your Max/Pro subscription, on the affected codepath. This is intentional per Anthropic support but it is not surfaced in-session — the UI continues to display the selected model normally while charges accumulate against the API key.

Issue #60093 (2026-05-18) documents a single operator accumulating ~USD 1,050 across 9 auto-refills over 3 days (2026-05-05 to 2026-05-07) before the divergence was noticed. An earlier May 2026 case surfaced a ~USD 187 loss from the same pattern. The cost is incurred at billing time and cannot be reversed by adjusting settings after the fact.

To use subscription billing on this session: unset ANTHROPIC_API_KEY in the shell (or remove the matching line from the source file above) and restart Claude Code.

To acknowledge that API-key billing is intended for this session, set CC_SUBSCRIPTION_BYPASS_ACK=1; the warning will be suppressed for future sessions but a log entry will still record the detection if CC_SUBSCRIPTION_BYPASS_LOG is set."

# Optional logging
if [ -n "${CC_SUBSCRIPTION_BYPASS_LOG:-}" ]; then
    {
        printf '[%s] subscription-bypass-detected: sources=%d sources_list=%s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${#SOURCES[@]}" "${SOURCES[*]}"
    } >> "$CC_SUBSCRIPTION_BYPASS_LOG" 2>/dev/null || true
fi

# Suppress visible warning if acknowledged
if [ "${CC_SUBSCRIPTION_BYPASS_ACK:-}" = "1" ]; then
    exit 0
fi

# Emit warning via SessionStart hookSpecificOutput
jq -n \
    --arg ctx "$(printf '%b' "$WARNING_BODY")" \
    '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: $ctx
        }
    }'

exit 0
