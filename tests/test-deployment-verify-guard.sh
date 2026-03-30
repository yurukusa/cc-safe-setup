#!/bin/bash
# Tests for deployment-verify-guard.sh
# Run: bash tests/test-deployment-verify-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/deployment-verify-guard.sh"

test_hook() {
    local input="$1" expected_exit="$2" desc="$3"
    local actual_exit=0
    echo "$input" | bash "$HOOK" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

# Test that deploy command produces "Deploy detected" on stderr
test_hook_stderr() {
    local input="$1" pattern="$2" desc="$3"
    local stderr
    stderr=$(echo "$input" | bash "$HOOK" 2>&1 >/dev/null) || true
    if echo "$stderr" | grep -qi "$pattern"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$pattern' on stderr, got: $stderr)"
        FAIL=$((FAIL + 1))
    fi
}

echo "deployment-verify-guard.sh tests"
echo ""

# --- All commands exit 0 (non-blocking) ---
test_hook '{"tool_input":{"command":"systemctl restart nginx"}}' 0 "deploy: systemctl restart exits 0"
test_hook '{"tool_input":{"command":"docker restart myapp"}}' 0 "deploy: docker restart exits 0"
test_hook '{"tool_input":{"command":"docker compose up -d"}}' 0 "deploy: docker compose up exits 0"
test_hook '{"tool_input":{"command":"kubectl apply -f deploy.yaml"}}' 0 "deploy: kubectl apply exits 0"
test_hook '{"tool_input":{"command":"terraform apply"}}' 0 "deploy: terraform apply exits 0"
test_hook '{"tool_input":{"command":"fly deploy"}}' 0 "deploy: fly deploy exits 0"
test_hook '{"tool_input":{"command":"heroku container:push web"}}' 0 "deploy: heroku push exits 0"

# --- Verification commands exit 0 ---
test_hook '{"tool_input":{"command":"curl http://localhost:3000/health"}}' 0 "verify: curl exits 0"
test_hook '{"tool_input":{"command":"npm test"}}' 0 "verify: npm test exits 0"
test_hook '{"tool_input":{"command":"pytest tests/"}}' 0 "verify: pytest exits 0"
test_hook '{"tool_input":{"command":"docker logs myapp | tail"}}' 0 "verify: docker logs exits 0"
test_hook '{"tool_input":{"command":"journalctl -u nginx --since 5min"}}' 0 "verify: journalctl exits 0"

# --- Non-deploy non-verify commands ---
test_hook '{"tool_input":{"command":"ls -la"}}' 0 "unrelated command exits 0"
test_hook '{"tool_input":{"command":"git commit -m fix"}}' 0 "commit without deploy exits 0"

# --- Edge cases ---
test_hook '{"tool_input":{"command":"echo deploy"}}' 0 "echo deploy not tracked (echo skipped)"
test_hook '{"tool_input":{"command":""}}' 0 "empty command passes"
test_hook '{}' 0 "empty input passes"

# --- Deploy detection stderr message ---
test_hook_stderr \
    '{"tool_input":{"command":"systemctl restart nginx"}}' \
    "deploy detected" \
    "deploy command emits detection message on stderr"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed!"
