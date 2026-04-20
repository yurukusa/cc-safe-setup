#!/bin/bash
# Tests for powershell-remove-item-guard.sh
# Run: bash tests/powershell-remove-item-guard.test.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/powershell-remove-item-guard.sh"

test_hook() {
    local input="$1" expected="$2" desc="$3"
    local output exit_code=0
    output=$(echo "$input" | bash "$HOOK" 2>/dev/null) || exit_code=$?
    if [ "$expected" = "DENY" ]; then
        if echo "$output" | grep -q '"decision":"DENY"'; then
            echo "  PASS: $desc"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $desc (expected DENY, got: $output)"
            FAIL=$((FAIL + 1))
        fi
    else
        if [ -z "$output" ] || ! echo "$output" | grep -q '"decision":"DENY"'; then
            echo "  PASS: $desc"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $desc (expected ALLOW, got DENY)"
            FAIL=$((FAIL + 1))
        fi
    fi
}

echo "powershell-remove-item-guard.sh tests"
echo ""

# --- Should DENY: system directory targets ---
test_hook '{"tool_input":{"command":"powershell -c \"Remove-Item -Recurse -Force C:\\Users\\john\""}}' DENY "Block Remove-Item on C:\\Users"
test_hook '{"tool_input":{"command":"powershell Remove-Item -Recurse /mnt/c/Windows"}}' DENY "Block Remove-Item on /mnt/c/Windows"
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force \"C:\\Program Files\\app\""}}' DENY "Block Remove-Item on Program Files"

# --- Should DENY: node_modules junction traversal ---
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force ./node_modules"}}' DENY "Block Remove-Item -Force on node_modules"
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force .pnpm/store"}}' DENY "Block Remove-Item on .pnpm"
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force worktree/packages"}}' DENY "Block Remove-Item on worktree"

# --- Should DENY: home directory ---
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force $HOME/Documents"}}' DENY "Block Remove-Item on \$HOME"
test_hook '{"tool_input":{"command":"Remove-Item -Recurse $env:USERPROFILE"}}' DENY "Block Remove-Item on USERPROFILE"
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force ~/projects"}}' DENY "Block Remove-Item on ~/"

# --- Should ALLOW: safe commands ---
test_hook '{"tool_input":{"command":"Remove-Item ./temp.txt"}}' ALLOW "Allow single file deletion"
test_hook '{"tool_input":{"command":"ls -la"}}' ALLOW "Allow non-Remove-Item command"
test_hook '{"tool_input":{"command":"rm -rf ./build"}}' ALLOW "Allow bash rm (different hook)"
test_hook '{"tool_input":{"command":"Get-ChildItem -Recurse"}}' ALLOW "Allow Get-ChildItem (read-only)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
