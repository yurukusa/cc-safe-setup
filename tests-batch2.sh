#!/bin/bash
# cc-safe-setup edge case tests — batch 2
# 24 hooks × 2-3 new tests each
# Run: bash tests-batch2.sh
# Requires: test.sh has been sourced or EXDIR/test_ex are defined

set -euo pipefail

PASS=0
FAIL=0
EXDIR="$(dirname "$0")/examples"

test_ex() {
    local script="$1" input="$2" expected_exit="$3" desc="$4"
    local actual_exit=0
    echo "$input" | bash "$EXDIR/$script" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "cc-safe-setup batch 2 edge case tests"
echo "======================================"
echo ""

# --- dependency-audit ---
echo "dependency-audit.sh:"
test_ex dependency-audit.sh '{"tool_input":{"command":"npm install"}}' 0 "dependency-audit: bare npm install (no pkg) passes"
test_ex dependency-audit.sh '{"tool_input":{"command":"npm install -D typescript"}}' 0 "dependency-audit: devDependency flag passes (exit 0)"
test_ex dependency-audit.sh '{"tool_input":{"command":"cargo add serde"}}' 0 "dependency-audit: cargo add without Cargo.toml passes (exit 0)"
test_ex dependency-audit.sh '{"tool_input":{"command":"pip install -r requirements.txt"}}' 0 "dependency-audit: pip -r requirements.txt skipped"
test_ex dependency-audit.sh '{"tool_input":{"command":"python3 -m pip install flask"}}' 0 "dependency-audit: python3 -m pip install passes (exit 0)"
echo ""

# --- diff-size-guard ---
echo "diff-size-guard.sh:"
test_ex diff-size-guard.sh '{"tool_input":{"command":"git add src/file.js"}}' 0 "diff-size-guard: git add single file passes"
test_ex diff-size-guard.sh '{"tool_input":{"command":"git add -A"}}' 0 "diff-size-guard: git add -A triggers check (exit 0 if under limit)"
test_ex diff-size-guard.sh '{"tool_input":{"command":"git add --all"}}' 0 "diff-size-guard: git add --all triggers check"
test_ex diff-size-guard.sh '{"tool_input":{"command":"git add ."}}' 0 "diff-size-guard: git add . triggers check"
test_ex diff-size-guard.sh '{"tool_input":{"command":"git status"}}' 0 "diff-size-guard: git status not checked"
test_ex diff-size-guard.sh '{"tool_input":{"command":"git diff HEAD"}}' 0 "diff-size-guard: git diff ignored"
echo ""

# --- disk-space-guard ---
echo "disk-space-guard.sh:"
test_ex disk-space-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"big.bin","content":"data"}}' 0 "disk-space-guard: Write tool triggers check (exit 0)"
test_ex disk-space-guard.sh '{"tool_name":"Bash","tool_input":{"command":"dd if=/dev/zero of=file bs=1M count=100"}}' 0 "disk-space-guard: large write command passes (exit 0)"
test_ex disk-space-guard.sh '{}' 0 "disk-space-guard: empty input passes"
echo ""

# --- dotenv-validate ---
echo "dotenv-validate.sh:"
test_ex dotenv-validate.sh '{"tool_input":{"file_path":"/tmp/test-batch2.env.local"}}' 0 "dotenv-validate: .env.local pattern matches but nonexistent"
test_ex dotenv-validate.sh '{"tool_input":{"file_path":"/tmp/test-batch2.env.production"}}' 0 "dotenv-validate: .env.production pattern matches"
test_ex dotenv-validate.sh '{"tool_input":{"file_path":"config.yaml"}}' 0 "dotenv-validate: non-env extension skipped"
echo ""

# --- edit-verify ---
echo "edit-verify.sh:"
# PostToolUse hook — checks file state after edit
echo "test content for edit-verify" > /tmp/cc-test-edit-verify.txt
test_ex edit-verify.sh '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/cc-test-edit-verify.txt","new_string":"test content for edit-verify"}}' 0 "edit-verify: new_string found in file (no warning)"
test_ex edit-verify.sh '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/cc-test-edit-verify.txt","new_string":"TOTALLY_NONEXISTENT_STRING_XYZ"}}' 0 "edit-verify: new_string NOT found in file warns but passes"
test_ex edit-verify.sh '{"tool_name":"Read","tool_input":{"file_path":"/tmp/cc-test-edit-verify.txt"}}' 0 "edit-verify: non-Edit/Write tool skipped"
# Test merge conflict marker detection
echo -e "<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch" > /tmp/cc-test-edit-conflict.txt
test_ex edit-verify.sh '{"tool_name":"Write","tool_input":{"file_path":"/tmp/cc-test-edit-conflict.txt"}}' 0 "edit-verify: conflict markers in file warns but passes"
# Test suspiciously small file
echo -n "ab" > /tmp/cc-test-edit-tiny.js
test_ex edit-verify.sh '{"tool_name":"Write","tool_input":{"file_path":"/tmp/cc-test-edit-tiny.js"}}' 0 "edit-verify: tiny .js file warns but passes"
# Config file exception for small size
echo -n "{}" > /tmp/cc-test-edit-tiny.json
test_ex edit-verify.sh '{"tool_name":"Write","tool_input":{"file_path":"/tmp/cc-test-edit-tiny.json"}}' 0 "edit-verify: tiny .json file no small-size warning"
rm -f /tmp/cc-test-edit-verify.txt /tmp/cc-test-edit-conflict.txt /tmp/cc-test-edit-tiny.js /tmp/cc-test-edit-tiny.json
echo ""

# --- env-required-check ---
echo "env-required-check.sh:"
test_ex env-required-check.sh '{"tool_input":{"content":"process.env.SECRET_KEY!"}}' 0 "env-required-check: content field with ! accessor warns (exit 0)"
test_ex env-required-check.sh '{"tool_input":{"new_string":"process.env.API_KEY || \"default\""}}' 0 "env-required-check: env with || fallback detected"
test_ex env-required-check.sh '{"tool_input":{"new_string":"process.env.NODE_ENV"}}' 0 "env-required-check: env without ! or || passes silently"
echo ""

# --- fact-check-gate ---
echo "fact-check-gate.sh:"
rm -f /tmp/cc-fact-check-reads-*
test_ex fact-check-gate.sh '{"tool_input":{"file_path":"docs/guide.md","new_string":"See `utils.ts` and `server.py` for implementation"}}' 0 "fact-check-gate: doc referencing multiple source files warns (exit 0)"
test_ex fact-check-gate.sh '{"tool_input":{"file_path":"CONTRIBUTING.md","new_string":"Run `main.go` to start"}}' 0 "fact-check-gate: CONTRIBUTING referencing source warns (exit 0)"
test_ex fact-check-gate.sh '{"tool_input":{"file_path":"README.md","new_string":"This project is awesome"}}' 0 "fact-check-gate: doc without source refs passes silently"
test_ex fact-check-gate.sh '{"tool_input":{"file_path":"src/index.ts","new_string":"See `utils.ts`"}}' 0 "fact-check-gate: non-doc file skipped even with refs"
rm -f /tmp/cc-fact-check-reads-*
echo ""

# --- git-blame-context ---
echo "git-blame-context.sh:"
test_ex git-blame-context.sh '{"tool_input":{"file_path":"/tmp/nonexistent-xyz.js"}}' 0 "git-blame-context: nonexistent file skipped"
test_ex git-blame-context.sh '{"tool_input":{"file_path":"/tmp/test.js","old_string":"a"}}' 0 "git-blame-context: old_string < 10 lines skipped"
test_ex git-blame-context.sh '{"tool_input":{"file_path":"/tmp/test.js"}}' 0 "git-blame-context: no old_string skipped"
echo ""

# --- git-merge-conflict-prevent ---
echo "git-merge-conflict-prevent.sh:"
test_ex git-merge-conflict-prevent.sh '{"tool_input":{"command":"git merge --no-ff develop","new_string":"code"}}' 0 "git-merge-conflict-prevent: --no-ff merge warns (exit 0)"
test_ex git-merge-conflict-prevent.sh '{"tool_input":{"command":"git merge --squash feature","new_string":"x"}}' 0 "git-merge-conflict-prevent: --squash merge warns (exit 0)"
test_ex git-merge-conflict-prevent.sh '{"tool_input":{"command":"git rebase main","new_string":"code"}}' 0 "git-merge-conflict-prevent: rebase not matched (only merge)"
echo ""

# --- git-message-length ---
echo "git-message-length.sh:"
test_ex git-message-length.sh '{"tool_input":{"command":"git commit -m \"a\""}}' 0 "git-message-length: 1-char message warns (exit 0)"
test_ex git-message-length.sh '{"tool_input":{"command":"git commit -m \"exactly10c\""}}' 0 "git-message-length: exactly 10 chars boundary"
test_ex git-message-length.sh '{"tool_input":{"command":"git commit --amend"}}' 0 "git-message-length: commit without -m flag ignored"
echo ""

# --- hook-debug-wrapper ---
echo "hook-debug-wrapper.sh:"
# Test with nonexistent hook script
cp examples/hook-debug-wrapper.sh /tmp/test-hook-debug-wrap-b2.sh && chmod +x /tmp/test-hook-debug-wrap-b2.sh
export CC_HOOK_DEBUG_LOG="/tmp/test-hook-debug-b2.log"
rm -f "$CC_HOOK_DEBUG_LOG"
# Nonexistent inner script — should exit 0 with usage message
local_exit=0
echo '{}' | bash /tmp/test-hook-debug-wrap-b2.sh /tmp/nonexistent-hook-xyz.sh > /dev/null 2>/dev/null || local_exit=$?
if [ "$local_exit" -eq 0 ]; then
    echo "  PASS: hook-debug-wrapper: nonexistent inner script exits 0"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook-debug-wrapper: nonexistent inner script exits 0 (got $local_exit)"
    FAIL=$((FAIL + 1))
fi
# Test with inner script that produces stdout
echo '#!/bin/bash' > /tmp/test-debug-stdout-b2.sh
echo 'cat > /dev/null; echo "STDOUT_OUTPUT"' >> /tmp/test-debug-stdout-b2.sh
chmod +x /tmp/test-debug-stdout-b2.sh
local_exit=0
RESULT=$(echo '{"tool_input":{"command":"test"}}' | bash /tmp/test-hook-debug-wrap-b2.sh /tmp/test-debug-stdout-b2.sh 2>/dev/null) || local_exit=$?
if [ "$local_exit" -eq 0 ] && echo "$RESULT" | grep -q "STDOUT_OUTPUT"; then
    echo "  PASS: hook-debug-wrapper: passes through inner hook stdout"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook-debug-wrapper: passes through inner hook stdout (exit=$local_exit)"
    FAIL=$((FAIL + 1))
fi
# Test with inner script exit code 1 (not just 0 and 2)
echo '#!/bin/bash' > /tmp/test-debug-exit1-b2.sh
echo 'cat > /dev/null; exit 1' >> /tmp/test-debug-exit1-b2.sh
chmod +x /tmp/test-debug-exit1-b2.sh
local_exit=0
echo '{}' | bash /tmp/test-hook-debug-wrap-b2.sh /tmp/test-debug-exit1-b2.sh > /dev/null 2>/dev/null || local_exit=$?
if [ "$local_exit" -eq 1 ]; then
    echo "  PASS: hook-debug-wrapper: preserves exit code 1 from inner hook"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook-debug-wrapper: preserves exit code 1 (got $local_exit)"
    FAIL=$((FAIL + 1))
fi
rm -f /tmp/test-hook-debug-wrap-b2.sh /tmp/test-debug-stdout-b2.sh /tmp/test-debug-exit1-b2.sh "$CC_HOOK_DEBUG_LOG"
unset CC_HOOK_DEBUG_LOG
echo ""

# --- import-cycle-warn ---
echo "import-cycle-warn.sh:"
test_ex import-cycle-warn.sh '{"tool_input":{"file_path":"/tmp/test.py","new_string":"from .models import User"}}' 0 "import-cycle-warn: Python relative import checked (exit 0)"
test_ex import-cycle-warn.sh '{"tool_input":{"file_path":"/tmp/app.js","new_string":"const x = require(\"./utils\")"}}' 0 "import-cycle-warn: require relative import checked (exit 0)"
test_ex import-cycle-warn.sh '{"tool_input":{"file_path":"/tmp/app.js","new_string":"import React from \"react\""}}' 0 "import-cycle-warn: non-relative import skipped"
echo ""

# --- max-file-count-guard ---
echo "max-file-count-guard.sh:"
rm -f /tmp/cc-new-files-count
test_ex max-file-count-guard.sh '{"tool_input":{}}' 0 "max-file-count-guard: empty file_path skipped"
# Simulate approaching threshold
rm -f /tmp/cc-new-files-count
for i in $(seq 1 19); do echo "/tmp/file$i.js" >> /tmp/cc-new-files-count; done
test_ex max-file-count-guard.sh '{"tool_input":{"file_path":"/tmp/file20.js"}}' 0 "max-file-count-guard: 20th file triggers warning (exit 0)"
rm -f /tmp/cc-new-files-count
for i in $(seq 1 25); do echo "/tmp/file$i.js" >> /tmp/cc-new-files-count; done
test_ex max-file-count-guard.sh '{"tool_input":{"file_path":"/tmp/file26.js"}}' 0 "max-file-count-guard: 26th file warns (exit 0, never blocks)"
rm -f /tmp/cc-new-files-count
echo ""

# --- max-session-duration ---
echo "max-session-duration.sh:"
rm -f /tmp/cc-session-start-*
# First call creates state file
test_ex max-session-duration.sh '{}' 0 "max-session-duration: first call creates state (exit 0)"
# Simulate an old session by writing an old timestamp
STATE_FILE=$(ls /tmp/cc-session-start-* 2>/dev/null | head -1)
if [ -n "$STATE_FILE" ]; then
    # Write timestamp 5 hours ago
    echo $(( $(date +%s) - 18000 )) > "$STATE_FILE"
    test_ex max-session-duration.sh '{}' 0 "max-session-duration: 5h old session warns (exit 0, never blocks)"
    # Write timestamp 1 hour ago (under default 4h limit)
    echo $(( $(date +%s) - 3600 )) > "$STATE_FILE"
    test_ex max-session-duration.sh '{}' 0 "max-session-duration: 1h old session no warning"
fi
rm -f /tmp/cc-session-start-*
echo ""

# --- max-subagent-count ---
echo "max-subagent-count.sh:"
rm -f /tmp/cc-subagent-count
test_ex max-subagent-count.sh '{"tool_input":{"command":"echo first"}}' 0 "max-subagent-count: first command increments to 1"
# Simulate threshold by writing count
echo "5" > /tmp/cc-subagent-count
test_ex max-subagent-count.sh '{"tool_input":{"command":"echo sixth"}}' 0 "max-subagent-count: 6th call warns (exit 0, never blocks)"
echo "10" > /tmp/cc-subagent-count
test_ex max-subagent-count.sh '{"tool_input":{"command":"echo eleventh"}}' 0 "max-subagent-count: 11th call still exit 0"
rm -f /tmp/cc-subagent-count
echo ""

# --- memory-write-guard ---
echo "memory-write-guard.sh:"
test_ex memory-write-guard.sh '{"tool_input":{"file_path":"/home/user/.claude/settings.json"}}' 0 "memory-write-guard: settings.json warns (exit 0)"
test_ex memory-write-guard.sh '{"tool_input":{"file_path":"/home/user/.claude/settings.local.json"}}' 0 "memory-write-guard: settings.local.json warns (exit 0)"
test_ex memory-write-guard.sh '{"tool_input":{"file_path":"/home/user/.claude/projects/mem/MEMORY.md"}}' 0 "memory-write-guard: MEMORY.md in .claude warns (exit 0)"
test_ex memory-write-guard.sh '{"tool_input":{"file_path":"src/app.js"}}' 0 "memory-write-guard: normal path no warning"
echo ""

# --- no-absolute-import ---
echo "no-absolute-import.sh:"
test_ex no-absolute-import.sh '{"tool_input":{"new_string":"from \"./relative\" import x"}}' 0 "no-absolute-import: relative from passes silently"
test_ex no-absolute-import.sh '{"tool_input":{"content":"require(\"/absolute/module\")"}}' 0 "no-absolute-import: content field with absolute warns (exit 0)"
test_ex no-absolute-import.sh '{"tool_input":{"new_string":"from \"react\" import Component"}}' 0 "no-absolute-import: package import (no slash prefix) passes"
echo ""

# --- no-alert-confirm-prompt ---
echo "no-alert-confirm-prompt.sh:"
test_ex no-alert-confirm-prompt.sh '{"tool_input":{"new_string":"window.alert(\"msg\")"}}' 0 "no-alert-confirm-prompt: window.alert warns (exit 0)"
test_ex no-alert-confirm-prompt.sh '{"tool_input":{"new_string":"sweetalert(\"msg\")"}}' 0 "no-alert-confirm-prompt: sweetalert not matched (no word boundary)"
test_ex no-alert-confirm-prompt.sh '{"tool_input":{"new_string":"const alertMessage = \"hi\""}}' 0 "no-alert-confirm-prompt: alertMessage variable not matched (no parens)"
echo ""

# --- no-any-type ---
echo "no-any-type.sh:"
test_ex no-any-type.sh '{"tool_input":{"new_string":"const x: unknown = val"}}' 0 "no-any-type: unknown type passes (not any)"
test_ex no-any-type.sh '{"tool_input":{"new_string":"function f(x: any): void {}"}}' 0 "no-any-type: param typed any warns (exit 0)"
test_ex no-any-type.sh '{"tool_input":{"new_string":"// company name is Company"}}' 0 "no-any-type: word any in comment not matched (no colon prefix)"
test_ex no-any-type.sh '{"tool_input":{"content":"Record<string, any>"}}' 0 "no-any-type: content field with <any> warns (exit 0)"
echo ""

# --- no-infinite-scroll-mem ---
echo "no-infinite-scroll-mem.sh:"
# This hook always emits NOTE when content is non-empty
test_ex no-infinite-scroll-mem.sh '{"tool_input":{"new_string":"useVirtualizer({ count: items.length })"}}' 0 "no-infinite-scroll-mem: virtualized code still notes (exit 0)"
test_ex no-infinite-scroll-mem.sh '{"tool_input":{"content":"items.push(...newItems); setItems([...items])"}}' 0 "no-infinite-scroll-mem: array append pattern notes (exit 0)"
test_ex no-infinite-scroll-mem.sh '{"tool_input":{}}' 0 "no-infinite-scroll-mem: no content field passes silently"
echo ""

# --- no-inline-handler ---
echo "no-inline-handler.sh:"
# This hook always emits NOTE when content is non-empty
test_ex no-inline-handler.sh '{"tool_input":{"new_string":"addEventListener(\"click\", handler)"}}' 0 "no-inline-handler: addEventListener still notes (exit 0)"
test_ex no-inline-handler.sh '{"tool_input":{"content":"<form onSubmit={() => save()}>"}}' 0 "no-inline-handler: onSubmit inline notes (exit 0)"
test_ex no-inline-handler.sh '{"tool_input":{}}' 0 "no-inline-handler: no content passes silently"
echo ""

# --- no-long-switch ---
echo "no-long-switch.sh:"
# This hook always emits NOTE when content is non-empty
test_ex no-long-switch.sh '{"tool_input":{"new_string":"if (x === 1) {} else if (x === 2) {}"}}' 0 "no-long-switch: if-else chain still notes (exit 0)"
test_ex no-long-switch.sh '{"tool_input":{"content":"switch(action) { default: break; }"}}' 0 "no-long-switch: single-case switch notes (exit 0)"
test_ex no-long-switch.sh '{"tool_input":{}}' 0 "no-long-switch: no content passes silently"
echo ""

# --- no-memory-leak-interval ---
echo "no-memory-leak-interval.sh:"
# This hook always emits NOTE when content is non-empty
test_ex no-memory-leak-interval.sh '{"tool_input":{"new_string":"setTimeout(() => cleanup(), 1000)"}}' 0 "no-memory-leak-interval: setTimeout (not setInterval) still notes (exit 0)"
test_ex no-memory-leak-interval.sh '{"tool_input":{"content":"const id = setInterval(fn, 100); return () => clearInterval(id);"}}' 0 "no-memory-leak-interval: paired interval still notes (exit 0)"
test_ex no-memory-leak-interval.sh '{"tool_input":{}}' 0 "no-memory-leak-interval: no content passes silently"
echo ""

# --- no-mutation-observer-leak ---
echo "no-mutation-observer-leak.sh:"
# This hook always emits NOTE when content is non-empty
test_ex no-mutation-observer-leak.sh '{"tool_input":{"new_string":"observer.disconnect(); observer = null;"}}' 0 "no-mutation-observer-leak: disconnect call still notes (exit 0)"
test_ex no-mutation-observer-leak.sh '{"tool_input":{"content":"const ro = new ResizeObserver(cb)"}}' 0 "no-mutation-observer-leak: ResizeObserver (not MutationObserver) still notes (exit 0)"
test_ex no-mutation-observer-leak.sh '{"tool_input":{}}' 0 "no-mutation-observer-leak: no content passes silently"
echo ""

# --- Summary ---
echo "======================================"
echo "Batch 2 results: $PASS passed, $FAIL failed (total $((PASS + FAIL)))"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
