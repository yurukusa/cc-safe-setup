#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Approve only when EVERY command position qualifies.
#
# The patterns below were anchored at `^\s*` and matched against the whole
# command string, so only the first command position was examined and the
# approval was then handed to the entire line: `pytest && sudo rm -rf app` was
# approved on the strength of its first word. Measured 2026-08-03. Same defect
# as PR #937 / #940 / #941, on the approving side, where the decision is an
# explicit approval rather than a missed block.
#
# Splitting on the separator characters is approximate — quotes are not parsed —
# so anything that can hide a command from a string-level read (command
# substitution, backticks) disqualifies the line outright. A line that does not
# qualify gets no decision, which leaves it to the normal permission flow. This
# hook only ever adds approval; it never blocks.
#
# The gate uses the union of all eight patterns, so a chain of test runners
# (`pytest && go test ./...`) still passes; the if-chain below only picks which
# reason to report.
cc_every_segment_matches() {
    local pat="$1" cmd="$2" seg
    case "$cmd" in *'$('*|*'`'*) return 1 ;; esac
    while IFS= read -r seg; do
        seg="${seg#"${seg%%[![:space:]]*}"}"
        seg="${seg%"${seg##*[![:space:]]}"}"
        [ -z "$seg" ] && continue
        printf '%s' "$seg" | grep -qE "$pat" || return 1
    done <<EOF
$(printf '%s' "$cmd" | tr ';&|' '\n\n\n')
EOF
    return 0
}

TEST_SAFE_RE='^\s*(npm\s+test|npm\s+run\s+test|npx\s+(jest|vitest|mocha|ava|tap|playwright\s+test|cypress\s+run)|yarn\s+test|pnpm\s+test|bun\s+test)\b'
TEST_SAFE_RE="$TEST_SAFE_RE"'|^\s*(pytest|python\s+-m\s+(pytest|unittest)|tox)\b'
TEST_SAFE_RE="$TEST_SAFE_RE"'|^\s*go\s+test\b'
TEST_SAFE_RE="$TEST_SAFE_RE"'|^\s*cargo\s+test\b'
TEST_SAFE_RE="$TEST_SAFE_RE"'|^\s*(phpunit|vendor/bin/phpunit|php\s+artisan\s+test)\b'
TEST_SAFE_RE="$TEST_SAFE_RE"'|^\s*(rspec|bundle\s+exec\s+rspec|rake\s+test|rails\s+test)\b'
TEST_SAFE_RE="$TEST_SAFE_RE"'|^\s*(mvn\s+test|gradle\s+test|./gradlew\s+test)\b'
TEST_SAFE_RE="$TEST_SAFE_RE"'|^\s*dotnet\s+test\b'

cc_every_segment_matches "$TEST_SAFE_RE" "$COMMAND" || exit 0

if echo "$COMMAND" | grep -qE '^\s*(npm\s+test|npm\s+run\s+test|npx\s+(jest|vitest|mocha|ava|tap|playwright\s+test|cypress\s+run)|yarn\s+test|pnpm\s+test|bun\s+test)\b'; then
    echo '{"decision":"approve","reason":"Test runner command"}'
    exit 0
fi
if echo "$COMMAND" | grep -qE '^\s*(pytest|python\s+-m\s+(pytest|unittest)|tox)\b'; then
    echo '{"decision":"approve","reason":"Python test runner"}'
    exit 0
fi
if echo "$COMMAND" | grep -qE '^\s*go\s+test\b'; then
    echo '{"decision":"approve","reason":"Go test runner"}'
    exit 0
fi
if echo "$COMMAND" | grep -qE '^\s*cargo\s+test\b'; then
    echo '{"decision":"approve","reason":"Cargo test runner"}'
    exit 0
fi
if echo "$COMMAND" | grep -qE '^\s*(phpunit|vendor/bin/phpunit|php\s+artisan\s+test)\b'; then
    echo '{"decision":"approve","reason":"PHP test runner"}'
    exit 0
fi
if echo "$COMMAND" | grep -qE '^\s*(rspec|bundle\s+exec\s+rspec|rake\s+test|rails\s+test)\b'; then
    echo '{"decision":"approve","reason":"Ruby test runner"}'
    exit 0
fi
if echo "$COMMAND" | grep -qE '^\s*(mvn\s+test|gradle\s+test|./gradlew\s+test)\b'; then
    echo '{"decision":"approve","reason":"Java test runner"}'
    exit 0
fi
if echo "$COMMAND" | grep -qE '^\s*dotnet\s+test\b'; then
    echo '{"decision":"approve","reason":".NET test runner"}'
    exit 0
fi
exit 0
