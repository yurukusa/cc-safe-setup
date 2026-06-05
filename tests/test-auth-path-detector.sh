#!/bin/bash
# Tests for auth-path-detector.sh (Issue #55909 prevention, complement
# to halt-signal-detector.sh)
HOOK="examples/auth-path-detector.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Helper to build a PreToolUse payload from tool name + JSON tool_input
make_payload() {
    local TOOL="$1"
    local INPUT_JSON="$2"
    printf '{"tool_name":"%s","tool_input":%s}' "$TOOL" "$INPUT_JSON"
}

# Test 1: empty payload, silent pass
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty payload no warning" "$OUT" "auth-path-detector"
assert_exit "empty payload exit 0" "$RC" "0"

# Test 2: bash command unrelated to auth, silent pass
PAYLOAD=$(make_payload "Bash" '{"command":"ls -la /tmp"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "ls no warning" "$OUT" "auth-path-detector"
assert_exit "ls exit 0" "$RC" "0"

# Test 3: WebFetch to /login URL, warn (advisory)
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://example.com/login"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "login url warns" "$OUT" "auth-path-detector"
assert_contains "login url references issue" "$OUT" "55909"
assert_exit "login url advisory exit 0" "$RC" "0"

# Test 4: Bash curl to /signin URL, warn
PAYLOAD=$(make_payload "Bash" '{"command":"curl -s https://acme.example.com/signin | head"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "signin curl warns" "$OUT" "auth-path-detector"
assert_exit "signin curl advisory exit 0" "$RC" "0"

# Test 5: WebFetch to OAuth authorize endpoint, warn
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://idp.example.com/oauth/authorize?client_id=abc"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "oauth authorize warns" "$OUT" "auth-path-detector"
assert_exit "oauth authorize advisory exit 0" "$RC" "0"

# Test 6: Japanese ログイン token in prompt field, warn
PAYLOAD=$(make_payload "Bash" '{"command":"echo ログインページ を確認"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "japanese login token warns" "$OUT" "auth-path-detector"
assert_exit "japanese login advisory exit 0" "$RC" "0"

# Test 7: SAML/SSO callback path, warn
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://acme.example.com/saml/acs"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "saml warns" "$OUT" "auth-path-detector"
assert_exit "saml advisory exit 0" "$RC" "0"

# Test 8: /credentials path warns
PAYLOAD=$(make_payload "Bash" '{"command":"curl https://api.example.com/credentials"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "credentials warns" "$OUT" "auth-path-detector"
assert_exit "credentials advisory exit 0" "$RC" "0"

# Test 9: Block mode via CC_AUTH_PATH_BLOCK=1, exit 2
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://example.com/login"}')
OUT=$(echo "$PAYLOAD" | CC_AUTH_PATH_BLOCK=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "block mode warns" "$OUT" "auth-path-detector"
assert_exit "block mode exit 2" "$RC" "2"

# Test 10: Allowlist suppresses warning when match contains allowed substring
PAYLOAD=$(make_payload "WebFetch" '{"url":"http://localhost:3000/login"}')
OUT=$(echo "$PAYLOAD" | CC_AUTH_PATH_ALLOW="localhost:3000" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "allowlist suppresses warning" "$OUT" "auth-path-detector"
assert_exit "allowlist exit 0" "$RC" "0"

# Test 11: Allowlist with multiple tokens
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://staging.example.com/login"}')
OUT=$(echo "$PAYLOAD" | CC_AUTH_PATH_ALLOW="dev.example.com,staging.example.com" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "allowlist multi suppresses" "$OUT" "auth-path-detector"
assert_exit "allowlist multi exit 0" "$RC" "0"

# Test 12: Extra patterns via CC_AUTH_PATH_EXTRA
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://example.com/verify-email"}')
OUT=$(echo "$PAYLOAD" | CC_AUTH_PATH_EXTRA="verify-email" bash "$HOOK" 2>&1)
RC=$?
assert_contains "extra pattern warns" "$OUT" "auth-path-detector"
assert_exit "extra pattern advisory exit 0" "$RC" "0"

# Test 13: github login URL warns
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://github.com/login"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "github login warns" "$OUT" "auth-path-detector"
assert_exit "github login advisory exit 0" "$RC" "0"

# Test 14: accounts.google.com warns
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://accounts.google.com/o/oauth2/v2/auth"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "google idp warns" "$OUT" "auth-path-detector"
assert_exit "google idp advisory exit 0" "$RC" "0"

# Test 15: Path with /reset-password warns
PAYLOAD=$(make_payload "Bash" '{"command":"curl https://app.example.com/reset-password"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "reset-password warns" "$OUT" "auth-path-detector"
assert_exit "reset-password advisory exit 0" "$RC" "0"

# Test 16: WebSearch with login query — should NOT warn (only path-style match)
PAYLOAD=$(make_payload "WebSearch" '{"query":"how to write a secure login form"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "websearch login query no warning" "$OUT" "auth-path-detector"
assert_exit "websearch login query exit 0" "$RC" "0"

# Test 17: tool_input has URL field with capital URL key
PAYLOAD=$(make_payload "Custom" '{"URL":"https://example.com/oauth/authorize"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "capital URL key warns" "$OUT" "auth-path-detector"
assert_exit "capital URL key advisory exit 0" "$RC" "0"

# Test 18: tool_input has location field
PAYLOAD=$(make_payload "Custom" '{"location":"https://example.com/sso/callback"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "location field warns" "$OUT" "auth-path-detector"
assert_exit "location field advisory exit 0" "$RC" "0"

# Test 19: Bash with both auth path and unrelated content, warn
PAYLOAD=$(make_payload "Bash" '{"command":"echo done && curl https://acme.example.com/oauth/authorize?response_type=code && echo retrieved"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "mixed bash with auth warns" "$OUT" "auth-path-detector"
assert_exit "mixed bash advisory exit 0" "$RC" "0"

# Test 20: missing tool_name silently passes
PAYLOAD='{"tool_input":{"url":"https://example.com/login"}}'
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "no tool name no warning" "$OUT" "auth-path-detector"
assert_exit "no tool name exit 0" "$RC" "0"

# Test 21: Empty tool_input passes silently
PAYLOAD='{"tool_name":"Bash","tool_input":{}}'
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty tool_input no warning" "$OUT" "auth-path-detector"
assert_exit "empty tool_input exit 0" "$RC" "0"

# Test 22: signin with hyphen variant
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://example.com/sign-in"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "sign-in variant warns" "$OUT" "auth-path-detector"
assert_exit "sign-in variant advisory exit 0" "$RC" "0"

# Test 23: openid endpoint warns
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://example.com/openid/.well-known"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "openid warns" "$OUT" "auth-path-detector"
assert_exit "openid advisory exit 0" "$RC" "0"

# Test 24: Bash without command field passes
PAYLOAD='{"tool_name":"Bash","tool_input":{"description":"some descriptive text mentioning login"}}'
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "bash with description only no warning" "$OUT" "auth-path-detector"
assert_exit "bash with description only exit 0" "$RC" "0"

# Test 25: japanese 認証ページ token warns
PAYLOAD=$(make_payload "Bash" '{"command":"echo 認証ページ に移動"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "japanese auth page token warns" "$OUT" "auth-path-detector"
assert_exit "japanese auth page advisory exit 0" "$RC" "0"

# Test 26: Allowlist not matching falls through to warning
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://prod.example.com/login"}')
OUT=$(echo "$PAYLOAD" | CC_AUTH_PATH_ALLOW="localhost,staging.example.com" bash "$HOOK" 2>&1)
RC=$?
assert_contains "allowlist non-match still warns" "$OUT" "auth-path-detector"
assert_exit "allowlist non-match advisory exit 0" "$RC" "0"

# Test 27: Block mode + extra pattern combination
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://example.com/2fa-verify"}')
OUT=$(echo "$PAYLOAD" | CC_AUTH_PATH_EXTRA="2fa-verify" CC_AUTH_PATH_BLOCK=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "extra+block warns" "$OUT" "auth-path-detector"
assert_exit "extra+block exit 2" "$RC" "2"

# Test 28: Mention of auth path inside a code review prompt should warn
PAYLOAD=$(make_payload "WebFetch" '{"url":"https://login.microsoftonline.com/common/oauth2/v2.0/authorize"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "ms login idp warns" "$OUT" "auth-path-detector"
assert_exit "ms login idp advisory exit 0" "$RC" "0"

# Test 29: Allowlist works with just a partial substring
PAYLOAD=$(make_payload "WebFetch" '{"url":"http://127.0.0.1:8080/oauth/authorize"}')
OUT=$(echo "$PAYLOAD" | CC_AUTH_PATH_ALLOW="127.0.0.1" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "127 allowlist suppresses" "$OUT" "auth-path-detector"
assert_exit "127 allowlist exit 0" "$RC" "0"

# Test 30: Multiple auth tokens in one input matches first
PAYLOAD=$(make_payload "Bash" '{"command":"curl /login && curl /oauth/authorize"}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_contains "multi token warns" "$OUT" "auth-path-detector"
assert_exit "multi token advisory exit 0" "$RC" "0"

echo
echo "================================="
echo "  PASS: $PASS  FAIL: $FAIL"
echo "================================="
[ "$FAIL" -eq 0 ]
