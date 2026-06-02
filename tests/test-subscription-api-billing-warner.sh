#!/bin/bash
# Tests for subscription-api-billing-warner.sh
HOOK="examples/subscription-api-billing-warner.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"

# Controlled temp settings files
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
EMPTY_SETTINGS="$TMP/empty-settings.json"
printf '{"hooks":{}}' > "$EMPTY_SETTINGS"
HELPER_SETTINGS="$TMP/helper-settings.json"
printf '{"apiKeyHelper":"/usr/local/bin/get-key.sh","permissions":{}}' > "$HELPER_SETTINGS"
NOFILE="$TMP/does-not-exist.json"

# Base env wrapper: clears the three signals so "absent" is deterministic
# even though this test may run inside a Claude Code session that sets them.
run_clean() { env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_ACCOUNT_LABEL "$@"; }

# Test 1: nothing set, empty settings → silent pass
OUT=$(run_clean CC_SUB_BILLING_SETTINGS_OVERRIDE="$EMPTY_SETTINGS" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "clean env no advisory" "$OUT" "API / purchased credits"
assert_exit "clean env exit 0" "$RC" "0"

# Test 2: ANTHROPIC_API_KEY set → advisory + exit 0
# (placeholder value deliberately NOT in Anthropic key format to avoid
#  secret-scanning false positives; the hook never reads the value anyway)
OUT=$(run_clean ANTHROPIC_API_KEY="dummy-placeholder-LEAKCANARY42" \
      CC_SUB_BILLING_SETTINGS_OVERRIDE="$NOFILE" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "api key triggers advisory" "$OUT" "API / purchased credits"
assert_contains "advisory names the env var" "$OUT" "ANTHROPIC_API_KEY is set"
assert_contains "advisory cites #64613" "$OUT" "#64613"
assert_exit "api key advisory exit 0" "$RC" "0"

# Test 3: hook never prints the key value (the canary must not leak)
assert_not_contains "key value never printed" "$OUT" "LEAKCANARY42"

# Test 4: ANTHROPIC_AUTH_TOKEN set → advisory
OUT=$(run_clean ANTHROPIC_AUTH_TOKEN="tok-abc" \
      CC_SUB_BILLING_SETTINGS_OVERRIDE="$NOFILE" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "auth token triggers advisory" "$OUT" "ANTHROPIC_AUTH_TOKEN is set"
assert_exit "auth token exit 0" "$RC" "0"

# Test 5: apiKeyHelper in settings → advisory naming the file
OUT=$(run_clean CC_SUB_BILLING_SETTINGS_OVERRIDE="$HELPER_SETTINGS" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "apiKeyHelper triggers advisory" "$OUT" "apiKeyHelper is configured"
assert_contains "apiKeyHelper names the file" "$OUT" "helper-settings.json"
assert_exit "apiKeyHelper exit 0" "$RC" "0"

# Test 6: settings without apiKeyHelper → no advisory from that source
OUT=$(run_clean CC_SUB_BILLING_SETTINGS_OVERRIDE="$EMPTY_SETTINGS" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "empty settings no advisory" "$OUT" "apiKeyHelper is configured"

# Test 7: CC_SUB_BILLING_DISABLE=1 silences even with key set
OUT=$(run_clean ANTHROPIC_API_KEY="sk-x" CC_SUB_BILLING_DISABLE=1 \
      CC_SUB_BILLING_SETTINGS_OVERRIDE="$HELPER_SETTINGS" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "disable suppresses advisory" "$OUT" "API / purchased credits"
assert_exit "disable exit 0" "$RC" "0"

# Test 8: ANTHROPIC_ACCOUNT_LABEL set → silent (deliberate API use)
OUT=$(env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
      ANTHROPIC_API_KEY="sk-x" ANTHROPIC_ACCOUNT_LABEL="work" \
      CC_SUB_BILLING_SETTINGS_OVERRIDE="$HELPER_SETTINGS" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "account label suppresses advisory" "$OUT" "API / purchased credits"
assert_exit "account label exit 0" "$RC" "0"

# Test 9: advisory points to /status and the refund path
OUT=$(run_clean ANTHROPIC_API_KEY="sk-x" \
      CC_SUB_BILLING_SETTINGS_OVERRIDE="$NOFILE" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "advisory points to /status" "$OUT" "/status"
assert_contains "advisory points to refund path" "$OUT" "support.claude.com"
assert_contains "advisory names silence path" "$OUT" "CC_SUB_BILLING_DISABLE"

# Test 10: stdin payload consumed without hanging
PAYLOAD='{"hook_event_name":"SessionStart","session_id":"abc"}'
OUT=$(echo "$PAYLOAD" | run_clean ANTHROPIC_API_KEY="sk-x" \
      CC_SUB_BILLING_SETTINGS_OVERRIDE="$NOFILE" \
      bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "stdin consumed, advisory still fires" "$OUT" "API / purchased credits"
assert_exit "stdin path exit 0" "$RC" "0"

# Test 11: both env var and apiKeyHelper → advisory lists both reasons
OUT=$(run_clean ANTHROPIC_API_KEY="sk-x" \
      CC_SUB_BILLING_SETTINGS_OVERRIDE="$HELPER_SETTINGS" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "both sources: env var listed" "$OUT" "ANTHROPIC_API_KEY is set"
assert_contains "both sources: helper listed" "$OUT" "apiKeyHelper is configured"
assert_exit "both sources exit 0" "$RC" "0"

# Test 12: empty-string env var is treated as not set
OUT=$(run_clean ANTHROPIC_API_KEY="" \
      CC_SUB_BILLING_SETTINGS_OVERRIDE="$EMPTY_SETTINGS" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "empty api key no advisory" "$OUT" "API / purchased credits"
assert_exit "empty api key exit 0" "$RC" "0"

# Test 13: multiple settings paths (colon-separated), one has helper
OUT=$(run_clean CC_SUB_BILLING_SETTINGS_OVERRIDE="$EMPTY_SETTINGS:$HELPER_SETTINGS" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "multi-path finds helper" "$OUT" "apiKeyHelper is configured"
assert_exit "multi-path exit 0" "$RC" "0"

# Test 14: disable wins even with stdin payload
OUT=$(echo "$PAYLOAD" | run_clean ANTHROPIC_API_KEY="sk-x" CC_SUB_BILLING_DISABLE=1 \
      CC_SUB_BILLING_SETTINGS_OVERRIDE="$HELPER_SETTINGS" \
      bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "disable with stdin silent" "$OUT" "API / purchased credits"
assert_exit "disable with stdin exit 0" "$RC" "0"

# Test 15: apiKeyHelper present but empty string value → not triggered
EMPTYHELPER="$TMP/empty-helper.json"
printf '{"apiKeyHelper":""}' > "$EMPTYHELPER"
OUT=$(run_clean CC_SUB_BILLING_SETTINGS_OVERRIDE="$EMPTYHELPER" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "empty apiKeyHelper value no advisory" "$OUT" "apiKeyHelper is configured"
assert_exit "empty apiKeyHelper exit 0" "$RC" "0"

# Test 16: unreadable/missing settings path is skipped silently (no error)
OUT=$(run_clean CC_SUB_BILLING_SETTINGS_OVERRIDE="$NOFILE" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "missing settings no advisory" "$OUT" "apiKeyHelper is configured"
assert_exit "missing settings exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
