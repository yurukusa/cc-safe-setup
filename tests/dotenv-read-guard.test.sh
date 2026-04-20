#!/bin/bash
# Tests for dotenv-read-guard.sh
HOOK="$(dirname "$0")/../examples/dotenv-read-guard.sh"
PASS=0; FAIL=0

run_test() {
    local desc="$1" input="$2" expect="$3"
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null; echo $?)
    code=$(echo "$result" | tail -1)
    if [ "$code" = "$expect" ]; then
        echo "PASS: $desc"
        ((PASS++))
    else
        echo "FAIL: $desc (expected $expect, got $code)"
        ((FAIL++))
    fi
}

# Should block .env files
run_test "Block .env" \
    '{"tool_input":{"file_path":"/home/user/project/.env"}}' "2"

run_test "Block .env.local" \
    '{"tool_input":{"file_path":"/app/.env.local"}}' "2"

run_test "Block .env.production" \
    '{"tool_input":{"file_path":"/deploy/.env.production"}}' "2"

run_test "Block .env.staging" \
    '{"tool_input":{"file_path":"/app/.env.staging"}}' "2"

run_test "Block .env.development" \
    '{"tool_input":{"file_path":"/app/.env.development"}}' "2"

run_test "Block .env.test" \
    '{"tool_input":{"file_path":"/project/.env.test"}}' "2"

# Should allow non-.env files
run_test "Allow .env.example" \
    '{"tool_input":{"file_path":"/project/.env.example"}}' "0"

run_test "Allow README.md" \
    '{"tool_input":{"file_path":"/project/README.md"}}' "0"

run_test "Allow package.json" \
    '{"tool_input":{"file_path":"/project/package.json"}}' "0"

run_test "Allow config.ts" \
    '{"tool_input":{"file_path":"/src/config.ts"}}' "0"

run_test "Allow env.ts (not dotenv)" \
    '{"tool_input":{"file_path":"/src/env.ts"}}' "0"

run_test "Allow .envrc (direnv)" \
    '{"tool_input":{"file_path":"/project/.envrc"}}' "0"

# Edge cases
run_test "Empty input" '{}' "0"

run_test "No file_path" \
    '{"tool_input":{}}' "0"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
