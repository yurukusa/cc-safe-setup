#!/bin/bash
# Tests for persisted-1m-model-advisor.sh
HOOK="examples/persisted-1m-model-advisor.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }

TMP=$(mktemp -d)
export HOME="$TMP"            # isolate user settings
mkdir -p "$HOME/.claude"
PROJ="$TMP/proj"; mkdir -p "$PROJ/.claude"
INPUT_NOPROJ='{}'
INPUT_PROJ="{\"cwd\":\"$PROJ\"}"

clean_env() { unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_MODEL CC_1M_ADVISOR CC_1M_ADVISOR_QUIET; }

# Test 1: no settings, no env → silent
clean_env; rm -f "$HOME/.claude/settings.json"
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_not_contains "no pin → silent" "$OUT" "persisted-1m-model-advisor"

# Test 2: user settings model pins [1m] → warns and names the source
clean_env
printf '{"model":"claude-opus-4-8[1m]"}' > "$HOME/.claude/settings.json"
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_contains "user settings [1m] warns" "$OUT" "persisted-1m-model-advisor"
assert_contains "names user settings source" "$OUT" "user settings"
assert_contains "shows the pinned value" "$OUT" "claude-opus-4-8[1m]"
assert_contains "offers disable env var" "$OUT" "CLAUDE_CODE_DISABLE_1M_CONTEXT=1"

# Test 3: non-[1m] model in settings → silent
clean_env
printf '{"model":"claude-opus-4-8"}' > "$HOME/.claude/settings.json"
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_not_contains "non-1m model silent" "$OUT" "persisted-1m-model-advisor"

# Test 4: env ANTHROPIC_DEFAULT_OPUS_MODEL pins [1m] → warns
clean_env; rm -f "$HOME/.claude/settings.json"
OUT=$(ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-8[1m]' bash -c "echo '$INPUT_NOPROJ' | bash '$HOOK'" 2>&1)
assert_contains "env opus [1m] warns" "$OUT" "ANTHROPIC_DEFAULT_OPUS_MODEL"

# Test 5: project settings pin [1m] (via cwd) → warns
clean_env; rm -f "$HOME/.claude/settings.json"
printf '{"model":"claude-sonnet-4-6[1m]"}' > "$PROJ/.claude/settings.json"
OUT=$(echo "$INPUT_PROJ" | bash "$HOOK" 2>&1)
assert_contains "project settings [1m] warns" "$OUT" "project settings"
assert_contains "shows sonnet value" "$OUT" "claude-sonnet-4-6[1m]"
rm -f "$PROJ/.claude/settings.json"

# Test 6: CC_1M_ADVISOR=off → silent even with a pin
clean_env
printf '{"model":"claude-opus-4-8[1m]"}' > "$HOME/.claude/settings.json"
OUT=$(CC_1M_ADVISOR=off bash -c "echo '$INPUT_NOPROJ' | bash '$HOOK'" 2>&1)
assert_not_contains "off mode silent" "$OUT" "persisted-1m-model-advisor"

# Test 7: malformed settings json → fails open (silent, no crash)
clean_env
printf 'not json' > "$HOME/.claude/settings.json"
OUT=$(echo "$INPUT_NOPROJ" | bash "$HOOK" 2>&1)
assert_not_contains "malformed settings fails open" "$OUT" "persisted-1m-model-advisor"

# Test 8: malformed hook input → fails open
clean_env
printf '{"model":"claude-opus-4-8[1m]"}' > "$HOME/.claude/settings.json"
OUT=$(echo 'not json' | bash "$HOOK" 2>&1)
assert_contains "bad input still reads user settings" "$OUT" "persisted-1m-model-advisor"

rm -r "$TMP" 2>/dev/null
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
