#!/bin/bash
# Tests for binary-read-detector.sh
# Covers: 25 binary extensions detection, advisory mode (exit 0),
# block mode (exit 2), disable env, custom extension list,
# multiple-path matching, fail-open on bad input.

HOOK="examples/binary-read-detector.sh"
PASS=0 FAIL=0

run_hook() {
    local payload="$1"; shift
    env -u CC_BINARY_READ_DISABLE -u CC_BINARY_READ_BLOCK \
        -u CC_BINARY_READ_EXTENSIONS \
        "$@" bash "$HOOK" <<< "$payload" 2>&1
}

run_and_capture() {
    local payload="$1"; shift
    env -u CC_BINARY_READ_DISABLE -u CC_BINARY_READ_BLOCK \
        -u CC_BINARY_READ_EXTENSIONS \
        "$@" bash "$HOOK" <<< "$payload" 2>&1
    LAST_RC=$?
}

assert_contains() { if echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: empty input — pass through
run_and_capture '{}'
assert_exit "empty input pass" "$LAST_RC" "0"

# Test 2: text-only prompt — silent
run_and_capture '{"prompt":"please run the tests and report"}'
assert_exit "text prompt pass" "$LAST_RC" "0"
OUT=$(run_hook '{"prompt":"please run the tests and report"}')
assert_not_contains "text prompt silent" "$OUT" "Binary path reference"

# Test 3: PNG reference — advisory (exit 0)
OUT=$(run_hook '{"prompt":"read screenshot.png and describe it"}')
LAST_RC=$?
run_and_capture '{"prompt":"read screenshot.png and describe it"}'
assert_exit "png advisory exit 0" "$LAST_RC" "0"
assert_contains "png named in advisory" "$OUT" "screenshot.png"
assert_contains "advisory references #62639" "$OUT" "#62639"

# Test 4: JPG reference
OUT=$(run_hook '{"prompt":"open foo.jpg and tell me what is shown"}')
assert_contains "jpg detected" "$OUT" "foo.jpg"

# Test 5: PDF reference
OUT=$(run_hook '{"prompt":"summarize document.pdf"}')
assert_contains "pdf detected" "$OUT" "document.pdf"

# Test 6: HEIC reference
OUT=$(run_hook '{"prompt":"read IMG_1234.heic"}')
assert_contains "heic detected" "$OUT" "IMG_1234.heic"

# Test 7: WEBP reference
OUT=$(run_hook '{"prompt":"check image.webp"}')
assert_contains "webp detected" "$OUT" "image.webp"

# Test 8: GIF reference
OUT=$(run_hook '{"prompt":"read animation.gif"}')
assert_contains "gif detected" "$OUT" "animation.gif"

# Test 9: MP4 reference
OUT=$(run_hook '{"prompt":"analyze video.mp4"}')
assert_contains "mp4 detected" "$OUT" "video.mp4"

# Test 10: zip reference
OUT=$(run_hook '{"prompt":"extract archive.zip"}')
assert_contains "zip detected" "$OUT" "archive.zip"

# Test 11: DOCX reference
OUT=$(run_hook '{"prompt":"read contract.docx"}')
assert_contains "docx detected" "$OUT" "contract.docx"

# Test 12: XLSX reference
OUT=$(run_hook '{"prompt":"open data.xlsx"}')
assert_contains "xlsx detected" "$OUT" "data.xlsx"

# Test 13: multiple binary paths in same prompt
OUT=$(run_hook '{"prompt":"compare foo.png with bar.pdf"}')
assert_contains "first path in multi" "$OUT" "foo.png"
assert_contains "second path in multi" "$OUT" "bar.pdf"

# Test 14: path with directory
OUT=$(run_hook '{"prompt":"read ~/Downloads/screenshot.png"}')
assert_contains "path with home dir" "$OUT" "Downloads/screenshot.png"

# Test 15: absolute path
OUT=$(run_hook '{"prompt":"read /Users/me/Desktop/foo.png"}')
assert_contains "absolute path" "$OUT" "Desktop/foo.png"

# Test 16: case-insensitive matching
OUT=$(run_hook '{"prompt":"open IMAGE.PNG"}')
assert_contains "uppercase ext detected" "$OUT" "IMAGE.PNG"

# Test 17: mixed case
OUT=$(run_hook '{"prompt":"read Photo.Jpeg"}')
assert_contains "mixed case detected" "$OUT" "Photo.Jpeg"

# Test 18: DISABLE env suppresses everything
run_and_capture '{"prompt":"read foo.png"}' CC_BINARY_READ_DISABLE=1
assert_exit "disable exit 0" "$LAST_RC" "0"
OUT=$(run_hook '{"prompt":"read foo.png"}' CC_BINARY_READ_DISABLE=1)
assert_not_contains "disable silent" "$OUT" "Binary path reference"

# Test 19: BLOCK env changes exit to 2
run_and_capture '{"prompt":"read foo.png"}' CC_BINARY_READ_BLOCK=1
assert_exit "block exit 2" "$LAST_RC" "2"
OUT=$(run_hook '{"prompt":"read foo.png"}' CC_BINARY_READ_BLOCK=1)
assert_contains "block still emits advisory" "$OUT" "Binary path reference"

# Test 20: custom EXTENSIONS env (only .secret)
run_and_capture '{"prompt":"read foo.png"}' CC_BINARY_READ_EXTENSIONS=secret
assert_exit "custom ext png excluded pass" "$LAST_RC" "0"
OUT=$(run_hook '{"prompt":"read foo.secret"}' CC_BINARY_READ_EXTENSIONS=secret)
assert_contains "custom ext secret detected" "$OUT" "foo.secret"

# Test 21: malformed JSON — fail-open
run_and_capture 'not-json'
assert_exit "malformed input exit 0" "$LAST_RC" "0"

# Test 22: missing prompt field — fail-open
run_and_capture '{"other":"field"}'
assert_exit "missing prompt exit 0" "$LAST_RC" "0"

# Test 23: empty prompt — fail-open silent
run_and_capture '{"prompt":""}'
assert_exit "empty prompt exit 0" "$LAST_RC" "0"
OUT=$(run_hook '{"prompt":""}')
assert_not_contains "empty prompt silent" "$OUT" "Binary path reference"

# Test 24: user_message field as alternative name
OUT=$(run_hook '{"user_message":"read photo.png"}')
assert_contains "user_message field works" "$OUT" "photo.png"

# Test 25: advisory mentions PreToolUse bypass
OUT=$(run_hook '{"prompt":"read foo.png"}')
assert_contains "advisory names PreToolUse bypass" "$OUT" "PreToolUse hooks will NOT fire"

# Test 26: advisory provides four operator-side options
OUT=$(run_hook '{"prompt":"read foo.png"}')
assert_contains "advisory option 1 verify trust" "$OUT" "Verify the file is trusted"
assert_contains "advisory option 2 pre-process" "$OUT" "Pre-process to text"
assert_contains "advisory option 3 PostToolUse" "$OUT" "PostToolUse"
assert_contains "advisory option 4 OS layer" "$OUT" "AppArmor"

# Test 27: advisory mentions disable env
OUT=$(run_hook '{"prompt":"read foo.png"}')
assert_contains "advisory mentions disable env" "$OUT" "CC_BINARY_READ_DISABLE=1"

# Test 28: text file (.txt) not detected
OUT=$(run_hook '{"prompt":"read notes.txt and summarize"}')
assert_not_contains "txt not detected" "$OUT" "Binary path reference"

# Test 29: source code file (.py, .js) not detected
OUT=$(run_hook '{"prompt":"read main.py"}')
assert_not_contains "py not detected" "$OUT" "Binary path reference"
OUT=$(run_hook '{"prompt":"read app.js"}')
assert_not_contains "js not detected" "$OUT" "Binary path reference"

# Test 30: bin / exe / dll detected (binaries)
OUT=$(run_hook '{"prompt":"run firmware.bin"}')
assert_contains "bin detected" "$OUT" "firmware.bin"
OUT=$(run_hook '{"prompt":"open setup.exe"}')
assert_contains "exe detected" "$OUT" "setup.exe"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
