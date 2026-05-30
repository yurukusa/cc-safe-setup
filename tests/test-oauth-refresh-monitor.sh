#!/bin/bash
# Tests for oauth-refresh-monitor.sh
HOOK="$(dirname "$0")/../examples/oauth-refresh-monitor.sh"
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
STATE="$TMPDIR/state"

reset_state() {
  rm -rf "$STATE"
  mkdir -p "$STATE"
  unset CC_OAUTH_REFRESH_MONITOR_DISABLE
  unset CC_OAUTH_REFRESH_MONITOR_QUIET
}

build_payload() {
  local output="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg o "$output" '{tool_name: "Bash", tool_response: {output: $o}}'
  else
    local escaped
    escaped=$(printf '%s' "$output" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"tool_name":"Bash","tool_response":{"output":"%s"}}' "$escaped"
  fi
}

echo "Testing oauth-refresh-monitor.sh"
echo "================================="

# Test 1: Empty input → silent
reset_state
OUT=$(printf '' | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Empty input is silent" pass
else
  run_test "Empty input (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: Normal tool output with no signature → silent
reset_state
PAYLOAD=$(build_payload "Successfully wrote 200 bytes")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s1" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Normal output (no signature) is silent" pass
else
  run_test "Normal output (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: "Needs authentication" signature fires the advisory
reset_state
PAYLOAD=$(build_payload "Error: MCP server returned: Needs authentication")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s2" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "oauth-refresh-monitor"; then
  run_test "'Needs authentication' signature fires" pass
else
  run_test "Needs auth (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: "refresh token rejected" signature fires
reset_state
PAYLOAD=$(build_payload "HTTP 400: Refresh token rejected by upstream")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s3" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "oauth-refresh-monitor"; then
  run_test "'refresh token rejected' signature fires" pass
else
  run_test "Refresh rejected (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 5: "401" + "refresh" co-occurrence fires
reset_state
PAYLOAD=$(build_payload "HTTP 401 returned during refresh flow")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s4" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "oauth-refresh-monitor"; then
  run_test "401 + refresh co-occurrence fires" pass
else
  run_test "401 refresh (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: "oauth" + "expired" co-occurrence fires
reset_state
PAYLOAD=$(build_payload "OAuth credentials have expired, please re-authenticate")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s5" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "oauth-refresh-monitor"; then
  run_test "oauth + expired co-occurrence fires" pass
else
  run_test "OAuth expired (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: "401" + "token" broad fallback fires
reset_state
PAYLOAD=$(build_payload "HTTP 401: Invalid token in Authorization header")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s6" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "oauth-refresh-monitor"; then
  run_test "401 + token broad fallback fires" pass
else
  run_test "401 token (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 8: DISABLE=1 silences even with signature present
reset_state
PAYLOAD=$(build_payload "Error: needs authentication for the request")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_DISABLE=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences (overrides signature detection)" pass
else
  run_test "DISABLE (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 9: QUIET=1 silences even with signature present
reset_state
PAYLOAD=$(build_payload "Error: needs authentication for the request")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences" pass
else
  run_test "QUIET (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 10: One-shot per session per signature
reset_state
PAYLOAD=$(build_payload "Error: needs authentication")
printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s7" bash "$HOOK" 2>/dev/null
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s7" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "One-shot: same signature silent on second call in same session" pass
else
  run_test "One-shot (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 11: Different signature in same session still fires
reset_state
PAYLOAD1=$(build_payload "needs authentication")
PAYLOAD2=$(build_payload "refresh token rejected")
printf '%s' "$PAYLOAD1" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s8" bash "$HOOK" 2>/dev/null
OUT=$(printf '%s' "$PAYLOAD2" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s8" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "oauth-refresh-monitor"; then
  run_test "Different signature same session still fires" pass
else
  run_test "Different signature (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 12: Same signature in different session fires
reset_state
PAYLOAD=$(build_payload "needs authentication")
printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s9" bash "$HOOK" 2>/dev/null
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s10" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "oauth-refresh-monitor"; then
  run_test "Same signature different session fires" pass
else
  run_test "Different session (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 13: Advisory cites axis 19A anchor (#61912)
reset_state
PAYLOAD=$(build_payload "needs authentication")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s11" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "61912"; then
  run_test "Advisory cites axis 19A anchor (#61912)" pass
else
  run_test "Cites #61912 (out_len=${#OUT})" fail
fi

# Test 14: Advisory cites MCP OAuth DCR re-runs (#59460)
reset_state
PAYLOAD=$(build_payload "needs authentication")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s12" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "59460"; then
  run_test "Advisory cites #59460 MCP OAuth DCR" pass
else
  run_test "Cites #59460 (out_len=${#OUT})" fail
fi

# Test 15: Advisory explains "full re-auth, not retry" recovery
reset_state
PAYLOAD=$(build_payload "needs authentication")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s13" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "full re-auth"; then
  run_test "Advisory explains full re-auth recovery (not retry)" pass
else
  run_test "Full re-auth framing (out_len=${#OUT})" fail
fi

# Test 16: Advisory references field guide gist
reset_state
PAYLOAD=$(build_payload "needs authentication")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s14" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "gist.github.com"; then
  run_test "Advisory references the field guide gist" pass
else
  run_test "Field guide link (out_len=${#OUT})" fail
fi

# Test 17: Advisory cross-references companion hooks
reset_state
PAYLOAD=$(build_payload "needs authentication")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s15" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "auth-status-checker" \
   && printf '%s' "$OUT" | grep -q "auth-expiry-reminder"; then
  run_test "Advisory cross-references both companion hooks" pass
else
  run_test "Companion hooks (out_len=${#OUT})" fail
fi

# Test 18: Case-insensitive matching (uppercase variants)
reset_state
PAYLOAD=$(build_payload "ERROR: NEEDS AUTHENTICATION REQUIRED")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s16" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "oauth-refresh-monitor"; then
  run_test "Case-insensitive matching (uppercase fires)" pass
else
  run_test "Uppercase (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 19: Malformed JSON falls back to raw text search
reset_state
OUT=$(printf 'this is not json but contains needs authentication string' \
  | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
    CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s17" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "oauth-refresh-monitor"; then
  run_test "Malformed JSON falls back to raw-text scan" pass
else
  run_test "Malformed JSON fallback (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 20: Never blocks — exit 0 when firing
reset_state
PAYLOAD=$(build_payload "needs authentication")
printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s18" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Never blocks (exit=0 when firing)" pass
else
  run_test "Exit on fire (exit=$EXIT)" fail
fi

# Test 21: Never blocks — exit 0 when silent
reset_state
PAYLOAD=$(build_payload "normal output, no signature here")
printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Never blocks (exit=0 when silent)" pass
else
  run_test "Exit when silent (exit=$EXIT)" fail
fi

# Test 22: Signature name appears in advisory body
reset_state
PAYLOAD=$(build_payload "Error: refresh token rejected")
OUT=$(printf '%s' "$PAYLOAD" | CC_OAUTH_REFRESH_MONITOR_STATE_DIR="$STATE" \
  CC_OAUTH_REFRESH_MONITOR_SESSION_ID="s19" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "refresh-token-rejected"; then
  run_test "Signature name appears in advisory body" pass
else
  run_test "Signature name (out_len=${#OUT})" fail
fi

echo "================================="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
