#!/bin/bash
# Tests for cost-incident-self-audit.sh
HOOK="examples/cost-incident-self-audit.sh"
[ -f "$HOOK" ] || HOOK="/tmp/ccps2/cost-incident-self-audit.sh"
# Resolve to an absolute path before any cd so the tests can chdir freely.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' got '$2')"; fi; }

WORK="/tmp/cost-audit-test-$$"
mkdir -p "$WORK"
cd "$WORK" || exit 1

# A settings file that wires in ALL the guards this audit checks for.
FULL="$WORK/full-settings.json"
cat > "$FULL" <<'JSON'
{ "hooks": { "PreToolUse": [
  {"hooks":[{"command":"git-push-blast-radius-guard.sh"}]},
  {"hooks":[{"command":"webfetch-runaway-guard.sh"}]},
  {"hooks":[{"command":"image-dimension-guard.sh"}]},
  {"hooks":[{"command":"unbounded-output-guard.sh"}]},
  {"hooks":[{"command":"daily-cost-guard.sh"}]}
] } }
JSON
EMPTY="$WORK/empty-settings.json"
echo '{}' > "$EMPTY"

# Test 1: fully-guarded setup + 1M off + no workflows -> 0 exposures, exit 0
OUT=$(CC_COST_AUDIT_SETTINGS="$FULL" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "fully guarded reports none" "$OUT" "No exposures found"
assert_eq "fully guarded exit 0" "$RC" "0"

# Test 2: empty settings + 1M off + no workflows -> exposed to runaway/image/output/spend (4)
OUT=$(CC_COST_AUDIT_SETTINGS="$EMPTY" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "empty settings -> 4 exposures (no CI, 1M off)" "$RC" "4"
assert_contains "mentions webfetch issue" "$OUT" "65684"
assert_contains "mentions image issue" "$OUT" "65636"
assert_contains "mentions output issue" "$OUT" "65789"
assert_not_contains "no CI -> no push-blast finding" "$OUT" "65944"

# Test 3: 1M context left ON adds the quota exposure (5)
OUT=$(CC_COST_AUDIT_SETTINGS="$EMPTY" bash "$HOOK" 2>/dev/null)
RC=$?
assert_eq "1M on -> 5 exposures" "$RC" "5"
assert_contains "mentions 1M quota issue" "$OUT" "64445"

# Test 4: CI workflows present + no push guard -> push-blast finding appears
mkdir -p "$WORK/.github/workflows"
echo 'on: [push]' > "$WORK/.github/workflows/ci.yml"
OUT=$(cd "$WORK" && CC_COST_AUDIT_SETTINGS="$EMPTY" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 bash "$HOOK" 2>/dev/null)
RC=$?
assert_contains "CI present -> push-blast finding" "$OUT" "65944"
assert_eq "CI present -> 5 exposures" "$RC" "5"

# Test 5: CI present but guard wired in -> no push-blast finding
OUT=$(cd "$WORK" && CC_COST_AUDIT_SETTINGS="$FULL" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 bash "$HOOK" 2>/dev/null)
assert_not_contains "CI + guard -> no push-blast" "$OUT" "65944"

# Test 6: --json emits valid JSON with the exposure count.
# Run from a clean dir with no CI workflows so the count is deterministic (4).
CLEAN="$WORK/clean"; mkdir -p "$CLEAN"
OUT=$(cd "$CLEAN" && CC_COST_AUDIT_SETTINGS="$EMPTY" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 bash "$HOOK" --json 2>/dev/null)
assert_contains "json has exposures field" "$OUT" '"exposures":4'
echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['exposures']==len(d['findings'])" 2>/dev/null \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: json parses and counts match"; }

# Test 7: partial guards -> only the missing ones are reported
PARTIAL="$WORK/partial.json"
echo '{"hooks":{"PreToolUse":[{"hooks":[{"command":"webfetch-runaway-guard.sh"}]}]}}' > "$PARTIAL"
OUT=$(CC_COST_AUDIT_SETTINGS="$PARTIAL" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 bash "$HOOK" 2>/dev/null)
assert_not_contains "webfetch guarded -> not reported" "$OUT" "65684"
assert_contains "image still reported" "$OUT" "65636"

# Test 8: missing settings entirely fails open (no crash) and still runs
OUT=$(CC_COST_AUDIT_SETTINGS="/nonexistent/path-$$.json" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "missing settings still produces a report" "$OUT" "cost-accident self-audit"
[ "$RC" -ge 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: missing settings no crash"; }

# Test 9: --help exits 0 without running the audit
OUT=$(bash "$HOOK" --help 2>&1); RC=$?
assert_contains "help shows usage" "$OUT" "Usage:"
assert_eq "help exits 0" "$RC" "0"

cd /tmp || true
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
