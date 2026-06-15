#!/bin/bash
# ================================================================
# deployment-readback-gate.sh — Refuse a deployment-completion claim
#                               unless an authority confirms it, recently
# ================================================================
# PURPOSE:
#   Turn a "deployment complete" claim into a refusable, auditable trust
#   artifact. This is the GENERIC decision core: it consumes a *normalized
#   readback receipt* (produced by a provider adapter — gh deployments,
#   Vercel, k8s, ...) and decides allow / refuse-mismatch / refuse-query-
#   failure / refuse-stale. It contains no provider knowledge.
#
#   Spec: docs/deployment-readback-gate-spec.md  (issue #313)
#   Motivating incident: anthropics/claude-code#61699 (model claimed
#   "deployment complete" while the real deployment state diverged).
#
# TRIGGER: Stop
#
# INPUT (stdin): a normalized readback receipt JSON. Required fields:
#   claim_span, claim_time (ISO 8601), claimed_ref, authority,
#   queried_ref, queried_state, readback_time (ISO 8601, from the
#   authority's own response), stale_if_older_than_ms (integer).
#   queried_state is the authority's state ("success" = confirmed) or
#   the literal "query-failure" when the adapter could not reach the
#   authority.
#
# DECISION (and exit code):
#   refuse-query-failure (exit 2) — authority unreachable / readback errored.
#       FAIL CLOSED. Never coerced to allow. Distinct incident class from a
#       mismatch: truth was never established (the claim *might* be correct).
#   refuse-mismatch (exit 2)      — queried_ref != claimed_ref, or
#       queried_state != "success". Truth established, claim was wrong.
#   refuse-stale (exit 2)         — claim_time - readback_time exceeds
#       stale_if_older_than_ms. A cached/replayed "success" must not ratify
#       a fresh claim. Staleness is anchored to the CLAIM, not wall-clock.
#   allow (exit 0)                — fresh AND matching AND success.
#
#   Missing required fields or unparseable timestamps also FAIL CLOSED
#   (refuse-query-failure): an unauditable receipt is not a confirmation.
#
# WHAT IT WRITES:
#   $CC_READBACK_RECEIPT_DIR/<timestamp>-<pid>.json   (decision filled in)
#   default: ~/.claude/state/deployments/readback/
#   The receipt is written OUTSIDE the transcript, so the audit unit
#   survives a lost or rewound session.
#
# USAGE (settings.json):
#   { "hooks": { "Stop": [{ "hooks": [{ "type": "command",
#     "command": "<adapter> | ~/.claude/hooks/deployment-readback-gate.sh" }] }] } }
#   The adapter emits the normalized receipt on stdout; this gate decides.
# ================================================================

set -uo pipefail

RECEIPT_DIR="${CC_READBACK_RECEIPT_DIR:-$HOME/.claude/state/deployments/readback}"

INPUT=$(cat)

# This gate only acts on a normalized readback receipt produced by an adapter.
# Empty stdin, "{}", or unrelated input means no deployment claim is being
# gated here — pass through. Hooks must not block on irrelevant input.
if ! printf '%s' "$INPUT" | grep -qE '"(claimed_ref|authority|queried_state|claim_span)"'; then
  exit 0
fi

# A receipt is present; jq is required to evaluate it.
if ! command -v jq >/dev/null 2>&1; then
  echo "deployment-readback-gate: jq not found; cannot audit a present receipt — failing closed" >&2
  exit 2
fi

# Extract fields (empty if absent).
field() { printf '%s' "$INPUT" | jq -r "(.$1 // empty)" 2>/dev/null; }

CLAIM_SPAN=$(field claim_span)
CLAIM_TIME=$(field claim_time)
CLAIMED_REF=$(field claimed_ref)
AUTHORITY=$(field authority)
QUERIED_REF=$(field queried_ref)
QUERIED_STATE=$(field queried_state)
READBACK_TIME=$(field readback_time)
STALE_MS=$(field stale_if_older_than_ms)

decision=""
reason=""

# to_ms: ISO 8601 -> epoch milliseconds, or empty on parse failure.
to_ms() { date -d "$1" +%s%3N 2>/dev/null; }

# --- fail closed on an unauditable receipt -------------------------------
if [ -z "$AUTHORITY" ] || [ -z "$READBACK_TIME" ] || [ -z "$STALE_MS" ] \
   || [ -z "$CLAIM_TIME" ] || [ -z "$CLAIMED_REF" ] || [ -z "$QUERIED_STATE" ]; then
  decision="refuse-query-failure"
  reason="receipt missing required fields (authority/readback_time/stale_if_older_than_ms/claim_time/claimed_ref/queried_state) — cannot establish truth"
elif [ "$QUERIED_STATE" = "query-failure" ]; then
  decision="refuse-query-failure"
  reason="authority '$AUTHORITY' was not reached — deployment NOT confirmed (failing closed)"
else
  claim_ms=$(to_ms "$CLAIM_TIME")
  read_ms=$(to_ms "$READBACK_TIME")
  if [ -z "$claim_ms" ] || [ -z "$read_ms" ]; then
    decision="refuse-query-failure"
    reason="unparseable claim_time/readback_time — cannot verify freshness (failing closed)"
  elif [ "$QUERIED_REF" != "$CLAIMED_REF" ] || [ "$QUERIED_STATE" != "success" ]; then
    decision="refuse-mismatch"
    reason="claim ref/state ($CLAIMED_REF/success) != authority ($QUERIED_REF/$QUERIED_STATE)"
  elif [ $(( claim_ms - read_ms )) -gt "$STALE_MS" ]; then
    decision="refuse-stale"
    reason="readback is $(( claim_ms - read_ms ))ms older than the claim (> ${STALE_MS}ms) — possible replay/cache, not ratifying"
  else
    decision="allow"
    reason="confirmed by $AUTHORITY: $QUERIED_REF/$QUERIED_STATE, fresh within ${STALE_MS}ms"
  fi
fi

# --- write the receipt (audit artifact, outside the transcript) ----------
mkdir -p "$RECEIPT_DIR" 2>/dev/null
ts=$(date -u +%Y%m%dT%H%M%S%3NZ 2>/dev/null || date -u +%Y%m%dT%H%M%SZ)
receipt_path="$RECEIPT_DIR/${ts}-$$.json"
printf '%s' "$INPUT" \
  | jq --arg d "$decision" --arg r "$reason" --arg w "$ts" \
       '. + {decision: $d, decision_reason: $r, decided_at: $w}' \
       > "$receipt_path" 2>/dev/null \
  || printf '{"decision":"%s","decision_reason":"%s","raw":true}\n' "$decision" "$reason" > "$receipt_path"

# --- emit decision -------------------------------------------------------
if [ "$decision" = "allow" ]; then
  exit 0
fi

# Stop hook: exit 2 surfaces the reason and blocks the stop so the claim
# is corrected instead of standing.
echo "deployment-readback-gate: $decision — $reason" >&2
echo "  receipt: $receipt_path" >&2
exit 2
