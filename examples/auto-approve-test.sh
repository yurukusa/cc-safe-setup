#!/bin/bash
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
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
