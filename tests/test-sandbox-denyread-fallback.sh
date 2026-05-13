#!/bin/bash
# Tests for sandbox-denyread-fallback.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/sandbox-denyread-fallback.sh"
PASS=0
FAIL=0

mk_input() {
    local tool="$1"
    local file="$2"
    printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$file"
}

run_hook() {
    local input="$1"
    local patterns="$2"
    RUN_OUTPUT=$(printf '%s' "$input" | CC_SANDBOX_DENYREAD_PATTERNS="$patterns" bash "$HOOK" 2>&1)
    RC=$?
}

assert_pass() {
    if [ "$RC" -eq 0 ]; then
        echo "  PASS: $1"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $1 (rc=$RC)"
        FAIL=$((FAIL + 1))
    fi
}

assert_block() {
    if [ "$RC" -eq 2 ]; then
        echo "  PASS: $1"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $1 (rc=$RC, expected 2, output=$RUN_OUTPUT)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== sandbox-denyread-fallback.sh tests ==="

# --- T1: Block .env.local with **/.env* pattern ---
run_hook "$(mk_input Read /home/x/proj/.env.local)" "**/.env*"
assert_block ".env.local blocked by **/.env*"

# --- T2: Block .env at repo root with **/.env* pattern ---
run_hook "$(mk_input Read .env)" "**/.env*"
assert_block ".env (bare) blocked by **/.env*"

# --- T3: Allow .env.example (not matched by **/.env* because .env.example matches too, but the user owns the pattern) ---
# Actually **/.env* DOES match .env.example since * matches anything-non-slash.
# For the dotenv-read-guard the .env.example is allowed, but here we just enforce user's pattern verbatim.
run_hook "$(mk_input Read /home/x/proj/.env.example)" "**/.env*"
assert_block ".env.example also matches **/.env* (user owns the pattern)"

# --- T4: README.md not blocked by **/.env* ---
run_hook "$(mk_input Read /home/x/proj/README.md)" "**/.env*"
assert_pass "README.md not blocked by **/.env*"

# --- T5: .pem file blocked by **/*.pem ---
run_hook "$(mk_input Read /home/x/cert/server.pem)" "**/*.pem"
assert_block "server.pem blocked by **/*.pem"

# --- T6: .key file blocked by **/*.key ---
run_hook "$(mk_input Read /home/x/private/id_rsa.key)" "**/*.key"
assert_block "id_rsa.key blocked by **/*.key"

# --- T7: credentials.json blocked ---
run_hook "$(mk_input Read /home/x/proj/credentials.json)" "**/credentials.json"
assert_block "credentials.json blocked by **/credentials.json"

# --- T8: file under .aws blocked by **/.aws/** ---
run_hook "$(mk_input Read /home/x/.aws/credentials)" "**/.aws/**"
assert_block ".aws/credentials blocked by **/.aws/**"

# --- T9: secrets/ subdirectory blocked ---
run_hook "$(mk_input Read /home/x/proj/secrets/db.json)" "**/secrets/**"
assert_block "secrets/db.json blocked by **/secrets/**"

# --- T10: Multiple patterns; second pattern matches ---
patterns=$'**/*.txt\n**/.env*'
run_hook "$(mk_input Read /home/x/proj/.env.production)" "$patterns"
assert_block "second pattern in list matches"

# --- T11: Write tool is not blocked (only Read is guarded) ---
run_hook "$(mk_input Write /home/x/proj/.env.local)" "**/.env*"
assert_pass "Write tool is not blocked by this hook"

# --- T12: Bash tool is not blocked (different attack surface) ---
run_hook "$(mk_input Bash /home/x/proj/.env.local)" "**/.env*"
assert_pass "Bash tool is not blocked by this hook"

# --- T13: No patterns configured → allow all ---
run_hook "$(mk_input Read /home/x/proj/.env.local)" ""
assert_pass "no patterns configured = allow"

# --- T14: Empty file_path → allow (no target to check) ---
input='{"tool_name":"Read","tool_input":{"file_path":""}}'
run_hook "$input" "**/.env*"
assert_pass "empty file_path allowed"

# --- T15: Relative path matched against pattern ---
run_hook "$(mk_input Read ./.env.local)" "**/.env*"
assert_block "relative ./.env.local blocked"

# --- T16: Bare filename matched against pattern (no slashes) ---
run_hook "$(mk_input Read .env)" "**/.env*"
assert_block "bare .env blocked"

# --- T17: Block message names the matched pattern ---
run_hook "$(mk_input Read /home/x/proj/.env.local)" "**/.env*"
if echo "$RUN_OUTPUT" | grep -q "\*\*/.env\*"; then
    echo "  PASS: block message names the pattern"
    PASS=$((PASS + 1))
else
    echo "  FAIL: block message should name the pattern (output=$RUN_OUTPUT)"
    FAIL=$((FAIL + 1))
fi

# --- T18: Block message references the upstream issue ---
run_hook "$(mk_input Read /home/x/proj/.env.local)" "**/.env*"
if echo "$RUN_OUTPUT" | grep -q "#58636"; then
    echo "  PASS: block message references #58636"
    PASS=$((PASS + 1))
else
    echo "  FAIL: block message should reference #58636"
    FAIL=$((FAIL + 1))
fi

# --- T19: private_key* pattern (no double-star prefix) ---
run_hook "$(mk_input Read /home/x/private_key.pem)" "**/private_key*"
assert_block "private_key.pem blocked by **/private_key*"

# --- T20: service-account-*.json pattern ---
run_hook "$(mk_input Read /home/x/proj/service-account-prod.json)" "**/service-account-*.json"
assert_block "service-account-prod.json blocked by **/service-account-*.json"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
