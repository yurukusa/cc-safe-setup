#!/usr/bin/env bash
# Tests for attachment-traversal-guard.sh
# Covers the anthropics/claude-code#61148 @../ bypass cases plus
# edge cases for the deny-rule synonymous edge.

set -e

HOOK="$(cd "$(dirname "$0")/../examples" && pwd)/attachment-traversal-guard.sh"
test -x "$HOOK" || chmod +x "$HOOK"

PASS=0
FAIL=0

run_test() {
  local name="$1"
  local prompt="$2"
  local expected_exit="$3"
  local env_vars="${4:-}"

  local payload
  payload=$(jq -nc --arg p "$prompt" '{prompt: $p}')

  local actual_exit
  if [ -n "$env_vars" ]; then
    actual_exit=$(env $env_vars bash -c "echo '$payload' | '$HOOK' >/dev/null 2>&1; echo \$?")
  else
    actual_exit=$(echo "$payload" | "$HOOK" >/dev/null 2>&1; echo $?)
  fi

  if [ "$actual_exit" = "$expected_exit" ]; then
    PASS=$((PASS + 1))
    echo "PASS: $name (exit $actual_exit)"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (expected $expected_exit, got $actual_exit)"
    echo "      prompt: $prompt"
    echo "      env: $env_vars"
  fi
}

# === Block cases (exit 2) ===

# Case 1: canonical reproduction from #61148
run_test "Forward-slash @../ blocks" \
  'Read @../Library/Security/KeyIV.cs' \
  '2'

# Case 2: Windows-style backslash variant
run_test "Backslash @..\\ blocks" \
  'Read @..\Library\Security\KeyIV.cs' \
  '2'

# Case 3: @../ at end of prompt
run_test "@../ at prompt end blocks" \
  'Please read this: @../secret.env' \
  '2'

# Case 4: nested traversal
run_test "@../../../ deep traversal blocks" \
  'Read @../../../etc/passwd' \
  '2'

# Case 5: with text before and after
run_test "@../ with surrounding text blocks" \
  'Compare @./current.txt with @../parent/old.txt please' \
  '2'

# Case 6: mixed slashes
run_test "@../subdir\\file blocks" \
  'Read @../subdir\file.txt' \
  '2'

# Case 7: tab-separated
run_test "@../ after tab blocks" \
  $'Read\t@../tab/file' \
  '2'

# Case 8: newline-separated
run_test "@../ on separate line blocks" \
  $'Please review:\n@../parent/file.txt' \
  '2'

# === Allow cases (exit 0) ===

# Case 9: workspace attachment (no parent traversal)
run_test "@workspace/file passes" \
  'Read @Library/Security/KeyIV.cs' \
  '0'

# Case 10: current-directory attachment passes
run_test "@./file passes" \
  'Read @./current/file.txt' \
  '0'

# Case 11: plain @file passes
run_test "@file (no slash) passes" \
  'Read @config.json' \
  '0'

# Case 12: absolute path with no @ prefix passes
run_test "Absolute path without @ passes" \
  'Read /etc/hosts' \
  '0'

# Case 13: empty prompt passes
run_test "Empty prompt passes" \
  '' \
  '0'

# Case 14: text containing "../" without @ passes
run_test "../ without @ prefix passes" \
  'The relative path ../config.json should be avoided' \
  '0'

# Case 15: literal "@.." without slash passes (incomplete syntax)
run_test "@.. without trailing slash passes" \
  'The user wrote @.. as an example' \
  '0'

# === Configuration cases ===

# Case 16: warn-only mode does not block
run_test "Block mode 0 does not block (advisory)" \
  'Read @../Library/Security/KeyIV.cs' \
  '0' \
  'CC_ATTACHMENT_TRAVERSAL_BLOCK=0'

# Case 17: explicit allow regex permits
run_test "Allow regex permits matching path" \
  'Read @../allowed/specific.txt' \
  '0' \
  'CC_ATTACHMENT_TRAVERSAL_ALLOW_REGEX=@\.\./allowed/specific\.txt'

# Case 18: allow regex that does not match still blocks
run_test "Allow regex non-matching blocks" \
  'Read @../denied/secret.env' \
  '2' \
  'CC_ATTACHMENT_TRAVERSAL_ALLOW_REGEX=@\.\./allowed/specific\.txt'

# === Robustness ===

# Case 19: malformed JSON gracefully passes (no prompt to scan)
malformed_payload='{not-valid-json'
actual_exit=$(echo "$malformed_payload" | "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$actual_exit" = "0" ]; then
  PASS=$((PASS + 1))
  echo "PASS: Malformed JSON passes silently (exit 0)"
else
  FAIL=$((FAIL + 1))
  echo "FAIL: Malformed JSON expected 0, got $actual_exit"
fi

# Case 20: JSON without .prompt field passes
no_prompt_payload='{"other_field":"value"}'
actual_exit=$(echo "$no_prompt_payload" | "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$actual_exit" = "0" ]; then
  PASS=$((PASS + 1))
  echo "PASS: Missing .prompt field passes (exit 0)"
else
  FAIL=$((FAIL + 1))
  echo "FAIL: Missing .prompt expected 0, got $actual_exit"
fi

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="
exit $FAIL
