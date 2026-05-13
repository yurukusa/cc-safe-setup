#!/bin/bash
# test-code-freeze-respect-guard.sh — Tests for code-freeze-respect-guard.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../examples/code-freeze-respect-guard.sh"
PASS=0
FAIL=0

run_test() {
    local name="$1"
    local input="$2"
    local expected_exit="$3"
    local setup="$4"
    local cleanup="$5"

    # Create test workspace
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"

    # Reset env vars that may leak across tests
    unset CFRG_ALLOW

    # Run setup if provided
    if [ -n "$setup" ]; then
        eval "$setup"
    fi

    # Run hook (preserve stderr for debugging)
    actual_exit=0
    HOOK_STDERR=$(echo "$input" | bash "$HOOK" 2>&1 >/dev/null) || actual_exit=$?

    # Cleanup
    cd /
    rm -rf "$TEST_DIR"

    if [ "$actual_exit" = "$expected_exit" ]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected exit $expected_exit, got $actual_exit)"
        [ -n "$HOOK_STDERR" ] && echo "  STDERR: $HOOK_STDERR" | head -3
        FAIL=$((FAIL + 1))
    fi
}

# Test 1: No freeze + destructive command = allow
run_test "no freeze + rm -rf = allow" \
    '{"tool_input":{"command":"rm -rf /tmp/foo"}}' \
    0 \
    ""

# Test 2: No freeze + non-destructive = allow
run_test "no freeze + ls = allow" \
    '{"tool_input":{"command":"ls -la"}}' \
    0 \
    ""

# Test 3: Freeze in CLAUDE.md + destructive rm = block
run_test "freeze + rm -rf = block" \
    '{"tool_input":{"command":"rm -rf /var/lib/postgres"}}' \
    2 \
    "echo 'This project is in code freeze until next week' > CLAUDE.md"

# Test 4: Freeze + non-destructive = allow
run_test "freeze + ls = allow" \
    '{"tool_input":{"command":"ls -la"}}' \
    0 \
    "echo 'code freeze in effect' > CLAUDE.md"

# Test 5: Freeze in FREEZE.md + DROP DATABASE = block
run_test "freeze + DROP DATABASE = block" \
    '{"tool_input":{"command":"psql -c \"DROP DATABASE production\""}}' \
    2 \
    "echo 'deployment freeze active' > FREEZE.md"

# Test 6: Freeze + git reset --hard = block
run_test "freeze + git reset --hard = block" \
    '{"tool_input":{"command":"git reset --hard HEAD~5"}}' \
    2 \
    "echo 'do not deploy this week' > CLAUDE.md"

# Test 7: Freeze + railway volume delete = block
run_test "freeze + railway destructive = block" \
    '{"tool_input":{"command":"railway volume delete prod-db"}}' \
    2 \
    "echo 'code freeze' > CLAUDE.md"

# Test 8: Freeze + aws s3 rm = block
run_test "freeze + aws s3 rm = block" \
    '{"tool_input":{"command":"aws s3 rm s3://prod-bucket --recursive"}}' \
    2 \
    "echo 'do not destroy' > CLAUDE.md"

# Test 9: Freeze + kubectl delete pvc = block
run_test "freeze + kubectl destructive = block" \
    '{"tool_input":{"command":"kubectl delete pvc prod-data-volume"}}' \
    2 \
    "echo 'hold all destructive ops' > CLAUDE.md"

# Test 10: Freeze + git push --force = block
run_test "freeze + git push --force = block" \
    '{"tool_input":{"command":"git push --force origin main"}}' \
    2 \
    "echo 'code freeze in progress' > CLAUDE.md"

# Test 11: Freeze in Japanese (凍結) + rm -rf = block
run_test "Japanese freeze + rm -rf = block" \
    '{"tool_input":{"command":"rm -rf /var/data"}}' \
    2 \
    "echo '本番 停止 中 今週は変更を入れない' > CLAUDE.md"

# Test 12: Freeze + CFRG_ALLOW=1 = allow (override)
run_test "freeze + rm -rf + CFRG_ALLOW=1 = allow" \
    '{"tool_input":{"command":"rm -rf /tmp/foo"}}' \
    0 \
    "echo 'code freeze' > CLAUDE.md; export CFRG_ALLOW=1"

# Test 13: Empty command = no-op
run_test "empty command = allow" \
    '{"tool_input":{"command":""}}' \
    0 \
    "echo 'code freeze' > CLAUDE.md"

# Test 14: Freeze + vercel deploy = block
run_test "freeze + vercel deploy = block" \
    '{"tool_input":{"command":"vercel deploy --prod"}}' \
    2 \
    "echo 'deployment freeze' > CLAUDE.md"

# Test 15: Freeze + terraform apply = block
run_test "freeze + terraform apply = block" \
    '{"tool_input":{"command":"terraform apply -auto-approve"}}' \
    2 \
    "echo 'do not deploy' > CLAUDE.md"

# Test 16: README.md with freeze + rm -rf = block
run_test "README.md freeze + rm -rf = block" \
    '{"tool_input":{"command":"rm -rf /tmp/foo"}}' \
    2 \
    "mkdir -p sub && echo 'CODE FREEZE: see this until Monday' > README.md"

# Test 17: .freeze file exists + rm -rf = block
run_test ".freeze file + rm -rf = block" \
    '{"tool_input":{"command":"rm -rf /tmp/foo"}}' \
    2 \
    "echo 'code freeze in effect' > .freeze"

# Test 18: No CLAUDE.md, no FREEZE.md = allow
run_test "no freeze files + destructive = allow" \
    '{"tool_input":{"command":"rm -rf /tmp/foo"}}' \
    0 \
    ""

# Test 19: CLAUDE.md exists but no freeze keyword + destructive = allow
run_test "CLAUDE.md without freeze keyword + rm = allow" \
    '{"tool_input":{"command":"rm -rf /tmp/foo"}}' \
    0 \
    "echo 'normal project docs here' > CLAUDE.md"

# Test 20: Freeze + TRUNCATE TABLE = block
run_test "freeze + TRUNCATE = block" \
    '{"tool_input":{"command":"psql -c \"TRUNCATE TABLE users\""}}' \
    2 \
    "echo 'code freeze' > CLAUDE.md"

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
