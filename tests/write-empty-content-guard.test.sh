#!/bin/bash
# Tests for write-empty-content-guard.sh (#72666)
# Run: bash tests/write-empty-content-guard.test.sh
set -uo pipefail

PASS=0
FAIL=0
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/write-empty-content-guard.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

NONEMPTY="$TMP/keep.txt"; printf 'line1\nline2\nline3\n' > "$NONEMPTY"
EMPTYF="$TMP/empty.txt";  : > "$EMPTYF"
NEWF="$TMP/new.txt"       # does not exist

run() { # $1 = file, $2 = content (raw)
    local exit=0
    jq -cn --arg f "$1" --arg c "$2" '{tool_input:{file_path:$f,content:$c}}' | bash "$HOOK" >/dev/null 2>/dev/null || exit=$?
    echo "$exit"
}

check() { # $1 = expected exit, $2 = actual exit, $3 = desc
    if [ "$1" = "$2" ]; then echo "  PASS: $3"; PASS=$((PASS+1)); else echo "  FAIL: $3 (expected $1, got $2)"; FAIL=$((FAIL+1)); fi
}

echo "write-empty-content-guard.sh tests"
echo ""

check 2 "$(run "$NONEMPTY" "")"            "empty content over non-empty file -> BLOCK (exit 2)"
check 2 "$(run "$NONEMPTY" "
	 ")"                                    "whitespace-only content over non-empty file -> BLOCK"
check 0 "$(run "$NONEMPTY" "new real text")" "real content over non-empty file -> allow"
check 0 "$(run "$EMPTYF" "")"              "empty content over already-empty file -> allow (nothing to lose)"
check 0 "$(run "$NEWF" "")"                "empty content to a new (nonexistent) file -> allow (creation)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
