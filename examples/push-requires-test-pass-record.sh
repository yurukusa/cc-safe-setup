#!/bin/bash
# push-requires-test-pass-record.sh — Record when tests pass (companion to push-requires-test-pass.sh)
#
# PostToolUse hook that detects successful test runs and records the timestamp.
# The PreToolUse companion then checks this record before allowing git push.
#
# Detected test commands: npm test, pytest, cargo test, go test, make test, etc.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output.exit_code // .exit_code // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Only record on exit code 0 (success)
[ "$EXIT_CODE" = "0" ] || exit 0

# Detect test commands
if echo "$COMMAND" | grep -qE '(npm\s+test|npx\s+jest|npx\s+vitest|npx\s+mocha|pytest|python\s+-m\s+pytest|cargo\s+test|go\s+test|make\s+test|gradle\s+test|mvn\s+test|bundle\s+exec\s+rspec|php\s+artisan\s+test|dotnet\s+test|bash\s+test\.sh)'; then
    STATE_FILE="/tmp/.cc-test-pass-$(pwd | md5sum | cut -c1-8)"
    date +%s > "$STATE_FILE"
fi

exit 0
