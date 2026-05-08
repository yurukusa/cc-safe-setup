#!/bin/bash
# Test for mcp-startup-bloat-detector.sh
#
# Verifies the hook warns when claude mcp list shows enough
# claude.ai-prefixed connectors to cross the threshold, and
# stays silent below the threshold or when explicitly disabled.

set -u

HOOK="$(dirname "$0")/../examples/mcp-startup-bloat-detector.sh"
[ ! -x "$HOOK" ] && chmod +x "$HOOK"

PASS=0
FAIL=0

LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR"

# Stub claude binary that prints a controlled mcp list
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT

make_stub() {
    local connector_count="$1"
    cat > "$STUB_DIR/claude" <<STUB
#!/bin/bash
if [ "\$1" = "mcp" ] && [ "\$2" = "list" ]; then
    echo "Checking MCP server health..."
    echo ""
STUB
    for i in $(seq 1 "$connector_count"); do
        printf '    echo "claude.ai Service%d: https://example.com/mcp/v1 - ✓ Connected"\n' "$i" >> "$STUB_DIR/claude"
    done
    cat >> "$STUB_DIR/claude" <<'STUB'
    echo "local-server: node /tmp/local.js - ✓ Connected"
fi
STUB
    chmod +x "$STUB_DIR/claude"
}

run_case() {
    local name="$1"
    local connector_count="$2"
    local threshold="$3"
    local expect_warn="$4"   # "yes" or "no"
    local extra_env="${5:-}"

    make_stub "$connector_count"

    local sess="bloat-test-$(date +%s%N)-$$"
    local input
    input=$(jq -nc --arg sid "$sess" '{session_id:$sid}')

    local stderr rc
    stderr=$(echo "$input" | env -i HOME="$HOME" PATH="$STUB_DIR:/usr/bin:/bin" \
        MCP_BLOAT_THRESHOLD_COUNT="$threshold" $extra_env "$HOOK" 2>&1 >/dev/null)
    rc=$?

    local warned=no
    if echo "$stderr" | grep -q "mcp-startup-bloat-detector"; then
        warned=yes
    fi

    if [ "$rc" -ne 0 ]; then
        FAIL=$((FAIL+1))
        echo "FAIL: $name — exit $rc (expected 0)"
    elif [ "$warned" = "$expect_warn" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $name — warned=$warned, expected $expect_warn"
        echo "      stderr: $stderr"
    fi

    # Cleanup the per-session log so reruns are deterministic
    [ -f "$LOG_DIR/mcp-bloat-warned-$sess" ] && rm -f "$LOG_DIR/mcp-bloat-warned-$sess"
}

# Test 1: count below threshold → silent
run_case "below threshold stays silent" 3 5 no

# Test 2: count at threshold → warns
run_case "at threshold warns" 5 5 yes

# Test 3: count above threshold → warns
run_case "above threshold warns" 12 5 yes

# Test 4: zero connectors → silent
run_case "zero connectors stays silent" 0 5 no

# Test 5: disable env silences even above threshold
run_case "disable env silences" 12 5 no "MCP_BLOAT_DETECTOR_DISABLE=1"

# Test 6: second run in the same session is silent
SESS2="bloat-test-twice-$(date +%s%N)-$$"
make_stub 12
INPUT2=$(jq -nc --arg sid "$SESS2" '{session_id:$sid}')
FIRST=$(echo "$INPUT2" | env -i HOME="$HOME" PATH="$STUB_DIR:/usr/bin:/bin" \
    MCP_BLOAT_THRESHOLD_COUNT=5 "$HOOK" 2>&1 >/dev/null)
SECOND=$(echo "$INPUT2" | env -i HOME="$HOME" PATH="$STUB_DIR:/usr/bin:/bin" \
    MCP_BLOAT_THRESHOLD_COUNT=5 "$HOOK" 2>&1 >/dev/null)
if echo "$FIRST" | grep -q "mcp-startup-bloat-detector" \
   && ! echo "$SECOND" | grep -q "mcp-startup-bloat-detector"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: second run in same session not silenced"
    echo "      first:  $FIRST"
    echo "      second: $SECOND"
fi
[ -f "$LOG_DIR/mcp-bloat-warned-$SESS2" ] && rm -f "$LOG_DIR/mcp-bloat-warned-$SESS2"

# Test 7: claude binary missing → exits cleanly (silent)
SESS7="bloat-test-noclaude-$(date +%s%N)-$$"
INPUT7=$(jq -nc --arg sid "$SESS7" '{session_id:$sid}')
NOCLAUDE_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR" "$NOCLAUDE_DIR"' EXIT
STDERR7=$(echo "$INPUT7" | env -i HOME="$HOME" PATH="$NOCLAUDE_DIR:/usr/bin:/bin" \
    MCP_BLOAT_THRESHOLD_COUNT=5 "$HOOK" 2>&1 >/dev/null)
RC7=$?
if [ "$RC7" -eq 0 ] && ! echo "$STDERR7" | grep -q "mcp-startup-bloat-detector"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: missing claude binary should exit 0 silent (rc=$RC7, stderr=$STDERR7)"
fi

# Test 8: malformed input (no session_id) → still safe
STDERR8=$(echo '{}' | env -i HOME="$HOME" PATH="$STUB_DIR:/usr/bin:/bin" \
    MCP_BLOAT_THRESHOLD_COUNT=5 "$HOOK" 2>&1 >/dev/null)
RC8=$?
if [ "$RC8" -eq 0 ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: malformed input should exit 0 (rc=$RC8)"
fi

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
