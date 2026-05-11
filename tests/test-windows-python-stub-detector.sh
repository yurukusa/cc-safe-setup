#!/bin/bash
# Tests for windows-python-stub-detector.sh
# Run: bash tests/test-windows-python-stub-detector.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/windows-python-stub-detector.sh"
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

# --- Mock python3 binaries ---

# Real python3 mock: prints "ok", exits 0
cat > "$MOCK_DIR/real-python3" <<'EOF'
#!/bin/bash
if [ "$1" = "-c" ]; then
    printf "ok"
fi
exit 0
EOF
chmod +x "$MOCK_DIR/real-python3"

# Store stub mock: exits 49, no output (the documented Git Bash signal)
cat > "$MOCK_DIR/stub-python3-exit49" <<'EOF'
#!/bin/bash
exit 49
EOF
chmod +x "$MOCK_DIR/stub-python3-exit49"

# Store stub mock variant: exits 1, "Microsoft Store" in stderr
cat > "$MOCK_DIR/stub-python3-storemsg" <<'EOF'
#!/bin/bash
echo "Python was not found; install it from Microsoft Store" >&2
exit 1
EOF
chmod +x "$MOCK_DIR/stub-python3-storemsg"

# Silent-success stub: exits 0 but produces no output
cat > "$MOCK_DIR/stub-python3-silent" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$MOCK_DIR/stub-python3-silent"

# Missing python3: command not found
# (no mock — just point at /nonexistent path)

# Helper: run hook with given python3 mock, check output
test_hook_output() {
    local python_path="$1"
    local input="$2"
    local expect_warning="$3"
    local desc="$4"

    local output
    output=$(echo "$input" | CC_PYTHON_CMD="$python_path" bash "$HOOK" 2>&1) || true

    local saw_warning=0
    if echo "$output" | grep -q 'python3 stub detected'; then
        saw_warning=1
    fi

    if [ "$saw_warning" -eq "$expect_warning" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected warning=$expect_warning, got=$saw_warning)"
        echo "    output: $output"
        FAIL=$((FAIL + 1))
    fi
}

# Helper: verify the hook always exits 0 (advisory, never block)
test_hook_exit() {
    local python_path="$1"
    local desc="$2"

    local actual_exit=0
    echo '{}' | CC_PYTHON_CMD="$python_path" bash "$HOOK" >/dev/null 2>&1 || actual_exit=$?

    if [ "$actual_exit" -eq 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit 0, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "windows-python-stub-detector.sh tests"
echo ""

# --- Real Python ---
test_hook_output "$MOCK_DIR/real-python3" '{}' 0 "Real python3 produces no warning"
test_hook_exit "$MOCK_DIR/real-python3" "Real python3 exits 0"

# --- Store stub: exit 49 ---
test_hook_output "$MOCK_DIR/stub-python3-exit49" '{}' 1 "Exit 49 stub triggers warning"
test_hook_exit "$MOCK_DIR/stub-python3-exit49" "Exit 49 stub still exits 0 (advisory)"

# --- Store stub: Microsoft Store stderr ---
test_hook_output "$MOCK_DIR/stub-python3-storemsg" '{}' 1 "Store-redirect stderr triggers warning"
test_hook_exit "$MOCK_DIR/stub-python3-storemsg" "Store-redirect stub exits 0"

# --- Silent-success stub ---
test_hook_output "$MOCK_DIR/stub-python3-silent" '{}' 1 "Silent stub (exit 0, no output) triggers warning"
test_hook_exit "$MOCK_DIR/stub-python3-silent" "Silent stub exits 0"

# --- Missing python3 ---
test_hook_output "/nonexistent/python3" '{}' 1 "Missing python3 triggers warning"
test_hook_exit "/nonexistent/python3" "Missing python3 still exits 0"

# --- Empty input ---
test_hook_output "$MOCK_DIR/real-python3" '' 0 "Empty input passes silently with real python"

# --- JSON SessionStart input ---
test_hook_output "$MOCK_DIR/stub-python3-exit49" '{"hook_event_name":"SessionStart","session_id":"abc123"}' 1 "SessionStart JSON input with stub triggers warning"

# --- Warning content shape ---
SHAPE_OUT=$(echo '{}' | CC_PYTHON_CMD="$MOCK_DIR/stub-python3-exit49" bash "$HOOK" 2>&1)
if echo "$SHAPE_OUT" | grep -q '"hookSpecificOutput"' && \
   echo "$SHAPE_OUT" | grep -q '"hookEventName":"SessionStart"' && \
   echo "$SHAPE_OUT" | grep -q '"additionalContext"' && \
   echo "$SHAPE_OUT" | grep -q 'claude-code#57946'; then
    echo "  PASS: Warning output matches expected hookSpecificOutput schema"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Warning output missing expected fields"
    echo "    output: $SHAPE_OUT"
    FAIL=$((FAIL + 1))
fi

# --- Resilience to weird python output ---
cat > "$MOCK_DIR/python-spammy" <<'EOF'
#!/bin/bash
echo "lots of unrelated output" >&2
echo "ok"
exit 0
EOF
chmod +x "$MOCK_DIR/python-spammy"
test_hook_output "$MOCK_DIR/python-spammy" '{}' 0 "Python with extra stderr but real 'ok' produces no warning"

echo ""
echo "Results: $PASS pass, $FAIL fail"
exit $FAIL
