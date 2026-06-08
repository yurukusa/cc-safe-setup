#!/bin/bash
# Tests for disabled-feature-toggle-advisor.sh
HOOK="examples/disabled-feature-toggle-advisor.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }

TMP=$(mktemp -d)
export HOME="$TMP"
mkdir -p "$HOME/.claude"
PROJ="$TMP/proj"; mkdir -p "$PROJ/.claude"
INPUT_NOPROJ='{}'
INPUT_PROJ="{\"cwd\":\"$PROJ\"}"
clean() { unset CC_DISABLE_TOGGLE_ADVISOR; rm -f "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" "$PROJ/.claude/settings.json" "$PROJ/.claude/settings.local.json"; }

# Test 1: no settings → silent
clean
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_not_contains "no settings → silent" "$OUT" "disabled-feature-toggle-advisor"

# Test 2: AUTO_MEMORY disabled (the #66232 case) → warns and names it
clean
printf '{"env":{"CLAUDE_CODE_DISABLE_AUTO_MEMORY":"1"}}' > "$HOME/.claude/settings.json"
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_contains "auto_memory disabled warns" "$OUT" "disabled-feature-toggle-advisor"
assert_contains "names the key" "$OUT" "CLAUDE_CODE_DISABLE_AUTO_MEMORY"
assert_contains "explains memory wont load" "$OUT" "persistent memory will NOT load"
assert_contains "cites the incident" "$OUT" "#66232"

# Test 3: env block present but NO disable toggle → silent
clean
printf '{"env":{"FOO":"bar","CC_MD_REINJECT_EVERY":"5"}}' > "$HOME/.claude/settings.json"
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_not_contains "non-disable env → silent" "$OUT" "disabled-feature-toggle-advisor"

# Test 4: disable toggle set to falsy ("0") → silent (not active)
clean
printf '{"env":{"CLAUDE_CODE_DISABLE_AUTO_MEMORY":"0"}}' > "$HOME/.claude/settings.json"
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_not_contains "falsy toggle → silent" "$OUT" "disabled-feature-toggle-advisor"

# Test 5: multiple toggles incl. an unknown DISABLE → lists all, generic note for unknown
clean
printf '{"env":{"DISABLE_TELEMETRY":"true","CLAUDE_CODE_DISABLE_SOMETHING_NEW":"1"}}' > "$HOME/.claude/settings.json"
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_contains "telemetry listed" "$OUT" "DISABLE_TELEMETRY"
assert_contains "unknown disable listed" "$OUT" "CLAUDE_CODE_DISABLE_SOMETHING_NEW"
assert_contains "generic note for unknown" "$OUT" "a built-in behavior is turned off"

# Test 6: project settings (via cwd) toggle → warns
clean
printf '{"env":{"CLAUDE_CODE_DISABLE_1M_CONTEXT":"1"}}' > "$PROJ/.claude/settings.json"
OUT=$(echo "$INPUT_PROJ" | bash "$HOOK" 2>&1)
assert_contains "project settings toggle warns" "$OUT" "CLAUDE_CODE_DISABLE_1M_CONTEXT"
assert_contains "1m note" "$OUT" "1M context window is turned off"

# Test 7: CC_DISABLE_TOGGLE_ADVISOR=off → silent even with a toggle set
clean
printf '{"env":{"CLAUDE_CODE_DISABLE_AUTO_MEMORY":"1"}}' > "$HOME/.claude/settings.json"
OUT=$(CC_DISABLE_TOGGLE_ADVISOR=off bash -c "echo '$INPUT_NOPROJ' | bash '$HOOK'" 2>&1)
assert_not_contains "off toggle silences" "$OUT" "disabled-feature-toggle-advisor"

# Test 8: never blocks (exit 0) even when warning
clean
printf '{"env":{"CLAUDE_CODE_DISABLE_AUTO_MEMORY":"1"}}' > "$HOME/.claude/settings.json"
echo "$INPUT_NOPROJ" | bash "$HOOK" >/dev/null 2>&1
assert_contains "exit 0 (never blocks)" "$?" "0"

# Test 9: malformed settings.json → silent, no crash (fail open)
clean
printf '{bad json' > "$HOME/.claude/settings.json"
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_not_contains "malformed json → silent" "$OUT" "disabled-feature-toggle-advisor"

echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$TMP"
[ "$FAIL" -eq 0 ]
