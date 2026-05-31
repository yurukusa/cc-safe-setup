#!/bin/bash
# Tests for plugin-hooks-json-bloat-detector.sh
HOOK="$(dirname "$0")/../examples/plugin-hooks-json-bloat-detector.sh"
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

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

reset_state() {
  rm -rf "$TMPDIR"
  mkdir -p "$TMPDIR/plugins/cache/example-plugin/hooks"
  mkdir -p "$TMPDIR/state"
  unset CC_PLUGIN_HOOKS_BLOAT_DISABLE
  unset CC_PLUGIN_HOOKS_BLOAT_QUIET
  unset CC_PLUGIN_HOOKS_BLOAT_THRESHOLD
}

# Write a hooks.json file with N duplicate registrations of one command,
# under the given event bucket (default PreToolUse)
write_hooks_json() {
  local n="$1"
  local cmd="${2:-bash /some/hook.sh}"
  local event="${3:-PreToolUse}"
  local entries=""
  for i in $(seq 1 "$n"); do
    if [ -n "$entries" ]; then entries="$entries,"; fi
    entries="$entries{\"type\":\"command\",\"command\":\"$cmd\"}"
  done
  cat > "$TMPDIR/plugins/cache/example-plugin/hooks/hooks.json" <<EOF
{"hooks":{"$event":[{"matcher":"","hooks":[$entries]}]}}
EOF
}

# Fire the hook once with current environment
fire_hook() {
  printf '%s' '{}' | env \
    CC_PLUGIN_HOOKS_BLOAT_ROOT="$TMPDIR/plugins" \
    CC_PLUGIN_HOOKS_BLOAT_STATE_DIR="$TMPDIR/state" \
    ${CC_PLUGIN_HOOKS_BLOAT_DISABLE:+CC_PLUGIN_HOOKS_BLOAT_DISABLE="$CC_PLUGIN_HOOKS_BLOAT_DISABLE"} \
    ${CC_PLUGIN_HOOKS_BLOAT_QUIET:+CC_PLUGIN_HOOKS_BLOAT_QUIET="$CC_PLUGIN_HOOKS_BLOAT_QUIET"} \
    ${CC_PLUGIN_HOOKS_BLOAT_THRESHOLD:+CC_PLUGIN_HOOKS_BLOAT_THRESHOLD="$CC_PLUGIN_HOOKS_BLOAT_THRESHOLD"} \
    bash "$HOOK" 2>&1
}

echo "Testing plugin-hooks-json-bloat-detector.sh"
echo "==========================================="

# Test 1: DISABLE env silences the hook entirely
reset_state
write_hooks_json 10 "bash /silenced.sh"
CC_PLUGIN_HOOKS_BLOAT_DISABLE=1 OUT=$(fire_hook)
if [ -z "$OUT" ]; then
  run_test "DISABLE silences hook even with bloat present" "pass"
else
  run_test "DISABLE silences hook even with bloat present" "fail (got: $OUT)"
fi

# Test 2: QUIET env silences the hook entirely
reset_state
write_hooks_json 10 "bash /quiet.sh"
CC_PLUGIN_HOOKS_BLOAT_QUIET=1 OUT=$(fire_hook)
if [ -z "$OUT" ]; then
  run_test "QUIET silences hook even with bloat present" "pass"
else
  run_test "QUIET silences hook even with bloat present" "fail (got: $OUT)"
fi

# Test 3: No findings when each command appears ≤ threshold (default 5)
reset_state
write_hooks_json 3 "bash /low-count.sh"
OUT=$(fire_hook)
if [ -z "$OUT" ]; then
  run_test "No warning when duplicate count is at/below threshold" "pass"
else
  run_test "No warning when duplicate count is at/below threshold" "fail (got: $OUT)"
fi

# Test 4: Findings when same command appears > threshold
reset_state
write_hooks_json 10 "bash /bloat.sh"
OUT=$(fire_hook)
case "$OUT" in
  *"bloat detected"*"/bloat.sh"*)
    run_test "Warning fires with bloat detected and command listed" "pass" ;;
  *) run_test "Warning fires with bloat detected and command listed" "fail (got: $OUT)" ;;
esac

# Test 5: Threshold env override (lower threshold catches lower counts)
reset_state
write_hooks_json 3 "bash /lower.sh"
CC_PLUGIN_HOOKS_BLOAT_THRESHOLD=2 OUT=$(fire_hook)
case "$OUT" in
  *"bloat detected"*"/lower.sh"*)
    run_test "THRESHOLD override catches lower counts" "pass" ;;
  *) run_test "THRESHOLD override catches lower counts" "fail (got: $OUT)" ;;
esac

# Test 6: Plugin root doesn't exist → silent (no error spam)
reset_state
rm -rf "$TMPDIR/plugins"
OUT=$(fire_hook)
if [ -z "$OUT" ]; then
  run_test "Missing plugin root → silent" "pass"
else
  run_test "Missing plugin root → silent" "fail (got: $OUT)"
fi

# Test 7: Malformed JSON in hooks.json → silent (fail-soft)
reset_state
mkdir -p "$TMPDIR/plugins/cache/broken/hooks"
echo "not valid json {" > "$TMPDIR/plugins/cache/broken/hooks/hooks.json"
OUT=$(fire_hook)
if [ -z "$OUT" ]; then
  run_test "Malformed hooks.json → silent (fail-soft)" "pass"
else
  run_test "Malformed hooks.json → silent (fail-soft)" "fail (got: $OUT)"
fi

# Test 8: Same command in two DIFFERENT event buckets doesn't combine
reset_state
mkdir -p "$TMPDIR/plugins/cache/cross-event/hooks"
cat > "$TMPDIR/plugins/cache/cross-event/hooks/hooks.json" <<'EOF'
{"hooks":{
  "PreToolUse":[{"matcher":"","hooks":[
    {"type":"command","command":"bash /shared.sh"},
    {"type":"command","command":"bash /shared.sh"},
    {"type":"command","command":"bash /shared.sh"}
  ]}],
  "PostToolUse":[{"matcher":"","hooks":[
    {"type":"command","command":"bash /shared.sh"},
    {"type":"command","command":"bash /shared.sh"},
    {"type":"command","command":"bash /shared.sh"}
  ]}]
}}
EOF
OUT=$(fire_hook)
# 3 in each event bucket, threshold default 5 → no warning
if [ -z "$OUT" ]; then
  run_test "Same command across two events doesn't combine" "pass"
else
  run_test "Same command across two events doesn't combine" "fail (got: $OUT)"
fi

# Test 9: Two different plugins each at threshold are reported separately
reset_state
mkdir -p "$TMPDIR/plugins/cache/plugin-a/hooks"
mkdir -p "$TMPDIR/plugins/cache/plugin-b/hooks"
cat > "$TMPDIR/plugins/cache/plugin-a/hooks/hooks.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"","hooks":[
  {"type":"command","command":"bash /a.sh"},{"type":"command","command":"bash /a.sh"},
  {"type":"command","command":"bash /a.sh"},{"type":"command","command":"bash /a.sh"},
  {"type":"command","command":"bash /a.sh"},{"type":"command","command":"bash /a.sh"},
  {"type":"command","command":"bash /a.sh"}]}]}}
EOF
cat > "$TMPDIR/plugins/cache/plugin-b/hooks/hooks.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"","hooks":[
  {"type":"command","command":"bash /b.sh"},{"type":"command","command":"bash /b.sh"},
  {"type":"command","command":"bash /b.sh"},{"type":"command","command":"bash /b.sh"},
  {"type":"command","command":"bash /b.sh"},{"type":"command","command":"bash /b.sh"},
  {"type":"command","command":"bash /b.sh"}]}]}}
EOF
OUT=$(fire_hook)
case "$OUT" in
  *"plugin-a"*"plugin-b"*|*"plugin-b"*"plugin-a"*)
    run_test "Two bloated plugins reported separately" "pass" ;;
  *) run_test "Two bloated plugins reported separately" "fail (got: $OUT)" ;;
esac

# Test 10: Empty/missing 'hooks' key → silent
reset_state
mkdir -p "$TMPDIR/plugins/cache/empty/hooks"
echo '{"description": "no hooks here"}' > "$TMPDIR/plugins/cache/empty/hooks/hooks.json"
OUT=$(fire_hook)
if [ -z "$OUT" ]; then
  run_test "hooks.json with no hooks field → silent" "pass"
else
  run_test "hooks.json with no hooks field → silent" "fail (got: $OUT)"
fi

# Test 11: Empty input JSON does not crash
reset_state
write_hooks_json 10 "bash /input-test.sh"
OUT=$(printf '' | CC_PLUGIN_HOOKS_BLOAT_ROOT="$TMPDIR/plugins" \
  CC_PLUGIN_HOOKS_BLOAT_STATE_DIR="$TMPDIR/state" \
  bash "$HOOK" 2>&1)
case "$OUT" in
  *"bloat detected"*)
    run_test "Empty stdin doesn't crash (still scans)" "pass" ;;
  *) run_test "Empty stdin doesn't crash (still scans)" "fail (got: $OUT)" ;;
esac

# Test 12: Hourly debounce — second fire within an hour stays silent
reset_state
write_hooks_json 10 "bash /debounce.sh"
OUT1=$(fire_hook)
OUT2=$(fire_hook)
case "$OUT1$OUT2" in
  *"bloat detected"*)
    if echo "$OUT1" | grep -q "bloat detected" && [ -z "$OUT2" ]; then
      run_test "Hourly debounce silences second fire" "pass"
    else
      run_test "Hourly debounce silences second fire" "fail (OUT1: $OUT1 / OUT2: $OUT2)"
    fi ;;
  *) run_test "Hourly debounce silences second fire" "fail (no warning at all: $OUT1$OUT2)" ;;
esac

# Test 13: Advisory only (always exits 0)
reset_state
write_hooks_json 50 "bash /advisory.sh"
fire_hook >/dev/null 2>&1
EXIT=$?
if [ "$EXIT" -eq 0 ]; then
  run_test "Hook exits 0 (advisory)" "pass"
else
  run_test "Hook exits 0 (advisory)" "fail (exit: $EXIT)"
fi

# Test 14: 122× growth pattern from #64022 is decisively caught
reset_state
write_hooks_json 122 "bash /the-original-issue.sh"
OUT=$(fire_hook)
case "$OUT" in
  *"bloat detected"*"/the-original-issue.sh"*)
    run_test "Issue #64022 122× growth pattern is detected" "pass" ;;
  *) run_test "Issue #64022 122× growth pattern is detected" "fail (got: $OUT)" ;;
esac

# Test 15: Two different commands each at threshold are both reported
reset_state
mkdir -p "$TMPDIR/plugins/cache/dual-bloat/hooks"
cat > "$TMPDIR/plugins/cache/dual-bloat/hooks/hooks.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"","hooks":[
  {"type":"command","command":"bash /cmd-a.sh"},{"type":"command","command":"bash /cmd-a.sh"},
  {"type":"command","command":"bash /cmd-a.sh"},{"type":"command","command":"bash /cmd-a.sh"},
  {"type":"command","command":"bash /cmd-a.sh"},{"type":"command","command":"bash /cmd-a.sh"},
  {"type":"command","command":"bash /cmd-a.sh"},
  {"type":"command","command":"bash /cmd-b.sh"},{"type":"command","command":"bash /cmd-b.sh"},
  {"type":"command","command":"bash /cmd-b.sh"},{"type":"command","command":"bash /cmd-b.sh"},
  {"type":"command","command":"bash /cmd-b.sh"},{"type":"command","command":"bash /cmd-b.sh"},
  {"type":"command","command":"bash /cmd-b.sh"}]}]}}
EOF
OUT=$(fire_hook)
case "$OUT" in
  *"cmd-a"*"cmd-b"*|*"cmd-b"*"cmd-a"*)
    run_test "Two bloated commands in one plugin both reported" "pass" ;;
  *) run_test "Two bloated commands in one plugin both reported" "fail (got: $OUT)" ;;
esac

# Test 16: jq missing → silent (we don't test by removing jq; document it)
# Skipping in CI; covered by code review.

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
