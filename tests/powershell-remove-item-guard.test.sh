#!/bin/bash
# Tests for powershell-remove-item-guard.sh
# Run: bash tests/powershell-remove-item-guard.test.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/powershell-remove-item-guard.sh"

# The verdict is the exit code, not the text. A refusal that only prints a word
# Claude Code does not act on is not a refusal: until 2026-09-19 this file checked
# for the string '"decision":"DENY"' in stdout, and passed all nine block cases
# while the guard refused none of them. One of the nine (C:\Users) was measured
# end to end against a do-nothing control; the other eight leave through the same
# two lines.
test_hook() {
    local input="$1" expected="$2" desc="$3"
    local out err exit_code=0
    err=$(mktemp)
    out=$(echo "$input" | bash "$HOOK" 2>"$err") || exit_code=$?
    local stderr_text
    stderr_text=$(cat "$err"); rm -f "$err"

    if [ "$expected" = "DENY" ]; then
        # exit 2 is what actually stops the tool call; the reason must reach stderr.
        if [ "$exit_code" -eq 2 ] && echo "$stderr_text" | grep -q 'BLOCKED'; then
            echo "  PASS: $desc"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $desc (expected exit 2 + BLOCKED on stderr, got exit $exit_code, stdout: $out, stderr: $stderr_text)"
            FAIL=$((FAIL + 1))
        fi
    elif [ "$expected" = "ASK" ]; then
        if [ "$exit_code" -eq 0 ] && echo "$out" | grep -q '"permissionDecision":"ask"'; then
            echo "  PASS: $desc"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $desc (expected exit 0 + ask, got exit $exit_code, stdout: $out)"
            FAIL=$((FAIL + 1))
        fi
    else
        if [ "$exit_code" -eq 0 ] && ! echo "$out" | grep -q '"permissionDecision":"ask"'; then
            echo "  PASS: $desc"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $desc (expected exit 0 and no verdict, got exit $exit_code, stdout: $out)"
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

# --- Should ASK: -Recurse -Force on an ordinary absolute data path (#64310) ---
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force D:\\Clientes\\Yandy\\ENTREGABLES"}}' ASK "Confirm Remove-Item -Force on D:\\ client data (#64310)"
test_hook '{"tool_input":{"command":"Remove-Item -Force -Recurse E:\\work\\deliverables"}}' ASK "Confirm regardless of flag order on E:\\"
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force \\\\nas\\share\\projects"}}' ASK "Confirm on UNC path"

# --- Should ALLOW: safe commands ---
test_hook '{"tool_input":{"command":"Remove-Item ./temp.txt"}}' ALLOW "Allow single file deletion"
test_hook '{"tool_input":{"command":"ls -la"}}' ALLOW "Allow non-Remove-Item command"
test_hook '{"tool_input":{"command":"rm -rf ./build"}}' ALLOW "Allow bash rm (different hook)"
test_hook '{"tool_input":{"command":"Get-ChildItem -Recurse"}}' ALLOW "Allow Get-ChildItem (read-only)"
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force ./dist"}}' ALLOW "Allow relative force-delete (no absolute path)"
test_hook '{"tool_input":{"command":"Remove-Item -Recurse -Force .\\build\\out"}}' ALLOW "Allow relative Windows force-delete"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
