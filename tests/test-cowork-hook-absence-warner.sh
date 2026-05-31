#!/bin/bash
# Tests for cowork-hook-absence-warner.sh
HOOK="examples/cowork-hook-absence-warner.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"
fresh_paths() {
    local s="$TMPDIR/settings-$$-$RANDOM-$RANDOM.json"
    local d="$TMPDIR/state-$$-$RANDOM-$RANDOM"
    mkdir -p "$d"
    echo "$s|$d"
}

run_hook() {
    local settings="$1" state_dir="$2"
    shift 2
    local out rc
    if [ "$#" -eq 0 ]; then
        out=$(env -u CC_COWORK_WARNER_DISABLE \
                  -u CC_COWORK_WARNER_DATE \
                  -u CC_COWORK_WARNER_MIN_HOOKS \
                  CC_COWORK_WARNER_SETTINGS="$settings" \
                  CC_COWORK_WARNER_STATE_DIR="$state_dir" \
                  bash "$HOOK_ABS" 2>&1)
    else
        out=$(env -u CC_COWORK_WARNER_DISABLE \
                  -u CC_COWORK_WARNER_DATE \
                  -u CC_COWORK_WARNER_MIN_HOOKS \
                  CC_COWORK_WARNER_SETTINGS="$settings" \
                  CC_COWORK_WARNER_STATE_DIR="$state_dir" "$@" \
                  bash "$HOOK_ABS" 2>&1)
    fi
    rc=$?
    echo "$out"
    return $rc
}

# Test 1: No settings file → silent.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
OUT=$(run_hook "$S" "$D"); RC=$?
assert_not_contains "no settings silent" "$OUT" "NOTE"
assert_exit "no settings exit 0" "$RC" "0"

# Test 2: Empty hooks block → silent.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{}}' > "$S"
OUT=$(run_hook "$S" "$D"); RC=$?
assert_not_contains "empty hooks silent" "$OUT" "NOTE"
assert_exit "empty hooks exit 0" "$RC" "0"

# Test 3: Settings file with 1 hook → emits NOTE.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"echo"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D"); RC=$?
assert_contains "1 hook emits NOTE" "$OUT" "NOTE"
assert_contains "1 hook mentions count" "$OUT" "1"
assert_contains "1 hook mentions 11E" "$OUT" "11E"
assert_exit "1 hook exit 0" "$RC" "0"

# Test 4: Settings file with 5 hooks across events → count of 5.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
cat > "$S" <<'JSON'
{
  "hooks": {
    "SessionStart": [{"matcher":"","hooks":[{"type":"command","command":"a"}]}],
    "UserPromptSubmit": [{"matcher":"","hooks":[{"type":"command","command":"b"}]}],
    "Stop": [{"matcher":"","hooks":[{"type":"command","command":"c"}]}],
    "PreToolUse": [{"matcher":"","hooks":[{"type":"command","command":"d"}]}],
    "PostToolUse": [{"matcher":"","hooks":[{"type":"command","command":"e"}]}]
  }
}
JSON
OUT=$(run_hook "$S" "$D"); RC=$?
assert_contains "5 hooks emits NOTE" "$OUT" "NOTE"
assert_contains "5 hooks mentions count 5" "$OUT" "5 CLI hooks"
assert_exit "5 hooks exit 0" "$RC" "0"

# Test 5: Disable kill switch.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"echo"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D" CC_COWORK_WARNER_DISABLE=1); RC=$?
assert_not_contains "disable suppresses NOTE" "$OUT" "NOTE"
assert_exit "disable exit 0" "$RC" "0"

# Test 6: One-shot per calendar day — second run same day is silent.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"echo"}]}]}}' > "$S"
OUT1=$(run_hook "$S" "$D" CC_COWORK_WARNER_DATE=2026-05-31)
OUT2=$(run_hook "$S" "$D" CC_COWORK_WARNER_DATE=2026-05-31); RC2=$?
assert_contains "first run emits NOTE" "$OUT1" "NOTE"
assert_not_contains "second run same day silent" "$OUT2" "NOTE"
assert_exit "second run exit 0" "$RC2" "0"

# Test 7: Next day → fires again.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"echo"}]}]}}' > "$S"
run_hook "$S" "$D" CC_COWORK_WARNER_DATE=2026-05-31 > /dev/null
OUT=$(run_hook "$S" "$D" CC_COWORK_WARNER_DATE=2026-06-01); RC=$?
assert_contains "next day fires again" "$OUT" "NOTE"
assert_exit "next day exit 0" "$RC" "0"

# Test 8: MIN_HOOKS threshold raises bar.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"echo"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D" CC_COWORK_WARNER_MIN_HOOKS=5); RC=$?
assert_not_contains "below threshold silent" "$OUT" "NOTE"
assert_exit "below threshold exit 0" "$RC" "0"

# Test 9: Malformed JSON → silent (jq fails).
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{not valid json' > "$S"
OUT=$(run_hook "$S" "$D"); RC=$?
assert_not_contains "malformed JSON silent" "$OUT" "NOTE"
assert_exit "malformed JSON exit 0" "$RC" "0"

# Test 10: NOTE mentions the three workarounds.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"a"}]}],"PreToolUse":[{"matcher":"","hooks":[{"type":"command","command":"b"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D")
assert_contains "advisory mentions Delay Cowork" "$OUT" "Delay Cowork"
assert_contains "advisory mentions Manual execution" "$OUT" "Manual execution"
assert_contains "advisory mentions CLI-only" "$OUT" "CLI-only"

# Test 11: NOTE references issues #63360 and #63047.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"a"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D")
assert_contains "advisory cites #63360" "$OUT" "63360"
assert_contains "advisory cites #63047" "$OUT" "63047"

# Test 12: NOTE references cluster-tracker URL.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"a"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D")
assert_contains "advisory points at cluster-tracker" "$OUT" "cluster-tracker"

# Test 13: Hook never blocks.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"a"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D"); RC=$?
assert_exit "advisory never blocks" "$RC" "0"

# Test 14: Stop hooks count toward total.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
cat > "$S" <<'JSON'
{
  "hooks": {
    "Stop": [{"matcher":"","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"},{"type":"command","command":"c"}]}]
  }
}
JSON
OUT=$(run_hook "$S" "$D")
assert_contains "Stop array counts" "$OUT" "3 CLI hooks"

# Test 15: PostToolUse hooks count.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"PostToolUse":[{"matcher":"","hooks":[{"type":"command","command":"a"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D")
assert_contains "PostToolUse counts" "$OUT" "1 CLI hook"

# Test 16: Concurrent invocations don't trample each other.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"a"}]}]}}' > "$S"
PIDS=()
for i in 1 2 3 4 5; do
    (run_hook "$S" "$D-$i" > /dev/null 2>&1) &
    PIDS+=($!)
done
ALL_OK=1
for pid in "${PIDS[@]}"; do
    wait "$pid" || ALL_OK=0
done
if [ "$ALL_OK" = "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: concurrent invocations"; fi

# Test 17: Settings file values are NEVER echoed back (privacy).
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
cat > "$S" <<'JSON'
{
  "hooks": {
    "SessionStart": [{"matcher":"","hooks":[{"type":"command","command":"echo SECRET_PROJECT_NAME"}]}]
  }
}
JSON
OUT=$(run_hook "$S" "$D")
assert_not_contains "secret command never echoed" "$OUT" "SECRET_PROJECT_NAME"

# Test 18: Hook event names are NOT echoed back individually (privacy).
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"echo"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D")
# The advisory lists event names statically (mentions UserPromptSubmit, Stop,
# etc.) but does not enumerate which specific events the operator has configured.
# This test ensures we list the standard set, not the operator-specific list.
assert_contains "static event list mentions UserPromptSubmit" "$OUT" "UserPromptSubmit"

# Test 19: NOTE explains the disable command.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"a"}]}]}}' > "$S"
OUT=$(run_hook "$S" "$D")
assert_contains "disable command shown" "$OUT" "CC_COWORK_WARNER_DISABLE=1"

# Test 20: Settings with non-hooks fields don't affect count.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
cat > "$S" <<'JSON'
{
  "model": "claude-opus-4-7",
  "permissions": {"defaultMode": "default"},
  "hooks": {
    "SessionStart": [{"matcher":"","hooks":[{"type":"command","command":"a"}]}]
  }
}
JSON
OUT=$(run_hook "$S" "$D")
assert_contains "other fields ignored, count=1" "$OUT" "1 CLI hook"

# Test 21: No hooks key at all → silent.
PATHS=$(fresh_paths); S=${PATHS%|*}; D=${PATHS#*|}
echo '{"model":"claude-opus-4-7"}' > "$S"
OUT=$(run_hook "$S" "$D")
assert_not_contains "no hooks key silent" "$OUT" "NOTE"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ] || exit 1
