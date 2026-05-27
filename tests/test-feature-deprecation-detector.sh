#!/bin/sh
# Tests for examples/feature-deprecation-detector.sh

set -u
HOOK="$(dirname "$0")/../examples/feature-deprecation-detector.sh"
PASS=0
FAIL=0

assert_no_output() {
    local desc="$1"
    local output="$2"
    if [ -z "$output" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — unexpected output: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1"
    local output="$2"
    local needle="$3"
    if echo "$output" | grep -q "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$needle' in output: $output"
        FAIL=$((FAIL + 1))
    fi
}

# Test 1: Empty input → no output
output=$(echo '{}' | bash "$HOOK" 2>&1)
assert_no_output "empty input produces no output" "$output"

# Test 2: Tool output with no deprecation signal → no output
output=$(echo '{"tool_response":{"output":"Hello, World"}}' | bash "$HOOK" 2>&1)
assert_no_output "non-deprecation output produces no output" "$output"

# Test 3: Known removal /buddy → references issue #45596
output=$(echo '{"tool_response":{"output":"Unknown skill: buddy"}}' | bash "$HOOK" 2>&1)
assert_contains "/buddy detected with #45596 reference" "$output" "45596"

# Test 4: Known removal /buddy → references release version
output=$(echo '{"tool_response":{"output":"Unknown skill: buddy"}}' | bash "$HOOK" 2>&1)
assert_contains "/buddy detected with v2.1.97 release info" "$output" "v2.1.97"

# Test 5: Unknown skill not in known list → still surfaces possible deprecation
output=$(echo '{"tool_response":{"output":"Unknown skill: foobar"}}' | bash "$HOOK" 2>&1)
assert_contains "unknown skill foobar surfaces possible deprecation" "$output" "may have been deprecated"

# Test 6: Unknown command pattern
output=$(echo '{"tool_response":{"output":"Unknown command: /helper"}}' | bash "$HOOK" 2>&1)
assert_contains "Unknown command pattern detected" "$output" "helper"

# Test 7: Command not found pattern
output=$(echo '{"tool_response":{"output":"Command not found: /xyz"}}' | bash "$HOOK" 2>&1)
assert_contains "Command not found pattern detected" "$output" "xyz"

# Test 8: Explicit "is deprecated" notice
output=$(echo '{"tool_response":{"output":"The /old-cmd skill is deprecated"}}' | bash "$HOOK" 2>&1)
assert_contains "is deprecated pattern detected" "$output" "Deprecation signal"

# Test 9: Explicit "has been removed" notice
output=$(echo '{"tool_response":{"output":"This feature has been removed in v2.1.99"}}' | bash "$HOOK" 2>&1)
assert_contains "has been removed pattern detected" "$output" "Deprecation signal"

# Test 10: CC_DEPRECATION_QUIET=1 suppresses all output
output=$(echo '{"tool_response":{"output":"Unknown skill: buddy"}}' | CC_DEPRECATION_QUIET=1 bash "$HOOK" 2>&1)
assert_no_output "QUIET=1 suppresses output" "$output"

# Test 11: Custom known removals list
TMP=$(mktemp -d /tmp/test-deprecation.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/custom.txt" << 'EOF'
/custom|v2.1.150 (2026-05-20)|Custom feature for org-specific test|https://example.com/custom-removal
EOF
output=$(echo '{"tool_response":{"output":"Unknown skill: custom"}}' | CC_DEPRECATION_KNOWN_REMOVALS="$TMP/custom.txt" bash "$HOOK" 2>&1)
assert_contains "custom known removal works" "$output" "Custom feature for org-specific test"

# Test 12: tool_response.content alternative key
output=$(echo '{"tool_response":{"content":"Unknown skill: buddy"}}' | bash "$HOOK" 2>&1)
assert_contains "tool_response.content key works" "$output" "buddy"

# Test 13: Output with no deprecation signal but contains "buddy" word
output=$(echo '{"tool_response":{"output":"I am your buddy"}}' | bash "$HOOK" 2>&1)
assert_no_output "false positive avoided (buddy mention)" "$output"

# Test 14: Multiple deprecation signals — first one wins, no duplicate output
output=$(echo '{"tool_response":{"output":"Unknown skill: buddy and feature has been removed"}}' | bash "$HOOK" 2>&1)
# Should detect /buddy first (more specific match)
assert_contains "first signal wins for multi-signal output" "$output" "45596"

# Test 15: Exit code is 0 regardless of detection
echo '{"tool_response":{"output":"Unknown skill: buddy"}}' | bash "$HOOK" > /dev/null 2>&1
rc=$?
if [ $rc -eq 0 ]; then
    echo "  PASS: exit code 0 (advisory)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: exit code $rc, expected 0"
    FAIL=$((FAIL + 1))
fi

# Test 16: Malformed JSON input → graceful exit
output=$(echo 'not valid json' | bash "$HOOK" 2>&1)
assert_no_output "malformed JSON exits gracefully" "$output"

# Test 17: tool_response with empty output → no detection
output=$(echo '{"tool_response":{"output":""}}' | bash "$HOOK" 2>&1)
assert_no_output "empty tool_response.output produces no output" "$output"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
