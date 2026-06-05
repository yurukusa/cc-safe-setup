set -uo pipefail
HOOK="$(dirname "$0")/../examples/session-persistence-verifier.sh"
PASS=0
FAIL=0
TEST_DIR=$(mktemp -d)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
echo "=== session-persistence-verifier.sh tests ==="
SESSION_ID="test-session-1"
mkdir -p "$TEST_DIR/projects/myproj"
cat > "$TEST_DIR/projects/myproj/${SESSION_ID}.jsonl" << JSONL
{"type":"queue-operation","operation":"enqueue"}
{"type":"user","message":{"role":"user","content":"hi"}}
{"type":"assistant","message":{"role":"assistant","content":"hello"}}
{"type":"ai-title","sessionId":"test-session-1","aiTitle":"Hi"}
JSONL
INPUT=$(jq -nc --arg sid "$SESSION_ID" '{session_id: $sid}')
output=$(CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" printf '%s' "$INPUT" | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "full event types is a silent no-op"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi
SESSION_ID="test-session-2"
cat > "$TEST_DIR/projects/myproj/${SESSION_ID}.jsonl" << JSONL
{"type":"ai-title","sessionId":"test-session-2","aiTitle":"Title only"}
JSONL
INPUT=$(jq -nc --arg sid "$SESSION_ID" '{session_id: $sid}')
output=$(printf '%s' "$INPUT" | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "60984"; then
    assert_pass "ai-title-only file triggers exit 2 + #60984 mention"
else
    assert_fail "expected exit 2 + #60984 ref, got rc=$rc output=$output"
fi
SESSION_ID="test-session-3"
touch "$TEST_DIR/projects/myproj/${SESSION_ID}.jsonl"
INPUT=$(jq -nc --arg sid "$SESSION_ID" '{session_id: $sid}')
output=$(printf '%s' "$INPUT" | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "empty"; then
    assert_pass "empty file triggers exit 2 + empty message"
else
    assert_fail "expected exit 2 + empty message, got rc=$rc output=$output"
fi
SESSION_ID="test-session-nonexistent"
INPUT=$(jq -nc --arg sid "$SESSION_ID" '{session_id: $sid}')
output=$(printf '%s' "$INPUT" | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing file in advisory mode is silent"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi
SESSION_ID="test-session-nonexistent-2"
INPUT=$(jq -nc --arg sid "$SESSION_ID" '{session_id: $sid}')
output=$(printf '%s' "$INPUT" | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" CC_PERSISTENCE_STRICT=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "not found"; then
    assert_pass "missing file in strict mode triggers exit 2"
else
    assert_fail "expected exit 2 + not found, got rc=$rc output=$output"
fi
output=$(echo '{}' | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing session_id is silent (defensive default)"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi
SESSION_ID="test-session-7"
cat > "$TEST_DIR/projects/myproj/${SESSION_ID}.jsonl" << JSONL
{"type":"ai-title","sessionId":"test-session-7","aiTitle":"Title only"}
JSONL
INPUT=$(jq -nc --arg sid "$SESSION_ID" '{session_id: $sid}')
output=$(printf '%s' "$INPUT" | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" CC_PERSISTENCE_CHECK_DISABLE=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "disable flag short-circuits to silent exit"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi
SESSION_ID="test-session-8"
cat > "$TEST_DIR/projects/myproj/${SESSION_ID}.jsonl" << JSONL
{"type":"queue-operation","operation":"enqueue"}
{"type":"ai-title","sessionId":"test-session-8","aiTitle":"Queue only"}
JSONL
INPUT=$(jq -nc --arg sid "$SESSION_ID" '{session_id: $sid}')
output=$(printf '%s' "$INPUT" | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "queue-operation event is sufficient"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi
SESSION_ID="test-session-9"
cat > "$TEST_DIR/projects/myproj/${SESSION_ID}.jsonl" << JSONL
{"type":"user","message":{"role":"user","content":"hi"}}
{"type":"ai-title","sessionId":"test-session-9","aiTitle":"User only"}
JSONL
INPUT=$(jq -nc --arg sid "$SESSION_ID" '{session_id: $sid}')
output=$(printf '%s' "$INPUT" | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "user event is sufficient"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi
SESSION_ID="test-session-deep"
mkdir -p "$TEST_DIR/projects/deep/nested"
cat > "$TEST_DIR/projects/deep/nested/${SESSION_ID}.jsonl" << JSONL
{"type":"assistant","message":{"role":"assistant","content":"hi"}}
{"type":"ai-title","sessionId":"test-session-deep","aiTitle":"Deep"}
JSONL
INPUT=$(jq -nc --arg sid "$SESSION_ID" '{session_id: $sid}')
output=$(printf '%s' "$INPUT" | CC_PERSISTENCE_CHECK_DIR="$TEST_DIR/projects" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "deeply nested file is located and validated"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi
echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
