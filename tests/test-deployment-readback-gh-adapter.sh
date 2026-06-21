#!/bin/bash
# Tests for deployment-readback-gh-adapter.sh (the `gh` provider adapter)
# and its end-to-end composition with deployment-readback-gate.sh.
#
# The GitHub API is mocked via DRG_GH_CMD pointing at a fixture-driven
# stub, so these tests are deterministic and offline. Timestamps for the
# "fresh" cases are generated at run time so the staleness window holds.
ADAPTER="$(dirname "$0")/../examples/deployment-readback-gh-adapter.sh"
GATE="$(dirname "$0")/../examples/deployment-readback-gate.sh"
PASS=0 FAIL=0

WORK=$(mktemp -d -t readback-gh-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# --- mock gh -------------------------------------------------------------
# Returns canned JSON from fixture files; exit codes from MOCK_*_RC env.
MOCKGH="$WORK/mockgh"
cat > "$MOCKGH" <<'EOS'
#!/bin/bash
case "$*" in
  *"/statuses"*)
    [ -n "${MOCK_STATUSES_FILE:-}" ] && cat "$MOCK_STATUSES_FILE"
    exit "${MOCK_STATUSES_RC:-0}" ;;
  *deployments*)
    [ -n "${MOCK_DEPLOYMENTS_FILE:-}" ] && cat "$MOCK_DEPLOYMENTS_FILE"
    exit "${MOCK_DEPLOYMENTS_RC:-0}" ;;
  "repo view"*) echo "owner/repo"; exit 0 ;;
esac
exit 0
EOS
chmod +x "$MOCKGH"

NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
HOUR_AGO=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || echo "2000-01-01T00:00:00.000Z")

dep_fixture() { # <sha>
  local f="$WORK/dep-$1.json"
  printf '[{"id":42,"sha":"%s","ref":"%s","environment":"production"}]\n' "$1" "$1" > "$f"
  echo "$f"
}
status_fixture() { # <state> <created_at>
  local f="$WORK/st-$1-$(echo "$2" | tr ':TZ.' '----').json"
  printf '[{"state":"%s","created_at":"%s"}]\n' "$1" "$2" > "$f"
  echo "$f"
}

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# run_adapter <env-assignments...> -- captures stdout into $OUT
# (env passed as VAR=val tokens before the call)
run_adapter() { OUT=$(env "$@" DRG_GH_CMD="$MOCKGH" bash "$ADAPTER" <<<'{"hook_event_name":"Stop"}' 2>/dev/null); }

# run_chain: adapter | gate ; captures gate exit into $RC
run_chain() {
  env "$@" DRG_GH_CMD="$MOCKGH" bash "$ADAPTER" <<<'{"hook_event_name":"Stop"}' 2>/dev/null \
    | env CC_READBACK_RECEIPT_DIR="$WORK/receipts" bash "$GATE" >/dev/null 2>/dev/null
  RC=$?
}

field() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }

# =========================================================================
# 1. No deployment claim → pass-through {}
run_adapter DRG_CLAIM_TEXT="All tests green, opened the PR."
[ "$OUT" = "{}" ] && ok "no claim → {}" || bad "no claim → {} (got: $OUT)"
run_chain DRG_CLAIM_TEXT="All tests green, opened the PR."
[ "$RC" -eq 0 ] && ok "no claim → gate passes (exit 0)" || bad "no claim → gate exit $RC"

# 2. Benign local context must not be a claim
run_adapter DRG_CLAIM_TEXT="I deployed the function locally to test it."
[ "$OUT" = "{}" ] && ok "'deployed locally' → {}" || bad "'deployed locally' not benign (got: $OUT)"
run_adapter DRG_CLAIM_TEXT="About to deploy api@abc1234 to production."
[ "$OUT" = "{}" ] && ok "'about to deploy' → {} (not yet a claim)" || bad "'about to deploy' tripped (got: $OUT)"

# 3. Fresh + matching + success → receipt fields + gate allow
D=$(dep_fixture abc1234); S=$(status_fixture success "$NOW")
run_adapter DRG_CLAIM_TEXT="Deployment complete for api@abc1234." DRG_REPO=owner/repo \
            MOCK_DEPLOYMENTS_FILE="$D" MOCK_STATUSES_FILE="$S"
[ "$(field .queried_state)" = "success" ] && ok "success: queried_state=success" || bad "queried_state ($(field .queried_state))"
[ "$(field .queried_ref)" = "abc1234" ] && ok "success: queried_ref from deployment sha" || bad "queried_ref ($(field .queried_ref))"
[ "$(field .readback_time)" = "$NOW" ] && ok "success: readback_time from status created_at" || bad "readback_time ($(field .readback_time))"
[ "$(field .authority)" = "github_deployments_api" ] && ok "success: authority set" || bad "authority ($(field .authority))"
[ "$(field .claimed_ref)" = "abc1234" ] && ok "success: claimed_ref parsed from @sha" || bad "claimed_ref ($(field .claimed_ref))"
run_chain DRG_CLAIM_TEXT="Deployment complete for api@abc1234." DRG_REPO=owner/repo \
          MOCK_DEPLOYMENTS_FILE="$D" MOCK_STATUSES_FILE="$S"
[ "$RC" -eq 0 ] && ok "success fresh+match → gate allow (exit 0)" || bad "gate should allow (exit $RC)"

# 4. Ref mismatch (authority reports a different sha) → refuse-mismatch
D2=$(dep_fixture def5678); S2=$(status_fixture success "$NOW")
run_chain DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo \
          MOCK_DEPLOYMENTS_FILE="$D2" MOCK_STATUSES_FILE="$S2"
[ "$RC" -eq 2 ] && ok "ref mismatch → gate refuse (exit 2)" || bad "ref mismatch exit $RC"

# 5. Status failure → refuse-mismatch
D3=$(dep_fixture abc1234); S3=$(status_fixture failure "$NOW")
run_chain DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo \
          MOCK_DEPLOYMENTS_FILE="$D3" MOCK_STATUSES_FILE="$S3"
[ "$RC" -eq 2 ] && ok "status=failure → gate refuse (exit 2)" || bad "status failure exit $RC"

# 6. Deployments API errors → query-failure → fail closed
run_adapter DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo MOCK_DEPLOYMENTS_RC=1
[ "$(field .queried_state)" = "query-failure" ] && ok "API error → queried_state=query-failure" || bad "api error state ($(field .queried_state))"
run_chain DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo MOCK_DEPLOYMENTS_RC=1
[ "$RC" -eq 2 ] && ok "API error → gate refuse-query-failure (exit 2)" || bad "api error exit $RC"

# 7. No deployment on record (empty array) → not_found → refuse-mismatch
EMPTY="$WORK/empty.json"; echo '[]' > "$EMPTY"
run_adapter DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo MOCK_DEPLOYMENTS_FILE="$EMPTY"
[ "$(field .queried_state)" = "not_found" ] && ok "no deployment → queried_state=not_found" || bad "not_found state ($(field .queried_state))"
run_chain DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo MOCK_DEPLOYMENTS_FILE="$EMPTY"
[ "$RC" -eq 2 ] && ok "no deployment → gate refuse (exit 2)" || bad "not_found exit $RC"

# 8. Deployment exists, statuses API errors → query-failure
D8=$(dep_fixture abc1234)
run_chain DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo \
          MOCK_DEPLOYMENTS_FILE="$D8" MOCK_STATUSES_RC=1
[ "$RC" -eq 2 ] && ok "statuses error → gate refuse-query-failure (exit 2)" || bad "statuses error exit $RC"

# 9. Deployment exists but no status yet → no_status → refuse-mismatch
D9=$(dep_fixture abc1234); SEMPTY="$WORK/st-empty.json"; echo '[]' > "$SEMPTY"
run_adapter DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo \
            MOCK_DEPLOYMENTS_FILE="$D9" MOCK_STATUSES_FILE="$SEMPTY"
[ "$(field .queried_state)" = "no_status" ] && ok "no status → queried_state=no_status" || bad "no_status state ($(field .queried_state))"

# 10. Success but STALE (status 1h older than claim) → refuse-stale
D10=$(dep_fixture abc1234); S10=$(status_fixture success "$HOUR_AGO")
run_chain DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo \
          MOCK_DEPLOYMENTS_FILE="$D10" MOCK_STATUSES_FILE="$S10"
[ "$RC" -eq 2 ] && ok "stale readback → gate refuse-stale (exit 2)" || bad "stale exit $RC"

# 11. Strict mode: claim but no resolvable ref → query-failure receipt → refuse
run_adapter DRG_CLAIM_TEXT="Deployment complete." DRG_REPO=owner/repo DRG_STRICT=1
[ "$(field .queried_state)" = "query-failure" ] && ok "strict + no ref → query-failure receipt" || bad "strict state ($(field .queried_state))"
run_chain DRG_CLAIM_TEXT="Deployment complete." DRG_REPO=owner/repo DRG_STRICT=1
[ "$RC" -eq 2 ] && ok "strict + no ref → gate refuse (exit 2)" || bad "strict exit $RC"

# 12. Advisory (default): claim but no resolvable ref → pass through {}
run_adapter DRG_CLAIM_TEXT="Deployment complete." DRG_REPO=owner/repo
[ "$OUT" = "{}" ] && ok "advisory + no ref → {}" || bad "advisory no ref (got: $OUT)"

# 13. claimed_ref from a bare hex token (no @)
D13=$(dep_fixture 0a1b2c3d4e5f6789); S13=$(status_fixture success "$NOW")
run_adapter DRG_CLAIM_TEXT="Rolled out 0a1b2c3d4e5f6789 to prod." DRG_REPO=owner/repo \
            MOCK_DEPLOYMENTS_FILE="$D13" MOCK_STATUSES_FILE="$S13"
[ "$(field .claimed_ref)" = "0a1b2c3d4e5f6789" ] && ok "claimed_ref from bare hex token" || bad "bare hex ($(field .claimed_ref))"

# 14. DRG_CLAIMED_REF env overrides text parsing
run_adapter DRG_CLAIM_TEXT="Deployed the service." DRG_REPO=owner/repo DRG_CLAIMED_REF=feedf00d \
            MOCK_DEPLOYMENTS_FILE="$(dep_fixture feedf00d)" MOCK_STATUSES_FILE="$(status_fixture success "$NOW")"
[ "$(field .claimed_ref)" = "feedf00d" ] && ok "DRG_CLAIMED_REF override" || bad "claimed_ref override ($(field .claimed_ref))"

# 15. Adapter always emits valid JSON
run_adapter DRG_CLAIM_TEXT="Deployed api@abc1234." DRG_REPO=owner/repo \
            MOCK_DEPLOYMENTS_FILE="$(dep_fixture abc1234)" MOCK_STATUSES_FILE="$(status_fixture success "$NOW")"
printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && ok "receipt is valid JSON" || bad "invalid JSON: $OUT"

# 16. target field reflects repo/environment
[ "$(field .target)" = "owner/repo/production" ] && ok "target = repo/environment" || bad "target ($(field .target))"

echo ""
echo "deployment-readback-gh-adapter: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
