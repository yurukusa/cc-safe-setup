#!/bin/bash
# Tests for bypass-mode-effective-verifier.sh (Cluster 6 Axis 7)
# Covers: three bypass-signal detection paths, silent on non-bypass,
# disable/silent environment toggles, JSON output shape, fail-open.

HOOK="examples/bypass-mode-effective-verifier.sh"
PASS=0 FAIL=0

run_hook() {
    # $1 = JSON payload, optional extra env vars trail as $2..$n
    local payload="$1"; shift
    # Always clear bypass env vars so each test starts clean.
    env -u CLAUDE_PERMISSION_MODE -u CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS \
        -u CC_BYPASS_VERIFIER_DISABLE -u CC_BYPASS_VERIFIER_SILENT \
        "$@" bash "$HOOK" <<< "$payload" 2>&1
}

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: no bypass signal — silent
OUT=$(run_hook '{}')
RC=$?
assert_exit "no bypass exit 0" "$RC" "0"
assert_not_contains "no bypass no warning" "$OUT" "bypass mode ACTIVE"
assert_not_contains "no bypass no advisory heading" "$OUT" "bypass-mode-effective-verifier"

# Test 2: hook-input permission_mode = bypassPermissions detected
OUT=$(run_hook '{"permission_mode":"bypassPermissions"}')
RC=$?
assert_exit "hook input bypass exit 0" "$RC" "0"
assert_contains "hook input bypass warns" "$OUT" "bypass mode ACTIVE"
assert_contains "hook input bypass names signal source" "$OUT" "hook input permission_mode"
assert_contains "hook input bypass references #29214" "$OUT" "#29214"
assert_contains "hook input bypass references #36192" "$OUT" "#36192"

# Test 3: hook-input permissionMode (camelCase variant) also detected
OUT=$(run_hook '{"permissionMode":"bypassPermissions"}')
RC=$?
assert_exit "camelCase exit 0" "$RC" "0"
assert_contains "camelCase warns" "$OUT" "bypass mode ACTIVE"

# Test 4: env var CLAUDE_PERMISSION_MODE=bypassPermissions detected
OUT=$(run_hook '{}' CLAUDE_PERMISSION_MODE=bypassPermissions)
RC=$?
assert_exit "env CLAUDE_PERMISSION_MODE exit 0" "$RC" "0"
assert_contains "env CLAUDE_PERMISSION_MODE warns" "$OUT" "bypass mode ACTIVE"
assert_contains "env CLAUDE_PERMISSION_MODE signal named" "$OUT" "CLAUDE_PERMISSION_MODE=bypassPermissions"

# Test 5: env var CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=1 detected
OUT=$(run_hook '{}' CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=1)
RC=$?
assert_exit "env DANGEROUSLY=1 exit 0" "$RC" "0"
assert_contains "env DANGEROUSLY=1 warns" "$OUT" "bypass mode ACTIVE"
assert_contains "env DANGEROUSLY=1 signal named" "$OUT" "CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=1"

# Test 6: env var CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=true detected (case variants)
OUT=$(run_hook '{}' CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=true)
assert_contains "env DANGEROUSLY=true warns" "$OUT" "bypass mode ACTIVE"

OUT=$(run_hook '{}' CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=TRUE)
assert_contains "env DANGEROUSLY=TRUE warns" "$OUT" "bypass mode ACTIVE"

# Test 7: env var CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=0 does NOT trigger
OUT=$(run_hook '{}' CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=0)
RC=$?
assert_exit "env DANGEROUSLY=0 exit 0" "$RC" "0"
assert_not_contains "env DANGEROUSLY=0 silent" "$OUT" "bypass mode ACTIVE"

# Test 8: env var CLAUDE_PERMISSION_MODE=default does NOT trigger
OUT=$(run_hook '{}' CLAUDE_PERMISSION_MODE=default)
assert_not_contains "env default mode silent" "$OUT" "bypass mode ACTIVE"

OUT=$(run_hook '{}' CLAUDE_PERMISSION_MODE=acceptEdits)
assert_not_contains "env acceptEdits silent" "$OUT" "bypass mode ACTIVE"

# Test 9: CC_BYPASS_VERIFIER_DISABLE=1 silences even with bypass active
OUT=$(run_hook '{"permission_mode":"bypassPermissions"}' CC_BYPASS_VERIFIER_DISABLE=1)
RC=$?
assert_exit "disabled exit 0" "$RC" "0"
assert_not_contains "disabled no warning" "$OUT" "bypass mode ACTIVE"
assert_not_contains "disabled no JSON output" "$OUT" "hookSpecificOutput"

# Test 10: CC_BYPASS_VERIFIER_SILENT=1 skips JSON but keeps stderr advisory
OUT=$(run_hook '{"permission_mode":"bypassPermissions"}' CC_BYPASS_VERIFIER_SILENT=1)
RC=$?
assert_exit "silent exit 0" "$RC" "0"
assert_contains "silent still emits stderr" "$OUT" "bypass mode ACTIVE"
assert_not_contains "silent no JSON output" "$OUT" "hookSpecificOutput"

# Test 11: JSON output shape is correct when bypass active and not silent
OUT=$(run_hook '{"permission_mode":"bypassPermissions"}')
assert_contains "JSON contains hookSpecificOutput" "$OUT" '"hookSpecificOutput"'
assert_contains "JSON contains hookEventName" "$OUT" '"hookEventName": "SessionStart"'
assert_contains "JSON contains additionalContext" "$OUT" '"additionalContext"'

# Test 12: empty input handled gracefully (jq parses {} default)
OUT=$(run_hook '')
RC=$?
assert_exit "empty input exit 0" "$RC" "0"
assert_not_contains "empty input no warning" "$OUT" "bypass mode ACTIVE"

# Test 13: invalid JSON handled gracefully (no bypass signal extracted)
OUT=$(run_hook 'not json')
RC=$?
assert_exit "invalid JSON exit 0" "$RC" "0"
assert_not_contains "invalid JSON no warning" "$OUT" "bypass mode ACTIVE"

# Test 14: hook input wins when env says default but JSON says bypass
OUT=$(run_hook '{"permission_mode":"bypassPermissions"}' CLAUDE_PERMISSION_MODE=default)
assert_contains "JSON wins over default env" "$OUT" "bypass mode ACTIVE"

# Test 15: multiple signals — first wins (env var, JSON also bypass)
OUT=$(run_hook '{"permission_mode":"bypassPermissions"}' CLAUDE_PERMISSION_MODE=bypassPermissions)
assert_contains "multiple signals still warns" "$OUT" "bypass mode ACTIVE"

# Test 16: known broken surfaces are all named in the warning
OUT=$(run_hook '{"permission_mode":"bypassPermissions"}')
assert_contains "warning names Edit" "$OUT" "Edit tool"
assert_contains "warning names Cowork" "$OUT" "Cowork"
assert_contains "warning names Remote Control" "$OUT" "Remote Control"
assert_contains "warning names v2.1.77 regression" "$OUT" "v2.1.77"
assert_contains "warning references meta-issue #39523" "$OUT" "#39523"

echo ""
echo "Tests: $((PASS+FAIL)) | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
