#!/bin/bash
# Tests for tokenizer-ratio-alert.sh — uses a stub curl on PATH to avoid real
# network calls. The stub inspects its argv for the model name and prints a
# minimal JSON body with a hardcoded input_tokens count.
HOOK="examples/tokenizer-ratio-alert.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

make_stub_curl() {
  local old_tokens="$1"
  local new_tokens="$2"
  local dir
  dir=$(mktemp -d)
  cat >"$dir/curl" <<EOF
#!/usr/bin/env bash
# Stub curl: returns hardcoded token counts based on the model in the
# request body. Reads -d <payload> from argv.
body=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -d) body="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
if echo "\$body" | grep -q '4-6'; then
  printf '{"input_tokens": %s}\n' "$old_tokens"
elif echo "\$body" | grep -q '4-7'; then
  printf '{"input_tokens": %s}\n' "$new_tokens"
else
  printf '{}\n'
fi
EOF
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

LONG_PROMPT=$(printf 'x%.0s' {1..3000})   # 3000 chars ≫ default 2000 (= 500 tokens * 4)

# Test 1: ratio above threshold → alert
STUB=$(make_stub_curl 1000 1500)          # ratio 1.5 > default 1.40
PAYLOAD=$(jq -n --arg p "$LONG_PROMPT" '{tool_input: {prompt: $p}}')
export ANTHROPIC_API_KEY="test-key"
OUT=$(PATH="$STUB:/usr/bin:/bin" printf '%s' "$PAYLOAD" | \
  PATH="$STUB:/usr/bin:/bin" bash "$HOOK" 2>&1)
# The above PATH-with-printf doesn't propagate; redo via explicit env:
OUT=$(PATH="$STUB:/usr/bin:/bin" ANTHROPIC_API_KEY=test-key bash -c "printf '%s' \"\$1\" | bash \"$HOOK\"" _ "$PAYLOAD" 2>&1)
RC=$?
assert_exit "alert path exits 0" "$RC" 0
assert_contains "alert mentions tokenizer-ratio" "$OUT" "tokenizer-ratio-alert"
assert_contains "alert shows ratio 1.5" "$OUT" "1.5"
rm -rf "$STUB"

# Test 2: ratio below threshold → no alert
STUB=$(make_stub_curl 1000 1300)          # 1.3 < 1.40
OUT=$(PATH="$STUB:/usr/bin:/bin" ANTHROPIC_API_KEY=test-key bash -c "printf '%s' \"\$1\" | bash \"$HOOK\"" _ "$PAYLOAD" 2>&1)
assert_not_contains "no alert when ratio below threshold" "$OUT" "tokenizer-ratio-alert:"
rm -rf "$STUB"

# Test 3: prompt too short → skip measurement entirely
SHORT_PAYLOAD=$(jq -n '{tool_input: {prompt: "hi"}}')
STUB=$(make_stub_curl 1000 1500)
OUT=$(PATH="$STUB:/usr/bin:/bin" ANTHROPIC_API_KEY=test-key bash -c "printf '%s' \"\$1\" | bash \"$HOOK\"" _ "$SHORT_PAYLOAD" 2>&1)
RC=$?
assert_exit "short prompt exits 0" "$RC" 0
assert_not_contains "short prompt no alert" "$OUT" "tokenizer-ratio-alert:"
rm -rf "$STUB"

# Test 4: no API key → no-op with notice
unset ANTHROPIC_API_KEY
OUT=$(printf '%s' "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "no API key exits 0" "$RC" 0
assert_contains "no-key notice printed" "$OUT" "ANTHROPIC_API_KEY not set"

# Test 5: empty prompt and no transcript → silent no-op
OUT=$(printf '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty payload exits 0" "$RC" 0
assert_not_contains "empty payload no alert" "$OUT" "tokenizer-ratio-alert:"

# Test 6: custom threshold respected
STUB=$(make_stub_curl 1000 1200)          # 1.2
export ANTHROPIC_API_KEY="test-key"
OUT=$(PATH="$STUB:/usr/bin:/bin" ANTHROPIC_API_KEY=test-key TOKENIZER_RATIO_THRESHOLD=1.10 \
  bash -c "printf '%s' \"\$1\" | bash \"$HOOK\"" _ "$PAYLOAD" 2>&1)
assert_contains "custom threshold alerts at 1.2 > 1.10" "$OUT" "tokenizer-ratio-alert"
rm -rf "$STUB"

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
