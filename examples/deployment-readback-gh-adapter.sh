#!/bin/bash
# ================================================================
# deployment-readback-gh-adapter.sh — `gh` deployments provider adapter
#                                     for deployment-readback-gate
# ================================================================
# PURPOSE:
#   The PROVIDER ADAPTER half of the deployment-readback-gate (issue
#   #313). It owns all GitHub-specific knowledge: given a Stop event,
#   it detects a deployment-completion claim in the assistant's
#   closeout, reads the GitHub Deployments API for the *authoritative*
#   state of that deploy, and emits the NORMALIZED readback receipt on
#   stdout. The generic gate (examples/deployment-readback-gate.sh)
#   consumes that receipt and decides allow / refuse-*.
#
#   Spec:  docs/deployment-readback-gate-spec.md
#   Gate:  examples/deployment-readback-gate.sh  (provider-agnostic core)
#   Incident: anthropics/claude-code#61699 (model claimed "deployment
#             complete" while the real deploy state diverged).
#
#   The adapter knows the provider; the gate knows the decision. A new
#   authority (Vercel, Cloud Run, k8s, ...) is added by writing another
#   adapter to this same output contract — never by touching the gate.
#
# TRIGGER: Stop
#
# INSTALL (settings.json) — adapter piped into the gate:
#   { "hooks": { "Stop": [{ "hooks": [{ "type": "command",
#     "command": "~/.claude/hooks/deployment-readback-gh-adapter.sh | ~/.claude/hooks/deployment-readback-gate.sh",
#     "env": { "DRG_REPO": "owner/repo", "DRG_ENVIRONMENT": "production" } }] }] } }
#
# INPUT (stdin): the Stop event JSON. The adapter reads the last
#   assistant message from `transcript_path` to find the claim. For
#   deterministic use/testing, DRG_CLAIM_TEXT overrides the transcript.
#
# OUTPUT (stdout): exactly one of —
#   * `{}`                         — no deployment claim here (or an
#       unresolvable target in advisory mode). The gate passes through.
#   * a normalized readback receipt — fields per the spec:
#       claim_span, claim_time, target, claimed_ref, authority,
#       readback_query, queried_ref, queried_state, readback_time,
#       stale_if_older_than_ms
#     `queried_state` is the authority's deployment-status state, or the
#     literal "query-failure" when the API could not be reached.
#
# CONFIG (env):
#   DRG_REPO            owner/repo. If unset, derived from `gh repo view`.
#   DRG_ENVIRONMENT     deployment environment to query (default: production)
#   DRG_CLAIMED_REF     the claimed commit/ref. If unset, parsed from the
#                       claim text (`@<sha>` or a bare 7–40 hex token).
#   DRG_PHRASE_LIST     comma-separated claim phrases (case-insensitive).
#                       default: deployed,deployment complete,shipped to
#                       production,rolled out,deploy succeeded,live in production
#   DRG_STALE_MS        staleness window in ms (default: 300000 = 5 min)
#   DRG_STRICT          "1" → a deployment claim with an unresolvable
#                       target emits a query-failure receipt (gate refuses)
#                       instead of passing through. default: advisory (0).
#   DRG_GH_CMD          gh binary to invoke (default: gh). Overridable so
#                       the API layer can be mocked under test.
#
# WHY A SEPARATE ADAPTER:
#   readback_time must come from the AUTHORITY's own response (the
#   deployment status `created_at`), not from when the hook ran — that
#   is what closes the replay/cache gap the gate's staleness check
#   depends on. Only the provider adapter can source it, so provider
#   I/O is isolated here and the gate stays pure and deterministic.
# ================================================================

set -uo pipefail

EVENT_INPUT=$(cat)

# --- config --------------------------------------------------------------
GH="${DRG_GH_CMD:-gh}"
ENVIRONMENT="${DRG_ENVIRONMENT:-production}"
STALE_MS="${DRG_STALE_MS:-300000}"
STRICT="${DRG_STRICT:-0}"
PHRASE_LIST="${DRG_PHRASE_LIST:-deployed,deployment complete,shipped to production,rolled out,deploy succeeded,live in production}"
AUTHORITY="github_deployments_api"

now_iso() { date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ; }

# Emit a bare pass-through and leave: this Stop is not gating a deploy claim.
pass_through() { printf '{}\n'; exit 0; }

# A receipt is meaningless without jq to build it; without it we cannot
# safely emit the contract, so pass through rather than emit malformed JSON.
command -v jq >/dev/null 2>&1 || pass_through

# --- 1. obtain the closeout text -----------------------------------------
# DRG_CLAIM_TEXT wins (deterministic). Otherwise read the last assistant
# message from the transcript named in the Stop event.
CLAIM_TEXT="${DRG_CLAIM_TEXT:-}"
if [ -z "$CLAIM_TEXT" ]; then
  TRANSCRIPT=$(printf '%s' "$EVENT_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    CLAIM_TEXT=$(python3 - "$TRANSCRIPT" <<'PY' 2>/dev/null || true
import sys, json
last = ""
try:
    with open(sys.argv[1]) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            msg = d.get("message", d)
            content = msg.get("content", "")
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text = " ".join(
                    b.get("text", "") for b in content
                    if isinstance(b, dict) and b.get("type") == "text"
                )
            else:
                text = ""
            if text.strip():
                last = text
except Exception:
    pass
print(last)
PY
)
  fi
fi
[ -n "$CLAIM_TEXT" ] || pass_through

# --- 2. detect a (non-benign) deployment-completion claim ----------------
# Returns the matched claim phrase/span, or empty. A phrase inside a benign
# context ("deployed locally", "shipped to my machine", "in dev only") is
# not a production-deployment claim and must not trip the gate.
CLAIM_SPAN=$(CLAIM_TEXT="$CLAIM_TEXT" PHRASE_LIST="$PHRASE_LIST" python3 <<'PY' 2>/dev/null || true
import os, re
text = os.environ["CLAIM_TEXT"]
low = text.lower()
phrases = [p.strip().lower() for p in os.environ["PHRASE_LIST"].split(",") if p.strip()]
benign = ("local", "localhost", "my machine", "in dev", "dev only",
          "staging only", "dry run", "dry-run", "would deploy", "about to deploy",
          "going to deploy", "preview deploy")
best = ""
for p in phrases:
    for m in re.finditer(re.escape(p), low):
        s, e = m.start(), m.end()
        window = low[max(0, s - 50):min(len(low), e + 50)]
        if any(b in window for b in benign):
            continue
        # span = the surrounding clause, trimmed, from the original-case text
        cs = max(0, s - 30)
        ce = min(len(text), e + 30)
        span = text[cs:ce].strip()
        span = re.sub(r"\s+", " ", span)
        if span:
            best = span[:120]
            break
    if best:
        break
print(best)
PY
)
[ -n "$CLAIM_SPAN" ] || pass_through

# --- 3. resolve the target (repo + claimed ref) --------------------------
REPO="${DRG_REPO:-}"
if [ -z "$REPO" ]; then
  REPO=$("$GH" repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi

CLAIMED_REF="${DRG_CLAIMED_REF:-}"
if [ -z "$CLAIMED_REF" ]; then
  # `@<sha>` first (e.g. "api@abc1234"), else a bare 7–40 hex token.
  CLAIMED_REF=$(printf '%s' "$CLAIM_SPAN" | grep -oiE '@[0-9a-f]{7,40}' | head -1 | tr -d '@')
  [ -n "$CLAIMED_REF" ] || CLAIMED_REF=$(printf '%s' "$CLAIM_SPAN" | grep -oiE '\b[0-9a-f]{7,40}\b' | head -1)
fi

CLAIM_TIME=$(now_iso)
READBACK_QUERY="repos/${REPO:-?}/deployments?environment=${ENVIRONMENT}&sha=${CLAIMED_REF:-?}&per_page=1 + /statuses"

# emit_receipt <queried_ref> <queried_state> <readback_time> <target>
emit_receipt() {
  jq -n \
    --arg cs "$CLAIM_SPAN" --arg ct "$CLAIM_TIME" --arg tg "$4" \
    --arg cr "$CLAIMED_REF" --arg au "$AUTHORITY" --arg rq "$READBACK_QUERY" \
    --arg qr "$1" --arg qs "$2" --arg rt "$3" \
    --argjson sm "$STALE_MS" \
    '{claim_span:$cs, claim_time:$ct, target:$tg, claimed_ref:$cr,
      authority:$au, readback_query:$rq, queried_ref:$qr, queried_state:$qs,
      readback_time:$rt, stale_if_older_than_ms:$sm}'
}

TARGET="${REPO:-?}/${ENVIRONMENT}"

# A deployment claim with no resolvable target: advisory passes through,
# strict fails closed (a named-but-unverifiable deploy is the spec's
# "strict mode refuses any closeout with a deployment phrase but no
# resolvable target").
if [ -z "$REPO" ] || [ -z "$CLAIMED_REF" ]; then
  if [ "$STRICT" = "1" ]; then
    emit_receipt "" "query-failure" "$(now_iso)" "$TARGET"
    exit 0
  fi
  pass_through
fi

# --- 4. read the authority: GitHub Deployments API -----------------------
DEPLOYMENTS=$("$GH" api "repos/$REPO/deployments?environment=$ENVIRONMENT&sha=$CLAIMED_REF&per_page=1" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$DEPLOYMENTS" ]; then
  # Authority unreachable / errored → truth never established. Fail closed.
  emit_receipt "" "query-failure" "$(now_iso)" "$TARGET"
  exit 0
fi

DEP_ID=$(printf '%s' "$DEPLOYMENTS" | jq -r 'if type=="array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
DEP_SHA=$(printf '%s' "$DEPLOYMENTS" | jq -r 'if type=="array" then (.[0].sha // empty) else (.sha // empty) end' 2>/dev/null)

if [ -z "$DEP_ID" ]; then
  # Authority reached, but it reports no deployment for this ref/env.
  # Truth established: the claimed deploy is not on record → mismatch.
  emit_receipt "" "not_found" "$(now_iso)" "$TARGET"
  exit 0
fi

STATUSES=$("$GH" api "repos/$REPO/deployments/$DEP_ID/statuses?per_page=1" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$STATUSES" ]; then
  emit_receipt "$DEP_SHA" "query-failure" "$(now_iso)" "$TARGET"
  exit 0
fi

STATE=$(printf '%s' "$STATUSES" | jq -r 'if type=="array" then (.[0].state // empty) else (.state // empty) end' 2>/dev/null)
CREATED_AT=$(printf '%s' "$STATUSES" | jq -r 'if type=="array" then (.[0].created_at // empty) else (.created_at // empty) end' 2>/dev/null)

if [ -z "$STATE" ]; then
  # Deployment exists but has no status yet → not confirmed.
  emit_receipt "$DEP_SHA" "no_status" "$(now_iso)" "$TARGET"
  exit 0
fi

# readback_time MUST be the authority's own timestamp (the status
# created_at), so the gate's staleness check is anchored to when the
# authority observed the state — not to when this hook ran.
[ -n "$CREATED_AT" ] || CREATED_AT=$(now_iso)
emit_receipt "$DEP_SHA" "$STATE" "$CREATED_AT" "$TARGET"
exit 0
