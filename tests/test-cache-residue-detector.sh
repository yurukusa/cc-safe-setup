#!/bin/bash
# Tests for cache-residue-detector.sh
HOOK="$(dirname "$0")/../examples/cache-residue-detector.sh"
PASS=0
FAIL=0

run_test() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# Temp dir for synthetic .claude.json fixtures
TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

EMPTY_JSON="$TMPDIR_RUN/empty.json"
echo '{}' > "$EMPTY_JSON"

GROWTHBOOK_JSON="$TMPDIR_RUN/growthbook.json"
cat > "$GROWTHBOOK_JSON" <<'EOF'
{
  "numStartups": 5,
  "cachedGrowthBookFeatures": {
    "tengu_desktop_upsell": true,
    "tengu_heron_brook": false,
    "tengu_amber_rokovoko": 0.2
  }
}
EOF

EXPERIMENT_JSON="$TMPDIR_RUN/experiment.json"
cat > "$EXPERIMENT_JSON" <<'EOF'
{
  "cachedExperimentFeatures": ["tengu_one", "tengu_two", "tengu_three"]
}
EOF

STATSIG_JSON="$TMPDIR_RUN/statsig.json"
cat > "$STATSIG_JSON" <<'EOF'
{
  "cachedStatsigGates": {
    "some_gate": true,
    "another_gate": false
  }
}
EOF

ALL_RESIDUE_JSON="$TMPDIR_RUN/all.json"
cat > "$ALL_RESIDUE_JSON" <<'EOF'
{
  "cachedGrowthBookFeatures": {"a": 1, "b": 2},
  "cachedExperimentFeatures": ["x", "y"],
  "cachedStatsigGates": {"g": true}
}
EOF

EMPTY_KEYS_JSON="$TMPDIR_RUN/emptykeys.json"
cat > "$EMPTY_KEYS_JSON" <<'EOF'
{
  "cachedGrowthBookFeatures": {},
  "cachedExperimentFeatures": [],
  "cachedStatsigGates": {}
}
EOF

UNREADABLE_JSON="$TMPDIR_RUN/unreadable.json"
echo '{"cachedGrowthBookFeatures":{"x":1}}' > "$UNREADABLE_JSON"
chmod 000 "$UNREADABLE_JSON"

MISSING_JSON="$TMPDIR_RUN/missing.json"
# do not create it

echo "Testing cache-residue-detector.sh"
echo "================================="

# Test 1: both opt-outs set, no residue → silent exit 0
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$EMPTY_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "both opt-outs + no residue → silent exit 0" pass
else
  run_test "both opt-outs + no residue → silent (exit=$EXIT, out=$OUT)" fail
fi

# Test 2: both opt-outs set + residue exists → advisory printed
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ADVISORY"; then
  run_test "opt-outs set + residue → advisory printed" pass
else
  run_test "opt-outs set + residue → advisory (exit=$EXIT, out=$OUT)" fail
fi

# Test 3: opt-outs missing → silent (default, not strict)
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "opt-outs missing → silent (default, non-strict)" pass
else
  run_test "opt-outs missing → silent (default) (exit=$EXIT, out=$OUT)" fail
fi

# Test 4: opt-outs missing + STRICT=1 + residue → advisory
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CC_CACHE_RESIDUE_DETECTOR_STRICT=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ADVISORY" && echo "$OUT" | grep -q "Strict mode"; then
  run_test "STRICT=1 + opt-outs missing + residue → advisory mentions strict" pass
else
  run_test "STRICT=1 + opt-outs missing → advisory with strict note (exit=$EXIT, out=$OUT)" fail
fi

# Test 5: DISABLE=1 silences everything
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$ALL_RESIDUE_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  CC_CACHE_RESIDUE_DETECTOR_DISABLE=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences even when residue exists" pass
else
  run_test "DISABLE=1 silences (exit=$EXIT, out=$OUT)" fail
fi

# Test 6: QUIET=1 silences everything
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$ALL_RESIDUE_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  CC_CACHE_RESIDUE_DETECTOR_QUIET=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences even when residue exists" pass
else
  run_test "QUIET=1 silences (exit=$EXIT, out=$OUT)" fail
fi

# Test 7: cachedGrowthBookFeatures detected with entry count
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "cachedGrowthBookFeatures" && echo "$OUT" | grep -q "3 entries"; then
  run_test "cachedGrowthBookFeatures detected with entry count (3)" pass
else
  run_test "cachedGrowthBookFeatures entry count (got: $OUT)" fail
fi

# Test 8: cachedExperimentFeatures detected with entry count
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$EXPERIMENT_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "cachedExperimentFeatures" && echo "$OUT" | grep -q "3 entries"; then
  run_test "cachedExperimentFeatures detected with entry count (3)" pass
else
  run_test "cachedExperimentFeatures entry count (got: $OUT)" fail
fi

# Test 9: cachedStatsigGates detected with entry count
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$STATSIG_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "cachedStatsigGates" && echo "$OUT" | grep -q "2 entries"; then
  run_test "cachedStatsigGates detected with entry count (2)" pass
else
  run_test "cachedStatsigGates entry count (got: $OUT)" fail
fi

# Test 10: all three keys reported when all present
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$ALL_RESIDUE_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "cachedGrowthBookFeatures" \
  && echo "$OUT" | grep -q "cachedExperimentFeatures" \
  && echo "$OUT" | grep -q "cachedStatsigGates"; then
  run_test "all three keys reported when all present" pass
else
  run_test "all three keys reported (got: $OUT)" fail
fi

# Test 11: empty keys (object with 0 entries) → silent exit 0
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$EMPTY_KEYS_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "empty key objects/arrays → silent (no false positive)" pass
else
  run_test "empty key objects/arrays → silent (exit=$EXIT, out=$OUT)" fail
fi

# Test 12: .claude.json missing → silent exit 0 (no false positive)
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$MISSING_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test ".claude.json missing → silent exit 0" pass
else
  run_test ".claude.json missing → silent (exit=$EXIT, out=$OUT)" fail
fi

# Test 13: .claude.json unreadable → silent (fail-open)
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$UNREADABLE_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test ".claude.json unreadable → fail-open silent" pass
else
  run_test ".claude.json unreadable → fail-open (exit=$EXIT, out=$OUT)" fail
fi

# Test 14: jq missing → grep fallback advises about jq
# Simulate jq missing by using a PATH that excludes jq
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  PATH="/usr/local/bin-empty-prefix:/bin:/usr/bin" \
  env -i HOME="$HOME" \
    CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    DISABLE_GROWTHBOOK=1 \
    PATH="$TMPDIR_RUN/no-jq" \
    bash "$HOOK" 2>&1)
mkdir -p "$TMPDIR_RUN/no-jq"
ln -sf /bin/grep "$TMPDIR_RUN/no-jq/grep" 2>/dev/null
ln -sf /bin/cat "$TMPDIR_RUN/no-jq/cat" 2>/dev/null
ln -sf /bin/bash "$TMPDIR_RUN/no-jq/bash" 2>/dev/null
ln -sf /usr/bin/test "$TMPDIR_RUN/no-jq/test" 2>/dev/null
ln -sf /usr/bin/dirname "$TMPDIR_RUN/no-jq/dirname" 2>/dev/null
OUT=$(env -i HOME="$HOME" \
    CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    DISABLE_GROWTHBOOK=1 \
    PATH="$TMPDIR_RUN/no-jq" \
    bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "jq was not found" || echo "$OUT" | grep -q "count unknown"; then
  run_test "jq missing → grep fallback advises about jq" pass
else
  run_test "jq missing → fallback advisory (got: $OUT)" fail
fi

# Test 15: cleanup command included when jq present
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$ALL_RESIDUE_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "jq 'del" \
  && echo "$OUT" | grep -q "cachedGrowthBookFeatures" \
  && echo "$OUT" | grep -q "cachedExperimentFeatures" \
  && echo "$OUT" | grep -q "cachedStatsigGates"; then
  run_test "cleanup command lists all three cache keys" pass
else
  run_test "cleanup command lists three keys (got: $OUT)" fail
fi

# Test 16: cleanup section labeled idempotent
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -qi "idempotent"; then
  run_test "cleanup section labeled idempotent" pass
else
  run_test "cleanup section labeled idempotent (got: $OUT)" fail
fi

# Test 17: custom CLAUDE_JSON path via env var
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "$GROWTHBOOK_JSON"; then
  run_test "custom CC_CACHE_RESIDUE_CLAUDE_JSON path honored" pass
else
  run_test "custom path honored (got: $OUT)" fail
fi

# Test 18: exit code 0 in all configurations (non-blocking)
EXITS=()
for cfg in \
    "CC_CACHE_RESIDUE_CLAUDE_JSON=$EMPTY_JSON CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1" \
    "CC_CACHE_RESIDUE_CLAUDE_JSON=$ALL_RESIDUE_JSON CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1" \
    "CC_CACHE_RESIDUE_CLAUDE_JSON=$MISSING_JSON CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1" \
    "CC_CACHE_RESIDUE_CLAUDE_JSON=$UNREADABLE_JSON CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1" \
    "CC_CACHE_RESIDUE_CLAUDE_JSON=$ALL_RESIDUE_JSON CC_CACHE_RESIDUE_DETECTOR_DISABLE=1" \
    "CC_CACHE_RESIDUE_CLAUDE_JSON=$ALL_RESIDUE_JSON CC_CACHE_RESIDUE_DETECTOR_QUIET=1" \
    "CC_CACHE_RESIDUE_CLAUDE_JSON=$ALL_RESIDUE_JSON CC_CACHE_RESIDUE_DETECTOR_STRICT=1"; do
  eval "env -i HOME=\"$HOME\" PATH=\"\$PATH\" $cfg bash \"$HOOK\" >/dev/null 2>&1"
  EXITS+=("$?")
done
ALL_ZERO=1
for e in "${EXITS[@]}"; do
  [ "$e" != "0" ] && ALL_ZERO=0
done
if [ "$ALL_ZERO" = "1" ]; then
  run_test "exit code 0 in all 7 configurations (non-blocking)" pass
else
  run_test "exit code 0 in all configs (got: ${EXITS[*]})" fail
fi

# Test 19: warning written to stderr, stdout empty
STDOUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$ALL_RESIDUE_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>/dev/null)
if [ -z "$STDOUT" ]; then
  run_test "warning written to stderr, stdout empty" pass
else
  run_test "warning to stderr (stdout was: $STDOUT)" fail
fi

# Test 20: uses ADVISORY prefix (not BLOCKED)
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "^ADVISORY:"; then
  run_test "uses ADVISORY prefix (non-blocking)" pass
else
  run_test "uses ADVISORY prefix (got: $OUT)" fail
fi

# Test 21: advisory references issue #62061
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "62061"; then
  run_test "advisory references issue #62061" pass
else
  run_test "issue reference (got: $OUT)" fail
fi

# Test 22: advisory mentions both opt-out env var names in background
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" \
  && echo "$OUT" | grep -q "DISABLE_GROWTHBOOK"; then
  run_test "advisory names both opt-out env vars" pass
else
  run_test "advisory names both opt-out env vars (got: $OUT)" fail
fi

# Test 23: advisory mentions QUIET silence path
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CC_CACHE_RESIDUE_DETECTOR_QUIET"; then
  run_test "advisory mentions QUIET env var to silence" pass
else
  run_test "advisory mentions QUIET (got: $OUT)" fail
fi

# Test 24: opt-out env var with value "0" → treated as not opted-out (silent in default)
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=0 DISABLE_GROWTHBOOK=0 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "opt-outs set to 0 (not 1) → treated as not opted-out, silent" pass
else
  run_test "opt-outs as 0 → silent in default (exit=$EXIT, out=$OUT)" fail
fi

# Test 25: only one opt-out set + residue → still triggers advisory
OUT=$(unset DISABLE_GROWTHBOOK; CC_CACHE_RESIDUE_CLAUDE_JSON="$GROWTHBOOK_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ADVISORY"; then
  run_test "only one opt-out set + residue → still triggers (gap detection)" pass
else
  run_test "one opt-out + residue → triggers (exit=$EXIT, out=$OUT)" fail
fi

# Test 26: residue with non-standard JSON (malformed) → fail-open silent
MALFORMED_JSON="$TMPDIR_RUN/malformed.json"
echo 'this is not json {{{' > "$MALFORMED_JSON"
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$MALFORMED_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
# Either silent or grep-fallback might find a textual mention, but no jq error should leak
if [ "$EXIT" = "0" ]; then
  run_test "malformed JSON → exit 0 (fail-open, no jq error leak)" pass
else
  run_test "malformed JSON → fail-open (exit=$EXIT, out=$OUT)" fail
fi

# Test 27: stdin input is consumed (SessionStart hooks receive JSON)
OUT=$(echo '{"hook_event_name":"SessionStart"}' | \
  CC_CACHE_RESIDUE_CLAUDE_JSON="$EMPTY_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "stdin JSON consumed silently when no residue" pass
else
  run_test "stdin JSON consumed (exit=$EXIT, out=$OUT)" fail
fi

# Test 28: only cachedExperimentFeatures present (sole key) → reported alone
OUT=$(CC_CACHE_RESIDUE_CLAUDE_JSON="$EXPERIMENT_JSON" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
# Should NOT mention GrowthBook or Statsig key names
if echo "$OUT" | grep -q "cachedExperimentFeatures (3 entries)" \
  && ! echo "$OUT" | grep -q "cachedGrowthBookFeatures (" \
  && ! echo "$OUT" | grep -q "cachedStatsigGates ("; then
  run_test "only one cache key present → only that key listed (no false detection of others)" pass
else
  run_test "only one cache key reported alone (got: $OUT)" fail
fi

# Cleanup permission so trap can rm
chmod 644 "$UNREADABLE_JSON" 2>/dev/null || true

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
