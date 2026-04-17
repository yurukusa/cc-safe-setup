#!/bin/bash
# Tests for move-delete-sequence-guard.sh
# Run: bash tests/test-move-delete-sequence-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/move-delete-sequence-guard.sh"

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

echo "move-delete-sequence-guard.sh tests"
echo ""

# --- Block: mv + rm -rf on parent directory (#49129 pattern) ---
test_hook '{"tool_input":{"command":"mv /home/user/project/important.txt /tmp/ && rm -rf /home/user/project"}}' 2 "Block mv file then rm -rf parent (&&)"
test_hook '{"tool_input":{"command":"mv /home/user/project/src/main.py /tmp/backup/ ; rm -rf /home/user/project/src"}}' 2 "Block mv file then rm -rf parent (;)"
test_hook '{"tool_input":{"command":"mv /data/app/config.yml /tmp/ || rm -rf /data/app"}}' 2 "Block mv file then rm -rf parent (||)"

# --- Block: mv + rm -rf on same path ---
test_hook '{"tool_input":{"command":"mv /home/user/mydir /tmp/backup && rm -rf /home/user/mydir"}}' 2 "Block mv dir then rm -rf same dir"

# --- Block: mv + rm -rf on ancestor directory ---
test_hook '{"tool_input":{"command":"mv /home/user/project/src/lib/util.py /tmp/ && rm -rf /home/user/project"}}' 2 "Block mv file then rm -rf ancestor"
test_hook '{"tool_input":{"command":"mv /var/data/app/logs/today.log /tmp/ ; rm -rf /var/data"}}' 2 "Block mv file then rm -rf distant ancestor"

# --- Allow: mv and rm on unrelated paths ---
test_hook '{"tool_input":{"command":"mv /tmp/old.txt /tmp/new.txt && rm /var/log/app.log"}}' 0 "Allow mv and rm on unrelated paths"
test_hook '{"tool_input":{"command":"mv file.txt backup/ && rm other_file.txt"}}' 0 "Allow mv and rm on different files"

# --- Allow: mv only (no rm) ---
test_hook '{"tool_input":{"command":"mv /home/user/file.txt /tmp/"}}' 0 "Allow mv without rm"

# --- Allow: rm only (no mv) ---
test_hook '{"tool_input":{"command":"rm -rf /tmp/junk"}}' 0 "Allow rm without mv"

# --- Allow: Empty/missing input ---
test_hook '{}' 0 "Allow empty input"
test_hook '{"tool_input":{}}' 0 "Allow missing command"
test_hook '{"tool_input":{"command":""}}' 0 "Allow empty command"

# --- Allow: Safe operations ---
test_hook '{"tool_input":{"command":"ls -la && echo done"}}' 0 "Allow non-destructive compound command"
test_hook '{"tool_input":{"command":"git mv old.txt new.txt"}}' 0 "Allow git mv (no rm)"

# --- Block: Real-world attack patterns ---
test_hook '{"tool_input":{"command":"mv /home/user/projects/webapp/src/index.js /tmp/safe/ && rm -rf /home/user/projects/webapp/src"}}' 2 "Block real-world: save one file, delete rest of src"
test_hook '{"tool_input":{"command":"mv /home/user/data/important.db /tmp/ ; rm -r /home/user/data"}}' 2 "Block real-world: save DB, delete data dir"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
