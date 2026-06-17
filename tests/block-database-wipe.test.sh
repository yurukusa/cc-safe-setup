#!/bin/bash
# Test for block-database-wipe.sh
#
# Verifies the hook blocks (exit 2) destructive framework/ORM database commands
# across Laravel, Django, Rails, Prisma, TypeORM/Sequelize, raw SQL and PostgreSQL,
# while letting safe incremental commands through (exit 0).
#
# Gaps closed in Issue #69059: migrate:refresh, Django "migrate <app> zero",
# Rails db:schema:load, TypeORM/Sequelize schema:drop / db:drop.

set -u

HOOK="$(dirname "$0")/../examples/block-database-wipe.sh"
[ ! -x "$HOOK" ] && chmod +x "$HOOK"

PASS=0
FAIL=0

run_case() {
    local name="$1"
    local cmd="$2"
    local expect="$3"  # "block" or "allow"

    local input rc
    input=$(jq -nc --arg cmd "$cmd" '{tool_input:{command:$cmd}}')
    echo "$input" | "$HOOK" >/dev/null 2>&1
    rc=$?

    if [ "$expect" = "block" ]; then
        if [ "$rc" = "2" ]; then PASS=$((PASS + 1)); echo "PASS: $name"
        else FAIL=$((FAIL + 1)); echo "FAIL: $name (expected block/exit2, got $rc)"; fi
    else
        if [ "$rc" = "0" ]; then PASS=$((PASS + 1)); echo "PASS: $name"
        else FAIL=$((FAIL + 1)); echo "FAIL: $name (expected allow/exit0, got $rc)"; fi
    fi
}

# --- destructive: must block ---
run_case "laravel migrate:fresh"      "php artisan migrate:fresh"            block
run_case "laravel migrate:refresh"    "php artisan migrate:refresh"         block
run_case "laravel migrate:reset"      "php artisan migrate:reset"           block
run_case "laravel db:wipe"            "php artisan db:wipe"                  block
run_case "django flush"               "python manage.py flush"              block
run_case "django migrate app zero"    "python manage.py migrate myapp zero" block
run_case "rails db:drop"              "rails db:drop"                       block
run_case "rails db:schema:load"       "rails db:schema:load"                block
run_case "prisma migrate reset"       "npx prisma migrate reset"            block
run_case "typeorm schema:drop"        "npm run typeorm schema:drop"         block
run_case "sequelize db:drop"          "npx sequelize-cli db:drop"           block
run_case "raw DROP DATABASE"          "mysql -e 'DROP DATABASE foo'"        block
run_case "dropdb"                     "dropdb mydb"                         block

# --- safe: must allow (no false positives) ---
run_case "laravel migrate (incremental)" "php artisan migrate"             allow
run_case "django migrate (incremental)"  "python manage.py migrate"        allow
run_case "rails db:migrate"              "rails db:migrate"                 allow
run_case "prisma migrate dev"           "npx prisma migrate dev"           allow
run_case "typeorm migration:run"        "npm run typeorm migration:run"    allow
run_case "plain git commit"             "git commit -m fix"                allow
run_case "safe SELECT"                  "psql -c 'SELECT count(*) FROM users'" allow

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
