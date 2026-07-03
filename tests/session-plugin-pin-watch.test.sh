#!/bin/bash
# Tests for session-plugin-pin-watch.sh (#73952)
# Run: bash tests/session-plugin-pin-watch.test.sh
set -uo pipefail

PASS=0
FAIL=0
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/session-plugin-pin-watch.sh"

TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT
mkdir -p "$TESTHOME/.claude/plugins/mkt/pluginA/v1.0.0/hooks" \
         "$TESTHOME/.claude/plugins/mkt/pluginB/v2.3.0/hooks"
GLOB="$TESTHOME/.claude/plugins/*/*/*"
SID="t-sid"

run() { # $1 = event
    HOME="$TESTHOME" CC_PLUGIN_WATCH_GLOB="$GLOB" bash "$HOOK" <<EOF
{"hook_event_name":"$1","session_id":"$SID"}
EOF
}

assert_warns() { # $1 = "warn"|"quiet", $2 = event, $3 = desc
    local out; out=$(run "$2")
    if [ "$1" = "warn" ]; then
        if printf '%s' "$out" | grep -q "systemMessage"; then echo "  PASS: $3"; PASS=$((PASS+1)); else echo "  FAIL: $3 (expected warning, got: ${out:-none})"; FAIL=$((FAIL+1)); fi
    else
        if [ -z "$out" ]; then echo "  PASS: $3"; PASS=$((PASS+1)); else echo "  FAIL: $3 (expected quiet, got: $out)"; FAIL=$((FAIL+1)); fi
    fi
}

echo "session-plugin-pin-watch.sh tests"
echo ""

assert_warns quiet SessionStart "SessionStart -> snapshot, quiet"
assert_warns quiet PreToolUse   "PreToolUse, all dirs present -> quiet"

rm -rf "$TESTHOME/.claude/plugins/mkt/pluginA/v1.0.0"   # simulate re-materialization removing pinned path
assert_warns warn PreToolUse    "pinned version dir vanished -> warn"

assert_warns quiet PreToolUse   "state refreshed, nothing new vanished -> quiet (no spam)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
