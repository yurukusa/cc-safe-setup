#!/bin/bash
# Test for sql-bulk-delete-warn.sh
#
# Verifies the hook warns on the high-risk SQL patterns documented in
# Issue #56738 and related cases, but stays silent on safe SQL.

set -u

HOOK="$(dirname "$0")/../examples/sql-bulk-delete-warn.sh"
[ ! -x "$HOOK" ] && chmod +x "$HOOK"

PASS=0
FAIL=0

run_case() {
    local name="$1"
    local cmd="$2"
    local expect_warn="$3"  # "yes" or "no"
    local strict="${4:-0}"

    local input
    input=$(jq -nc --arg cmd "$cmd" '{tool_input:{command:$cmd}}')
    local stderr
    if [ "$strict" = "1" ]; then
        stderr=$(echo "$input" | CC_SQL_BULK_DELETE_BLOCK=1 "$HOOK" 2>&1 >/dev/null)
        local rc=$?
    else
        stderr=$(echo "$input" | "$HOOK" 2>&1 >/dev/null)
        local rc=$?
    fi

    if [ "$expect_warn" = "yes" ]; then
        if [ -n "$stderr" ]; then
            PASS=$((PASS + 1))
            echo "PASS: $name"
        else
            FAIL=$((FAIL + 1))
            echo "FAIL: $name (expected warning, got none)"
        fi
        if [ "$strict" = "1" ]; then
            if [ "$rc" = "2" ]; then
                PASS=$((PASS + 1))
                echo "PASS: $name (strict mode, exit 2)"
            else
                FAIL=$((FAIL + 1))
                echo "FAIL: $name (strict mode, expected exit 2, got $rc)"
            fi
        fi
    else
        if [ -z "$stderr" ]; then
            PASS=$((PASS + 1))
            echo "PASS: $name"
        else
            FAIL=$((FAIL + 1))
            echo "FAIL: $name (expected silence, got: $stderr)"
        fi
    fi
}

# Issue #56738 pattern: DELETE WHERE col IS NULL after a populating UPDATE
run_case "Issue 56738: DELETE WHERE col IS NULL" \
    "psql -d mydb -c \"DELETE FROM manager_roles WHERE _clean_title IS NULL\"" \
    "yes"

# Strict mode: same pattern should exit 2
run_case "Issue 56738 strict mode" \
    "psql -d mydb -c \"DELETE FROM manager_roles WHERE _clean_title IS NULL\"" \
    "yes" \
    "1"

# DELETE without WHERE
run_case "DELETE without WHERE" \
    "mysql -e \"DELETE FROM users;\"" \
    "yes"

# UPDATE without WHERE
run_case "UPDATE without WHERE" \
    "psql -c \"UPDATE accounts SET balance = 0;\"" \
    "yes"

# TRUNCATE warning
run_case "TRUNCATE TABLE" \
    "psql -c \"TRUNCATE TABLE sessions;\"" \
    "yes"

# psql -c without explicit transaction
run_case "psql -c DELETE no BEGIN" \
    "psql -c \"DELETE FROM logs WHERE created_at < '2026-01-01'\"" \
    "yes"

# Safe: DELETE wrapped in BEGIN/ROLLBACK
run_case "DELETE wrapped in BEGIN ROLLBACK" \
    "psql -c \"BEGIN; DELETE FROM logs WHERE id = 5; ROLLBACK;\"" \
    "no"

# Safe: SELECT only
run_case "Pure SELECT" \
    "psql -c \"SELECT COUNT(*) FROM users;\"" \
    "no"

# Safe: non-SQL command
run_case "Non-SQL command" \
    "ls -la" \
    "no"

# Safe: psql to print version
run_case "psql --version" \
    "psql --version" \
    "no"

# DELETE with specific WHERE = (not full-table)
run_case "DELETE WHERE id = N" \
    "psql -c \"BEGIN; DELETE FROM users WHERE id = 42; COMMIT;\"" \
    "no"

# sqlite3 DELETE without WHERE
run_case "sqlite3 DELETE no WHERE" \
    "sqlite3 mydb.sqlite \"DELETE FROM messages;\"" \
    "yes"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
