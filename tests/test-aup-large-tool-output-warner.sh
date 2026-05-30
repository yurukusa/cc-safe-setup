#!/bin/bash
# Tests for aup-large-tool-output-warner.sh
HOOK="$(dirname "$0")/../examples/aup-large-tool-output-warner.sh"
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
  unset CC_AUP_LARGE_OUTPUT_WARNER_DISABLE
  unset CC_AUP_LARGE_OUTPUT_WARNER_QUIET
}

# Helper: build a PreToolUse JSON payload for Bash with the given command.
bash_payload() {
  local cmd="$1"
  # Escape for JSON via jq when available; fall back to crude escaping.
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}'
  else
    # Best-effort: escape backslash and double-quote only.
    local escaped
    escaped=$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$escaped"
  fi
}

# Run hook with a given command and a given session id; return stdout+stderr in $OUT.
run_hook() {
  local cmd="$1"
  local sid="${2:-test-session}"
  local payload
  payload=$(bash_payload "$cmd")
  OUT=$(printf '%s' "$payload" | CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR="$STATE" \
    CC_AUP_LARGE_OUTPUT_WARNER_SESSION_ID="$sid" bash "$HOOK" 2>&1)
  EXIT=$?
}

echo "Testing aup-large-tool-output-warner.sh"
echo "========================================"

# Test 1: DISABLE=1 silences entirely
reset_state
payload=$(bash_payload "cat /etc/banip/banip.blocklist")
OUT=$(printf '%s' "$payload" | CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR="$STATE" \
  CC_AUP_LARGE_OUTPUT_WARNER_DISABLE=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences entirely on the canonical #61185 trigger" pass
else
  run_test "DISABLE=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: QUIET=1 silences entirely
reset_state
payload=$(bash_payload "cat /etc/banip/banip.blocklist")
OUT=$(printf '%s' "$payload" | CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR="$STATE" \
  CC_AUP_LARGE_OUTPUT_WARNER_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences" pass
else
  run_test "QUIET=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: Non-Bash tool → silent
reset_state
payload='{"tool_name":"Edit","tool_input":{"file_path":"/etc/banip/banip.blocklist"}}'
OUT=$(printf '%s' "$payload" | CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Non-Bash tool (Edit) → silent" pass
else
  run_test "Non-Bash tool (exit=$EXIT, out=$OUT)" fail
fi

# Test 4: Empty command → silent
reset_state
payload='{"tool_name":"Bash","tool_input":{"command":""}}'
OUT=$(printf '%s' "$payload" | CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Empty command → silent" pass
else
  run_test "Empty command (exit=$EXIT, out=$OUT)" fail
fi

# Test 5: The canonical #61185 trigger fires
reset_state
run_hook "cat /etc/banip/banip.blocklist" "session-a"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "cat /etc/banip/banip.blocklist (the #61185 trigger) fires" pass
else
  run_test "Canonical trigger (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: cat /var/log/auth.log fires (Category A, system path)
reset_state
run_hook "cat /var/log/auth.log" "session-b"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "cat on /var/log/ system path fires" pass
else
  run_test "/var/log/ path (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: cat /etc/passwd is silent (not a security-content sentinel path)
reset_state
run_hook "cat /etc/passwd" "session-c"
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "cat /etc/passwd is silent (no security-content match)" pass
else
  run_test "cat /etc/passwd (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 8: cat file.blocklist fires (Category A, file extension)
reset_state
run_hook "cat ~/firewall/myrules.blocklist" "session-d"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "cat on .blocklist extension fires" pass
else
  run_test ".blocklist extension (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 9: cat file.txt is silent
reset_state
run_hook "cat /tmp/notes.txt" "session-e"
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "cat /tmp/notes.txt is silent" pass
else
  run_test "cat /tmp/notes.txt (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 10: cat with | head cap is silent (size cap present)
reset_state
run_hook "cat /etc/banip/banip.blocklist | head -100" "session-f"
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "cat with | head cap is silent (size cap respected)" pass
else
  run_test "Size cap via head (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 11: find on security path fires (Category B)
reset_state
run_hook "find /etc/banip/ -type f" "session-g"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "find on /etc/banip/ fires (Category B)" pass
else
  run_test "find Category B (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 12: find with | head cap is silent
reset_state
run_hook "find /etc/banip/ -type f | head -50" "session-h"
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "find with | head cap is silent" pass
else
  run_test "find + head (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 13: journalctl without cap fires (Category C)
reset_state
run_hook "journalctl" "session-i"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "journalctl without cap fires (Category C)" pass
else
  run_test "journalctl bare (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 14: journalctl -n 100 is silent (cap present)
reset_state
run_hook "journalctl -n 100" "session-j"
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "journalctl -n 100 is silent" pass
else
  run_test "journalctl -n 100 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 15: journalctl --since is silent
reset_state
run_hook 'journalctl --since "1 hour ago"' "session-k"
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "journalctl --since is silent" pass
else
  run_test "journalctl --since (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 16: dmesg without cap fires (Category D)
reset_state
run_hook "dmesg" "session-l"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "dmesg without cap fires (Category D)" pass
else
  run_test "dmesg bare (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 17: dmesg | tail is silent
reset_state
run_hook "dmesg | tail -50" "session-m"
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "dmesg | tail is silent" pass
else
  run_test "dmesg | tail (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 18: grep -r on security path fires (Category E)
reset_state
run_hook "grep -r evil /var/log/" "session-n"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "grep -r on /var/log/ fires (Category E)" pass
else
  run_test "grep -r Category E (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 19: grep -r on non-security path is silent
reset_state
run_hook "grep -r foo /tmp/" "session-o"
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "grep -r on /tmp/ is silent (non-security path)" pass
else
  run_test "grep -r /tmp/ (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 20: wc -l on blocklist is silent (wc itself is a size cap)
reset_state
run_hook "wc -l /etc/banip/banip.blocklist" "session-p"
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "wc -l is silent (it IS the size-cap recommendation)" pass
else
  run_test "wc -l (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 21: One-shot — same pattern fires once per session
reset_state
run_hook "cat /etc/banip/banip.blocklist" "session-q"
FIRST_OUT_LEN=${#OUT}
run_hook "cat /etc/banip/banip.blocklist" "session-q"
SECOND_OUT_LEN=${#OUT}
if [ "$FIRST_OUT_LEN" -gt 100 ] && [ "$SECOND_OUT_LEN" -eq 0 ]; then
  run_test "One-shot: same pattern silent on second call in same session" pass
else
  run_test "One-shot same session (first=$FIRST_OUT_LEN second=$SECOND_OUT_LEN)" fail
fi

# Test 22: One-shot is per (session, pattern) — different command fires
reset_state
run_hook "cat /etc/banip/banip.blocklist" "session-r"
run_hook "dmesg" "session-r"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "One-shot: different pattern in same session still fires" pass
else
  run_test "Different pattern same session (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 23: One-shot is per session — same pattern in new session fires
reset_state
run_hook "cat /etc/banip/banip.blocklist" "session-s"
run_hook "cat /etc/banip/banip.blocklist" "session-t"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "One-shot: same pattern in different session fires again" pass
else
  run_test "Same pattern different session (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 24: Sentinel-only (no category) — command containing blocklist substring
reset_state
run_hook 'echo "blocklist updated" >> /tmp/notes.txt' "session-u"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "Sentinel-only (blocklist substring in echo) fires" pass
else
  run_test "Sentinel-only echo (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 25: iptables-save fires (sentinel)
reset_state
run_hook "iptables-save > /tmp/rules.txt" "session-v"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "iptables-save sentinel fires" pass
else
  run_test "iptables-save (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 26: /etc/fail2ban/ path fires (sentinel)
reset_state
run_hook "ls /etc/fail2ban/" "session-w"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "aup-large-tool-output-warner"; then
  run_test "/etc/fail2ban/ path sentinel fires" pass
else
  run_test "/etc/fail2ban/ (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 27: Advisory references #61185 evidence
reset_state
run_hook "cat /etc/banip/banip.blocklist" "session-x"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "61185"; then
  run_test "Advisory cites #61185 evidence" pass
else
  run_test "Advisory references #61185 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 28: Advisory references #60366 cluster anchor
reset_state
run_hook "cat /etc/banip/banip.blocklist" "session-y"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "60366"; then
  run_test "Advisory cites #60366 cluster anchor" pass
else
  run_test "Advisory references #60366 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 29: Advisory includes a narrower-variant recommendation (head)
reset_state
run_hook "cat /etc/banip/banip.blocklist" "session-z"
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "head -200"; then
  run_test "Advisory recommends head -N narrower variant" pass
else
  run_test "Advisory recommends head (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 30: State directory is auto-created when missing
reset_state
NEW_STATE="$TMPDIR/state-fresh-dir"
[ -d "$NEW_STATE" ] && rmdir "$NEW_STATE"
payload=$(bash_payload "cat /etc/banip/banip.blocklist")
OUT=$(printf '%s' "$payload" | CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR="$NEW_STATE" \
  CC_AUP_LARGE_OUTPUT_WARNER_SESSION_ID="session-fresh" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -d "$NEW_STATE" ] && [ -f "$NEW_STATE/aup-large-tool-output-warner.fired" ]; then
  run_test "State directory auto-created when missing" pass
else
  run_test "State auto-create (exit=$EXIT, dir_exists=$([ -d "$NEW_STATE" ] && echo y || echo n))" fail
fi

# Test 31: Malformed JSON input → silent (does not crash)
reset_state
OUT=$(printf 'this is not json' | CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Malformed JSON input does not crash and stays silent" pass
else
  run_test "Malformed JSON (exit=$EXIT, out=$OUT)" fail
fi

# Test 32: Never blocks — exit always 0 even when firing
reset_state
run_hook "cat /etc/banip/banip.blocklist" "session-blocking-check"
if [ "$EXIT" = "0" ]; then
  run_test "Never blocks (exit=0 even when firing)" pass
else
  run_test "Exit code on fire (exit=$EXIT)" fail
fi

echo "================================"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
