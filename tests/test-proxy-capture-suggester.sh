#!/bin/bash
# Tests for proxy-capture-suggester.sh
HOOK="$(dirname "$0")/../examples/proxy-capture-suggester.sh"
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

# Helper: run hook with a clean env. The caller passes overrides as VAR=value tokens.
run_hook() {
  env -i HOME="$HOME" PATH="$PATH" "$@" bash "$HOOK" 2>&1
}

echo "Testing proxy-capture-suggester.sh"
echo "===================================="

# Test 1: Default (ENABLE unset) → silent, no advisory
OUT=$(run_hook)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ENABLE unset → silent (default off, opt-in only)" pass
else
  run_test "ENABLE unset (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: QUIET=1 silences even when ENABLE=1
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 CC_PROXY_CAPTURE_SUGGESTER_QUIET=1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences even with ENABLE=1" pass
else
  run_test "QUIET=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: ENABLE=1 + no proxy → full four-tool advisory emitted
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "Compliance audit intent declared"; then
  run_test "ENABLE=1, no proxy → full advisory emitted" pass
else
  run_test "Full advisory (exit=$EXIT)" fail
fi

# Test 4: ENABLE=1 + HTTPS_PROXY set + no log dir → short advisory about audit sink
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 HTTPS_PROXY=http://127.0.0.1:8080)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ANTHROPIC_LOG_DIR is unset"; then
  run_test "ENABLE=1 + proxy + no log dir → audit-sink advisory" pass
else
  run_test "Audit-sink advisory (exit=$EXIT, OUT excerpt: $(echo "$OUT" | head -1))" fail
fi

# Test 5: ENABLE=1 + HTTPS_PROXY set + ANTHROPIC_LOG_DIR set → silent
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 HTTPS_PROXY=http://127.0.0.1:8080 ANTHROPIC_LOG_DIR=/tmp/audit)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ENABLE=1 + proxy + log dir → silent (fully configured)" pass
else
  run_test "Fully configured silent (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: Lowercase https_proxy honored
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 https_proxy=http://127.0.0.1:8080)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ANTHROPIC_LOG_DIR is unset"; then
  run_test "Lowercase https_proxy detected as active" pass
else
  run_test "Lowercase https_proxy detection (exit=$EXIT)" fail
fi

# Test 7: ALL_PROXY honored as a proxy signal
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 ALL_PROXY=http://127.0.0.1:8080)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ANTHROPIC_LOG_DIR is unset"; then
  run_test "ALL_PROXY detected as active" pass
else
  run_test "ALL_PROXY detection (exit=$EXIT)" fail
fi

# Test 8: Empty HTTPS_PROXY does NOT count as active (treated as unset)
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 HTTPS_PROXY=)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "Compliance audit intent declared"; then
  run_test "Empty HTTPS_PROXY treated as unset → full advisory" pass
else
  run_test "Empty HTTPS_PROXY (exit=$EXIT, OUT excerpt: $(echo "$OUT" | head -1))" fail
fi

# Test 9: Advisory enumerates four distinct proxy tools
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1)
if echo "$OUT" | grep -q "mitmproxy" \
  && echo "$OUT" | grep -qi "burp" \
  && echo "$OUT" | grep -qi "charles" \
  && echo "$OUT" | grep -q "ANTHROPIC_LOG"; then
  run_test "Advisory enumerates four audit paths" pass
else
  run_test "Four-tool enumeration (mitm=$(echo "$OUT" | grep -c mitmproxy), burp=$(echo "$OUT" | grep -ci burp))" fail
fi

# Test 10: Advisory includes a concrete HTTPS_PROXY bridge command
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1)
if echo "$OUT" | grep -q "export HTTPS_PROXY="; then
  run_test "Advisory shows concrete HTTPS_PROXY bridge command" pass
else
  run_test "HTTPS_PROXY bridge command" fail
fi

# Test 11: Advisory references the v2.1.150 cluster issue (#62061)
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1)
if echo "$OUT" | grep -q "62061"; then
  run_test "Advisory references upstream cluster issue #62061" pass
else
  run_test "Issue #62061 reference" fail
fi

# Test 12: Advisory mentions partner hooks for cluster coverage
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1)
if echo "$OUT" | grep -q "cache-residue-detector" \
  && echo "$OUT" | grep -q "server-side-prompt-injection-detector"; then
  run_test "Advisory names both partner hooks (cache-residue + server-side detector)" pass
else
  run_test "Partner hook references" fail
fi

# Test 13: Advisory tells the user how to suppress via QUIET=1
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1)
if echo "$OUT" | grep -q "CC_PROXY_CAPTURE_SUGGESTER_QUIET"; then
  run_test "Advisory tells user how to suppress via QUIET=1" pass
else
  run_test "QUIET suppression instruction" fail
fi

# Test 14: ENABLE=0 explicitly → silent (treats non-1 values as off)
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=0)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ENABLE=0 → silent (only ENABLE=1 opts in)" pass
else
  run_test "ENABLE=0 silences (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 15: ENABLE=true (non-1) → silent (strict ENABLE=1 gate)
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=true)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ENABLE=true → silent (strict ENABLE=1 only)" pass
else
  run_test "ENABLE=true silences (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 16: Hook never blocks the session — all paths exit 0
EXIT_CODES=""
for case in "default" "quiet" "enable-no-proxy" "enable-proxy" "enable-proxy-log" "lowercase" "all-proxy" "empty-proxy" "enable-zero" "enable-true"; do
  case "$case" in
    "default") OUT=$(run_hook); EXIT=$? ;;
    "quiet") OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 CC_PROXY_CAPTURE_SUGGESTER_QUIET=1); EXIT=$? ;;
    "enable-no-proxy") OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1); EXIT=$? ;;
    "enable-proxy") OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 HTTPS_PROXY=http://127.0.0.1:8080); EXIT=$? ;;
    "enable-proxy-log") OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 HTTPS_PROXY=http://127.0.0.1:8080 ANTHROPIC_LOG_DIR=/tmp/x); EXIT=$? ;;
    "lowercase") OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 https_proxy=http://x); EXIT=$? ;;
    "all-proxy") OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 ALL_PROXY=http://x); EXIT=$? ;;
    "empty-proxy") OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 HTTPS_PROXY=); EXIT=$? ;;
    "enable-zero") OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=0); EXIT=$? ;;
    "enable-true") OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=true); EXIT=$? ;;
  esac
  EXIT_CODES="$EXIT_CODES $EXIT"
done
NONZERO=$(echo "$EXIT_CODES" | tr ' ' '\n' | grep -v "^$" | grep -v "^0$" | head -1)
if [ -z "$NONZERO" ]; then
  run_test "Hook never blocks (all 10 paths exit 0)" pass
else
  run_test "Hook never blocks (exit codes: $EXIT_CODES)" fail
fi

# Test 17: Idempotent — two invocations with same env produce identical output
OUT1=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1)
OUT2=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1)
if [ "$OUT1" = "$OUT2" ]; then
  run_test "Idempotent: two invocations produce identical output" pass
else
  run_test "Idempotent output" fail
fi

# Test 18: Audit-sink advisory includes concrete ANTHROPIC_LOG_DIR export command
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 HTTPS_PROXY=http://127.0.0.1:8080)
if echo "$OUT" | grep -q 'export ANTHROPIC_LOG_DIR='; then
  run_test "Audit-sink advisory has concrete export command" pass
else
  run_test "Audit-sink export command" fail
fi

# Test 19: Audit-sink advisory mentions all three GUI tools' save mechanisms
OUT=$(run_hook CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1 HTTPS_PROXY=http://127.0.0.1:8080)
if echo "$OUT" | grep -q "save-stream-file" \
  && echo "$OUT" | grep -qi "burp" \
  && echo "$OUT" | grep -qi "charles"; then
  run_test "Audit-sink advisory enumerates three save mechanisms" pass
else
  run_test "Save mechanism enumeration" fail
fi

echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
