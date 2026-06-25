#!/bin/bash
# Standalone tests for write-nul-corruption-detector.sh
# Run: bash tests/write-nul-corruption-detector.test.sh
HOOK="$(dirname "$0")/../examples/write-nul-corruption-detector.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)

run() { # desc input expected_exit
    local desc="$1" input="$2" expected="$3" actual=0
    echo "$input" | bash "$HOOK" >/dev/null 2>&1 || actual=$?
    if [ "$actual" -eq "$expected" ]; then echo "  PASS: $desc"; PASS=$((PASS+1));
    else echo "  FAIL: $desc (expected $expected, got $actual)"; FAIL=$((FAIL+1)); fi
}

printf 'clean text line\n' > "$TMP/clean.txt"
printf 'good stuff\x00\x00\x00corrupted tail' > "$TMP/bad.txt"
# Same byte count as a 12-char file but tail is NUL-padded — wc -c cannot tell.
printf 'AAAAAA\x00\x00\x00\x00\x00\x00' > "$TMP/pad.txt"
printf 'binary\x00\x00data' > "$TMP/img.png"

run "empty input passes"                 '{}' 0
run "missing file passes"                '{"tool_name":"Write","tool_input":{"file_path":"/nonexistent/xyz.txt"}}' 0
run "clean text passes"                  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/clean.txt\"}}" 0
run "NUL corruption flagged"             "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/bad.txt\"}}" 2
run "NUL padding (size-preserving) flagged" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/pad.txt\"}}" 2
run "binary extension skipped"           "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/img.png\"}}" 0

echo "Results: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
