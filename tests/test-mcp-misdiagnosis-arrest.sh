#!/bin/bash
# tests/test-mcp-misdiagnosis-arrest.sh
# Standalone test suite for examples/mcp-misdiagnosis-arrest.sh
# (precedent: tests/test-commitment-carry-forward-arrest.sh)

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SCRIPT_DIR/../examples/mcp-misdiagnosis-arrest.sh"

if [ ! -x "$HOOK" ]; then
    echo "FAIL: hook not executable: $HOOK"
    exit 1
fi

PASS=0
FAIL=0

# Fixture dir for synthetic settings.json files used across tests.
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Create a fixture settings.json that has Slack and GitHub plugins enabled.
INSTALLED_FIXTURE="$FIXTURE_DIR/settings-installed.json"
cat > "$INSTALLED_FIXTURE" <<'JSON'
{
  "enabledPlugins": {
    "slack@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "linear@claude-plugins-official": false
  }
}
JSON

# Fixture with no connectors installed.
EMPTY_FIXTURE="$FIXTURE_DIR/settings-empty.json"
cat > "$EMPTY_FIXTURE" <<'JSON'
{
  "enabledPlugins": {}
}
JSON

# Fixture with mcpServers entries (alternate shape).
MCPSERVERS_FIXTURE="$FIXTURE_DIR/settings-mcpservers.json"
cat > "$MCPSERVERS_FIXTURE" <<'JSON'
{
  "mcpServers": {
    "slack": { "command": "slack-mcp" },
    "github": { "command": "github-mcp" }
  }
}
JSON

# Helper: feed a JSON Stop event with the given assistant text to the hook,
# capture exit code + stderr. Args:
#   $1 = test description
#   $2 = expected exit code
#   $3 = settings.json fixture path (or "missing" for no file)
#   $4 = mode ("advisory" or "strict")
#   $5 = expected stderr substring (optional; "" to skip stderr check)
#   $6 = assistant text
run_case() {
    local desc="$1"
    local expected_exit="$2"
    local settings="$3"
    local mode="$4"
    local expected_stderr="$5"
    local assistant_text="$6"

    local payload
    payload=$(jq -nc --arg t "$assistant_text" '{transcript:[{content:$t}]}')

    local stderr_file actual_exit=0
    stderr_file=$(mktemp)

    local env_args=()
    if [ "$settings" = "missing" ]; then
        env_args+=("CC_MCP_SETTINGS_PATH=/nonexistent/path/settings.json")
    else
        env_args+=("CC_MCP_SETTINGS_PATH=$settings")
    fi
    if [ "$mode" = "strict" ]; then
        env_args+=("CC_MCP_MISDIAGNOSIS_MODE=strict")
    fi

    printf '%s' "$payload" | env "${env_args[@]}" bash "$HOOK" >/dev/null 2>"$stderr_file" || actual_exit=$?

    local ok=1
    if [ "$actual_exit" -ne "$expected_exit" ]; then
        ok=0
    fi
    if [ -n "$expected_stderr" ]; then
        if ! grep -Fq "$expected_stderr" "$stderr_file"; then
            ok=0
        fi
    fi

    if [ "$ok" -eq 1 ]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        if [ -n "$expected_stderr" ]; then
            echo "  expected stderr substring: $expected_stderr"
        fi
        echo "  stderr was:"
        sed 's/^/    /' "$stderr_file"
        FAIL=$((FAIL + 1))
    fi

    rm -f "$stderr_file"
}

echo "=== Group 1: input handling ==="

run_case "1.1 empty stdin exits 0" \
    0 "$INSTALLED_FIXTURE" advisory "" ""

run_case "1.2 unparseable input exits 0" \
    0 "$INSTALLED_FIXTURE" advisory "" "not json at all"

# Empty assistant text → silent.
run_case "1.3 empty assistant text exits 0" \
    0 "$INSTALLED_FIXTURE" advisory "" ""

# Test global disable.
echo "=== Group 2: disable switch ==="
DISABLE_PAYLOAD=$(jq -nc --arg t "the Slack Connector isn't installed" \
    '{transcript:[{content:$t}]}')
DISABLE_EXIT=0
printf '%s' "$DISABLE_PAYLOAD" | \
    CC_MCP_SETTINGS_PATH="$INSTALLED_FIXTURE" \
    CC_MCP_MISDIAGNOSIS_DISABLE=1 \
    CC_MCP_MISDIAGNOSIS_MODE=strict \
    bash "$HOOK" >/dev/null 2>/dev/null || DISABLE_EXIT=$?
if [ "$DISABLE_EXIT" -eq 0 ]; then
    echo "PASS: 2.1 DISABLE=1 bypasses misdiagnosis check even in strict mode"
    PASS=$((PASS + 1))
else
    echo "FAIL: 2.1 DISABLE=1 should exit 0 (got $DISABLE_EXIT)"
    FAIL=$((FAIL + 1))
fi

echo "=== Group 3: silent / non-matching turns ==="

run_case "3.1 turn with no MCP mention exits 0" \
    0 "$INSTALLED_FIXTURE" advisory "" \
    "Read the file and edit line 5."

run_case "3.2 turn that successfully used Slack tools exits 0" \
    0 "$INSTALLED_FIXTURE" advisory "" \
    "I sent the Slack message to #ops. Anything else?"

run_case "3.3 turn that talks about MCP without misdiagnosis exits 0" \
    0 "$INSTALLED_FIXTURE" advisory "" \
    "The MCP protocol uses JSON-RPC over stdio."

echo "=== Group 4: misdiagnosis matches (advisory mode, exit 0) ==="

run_case "4.1 'Slack Connector isn't installed' fires advisory" \
    0 "$INSTALLED_FIXTURE" advisory "MCP MISDIAGNOSIS LIKELY" \
    "It looks like the Slack Connector isn't installed. Please install it first."

run_case "4.2 'Slack Plugin needs to be installed' fires advisory" \
    0 "$INSTALLED_FIXTURE" advisory "MCP MISDIAGNOSIS LIKELY" \
    "The Slack Plugin needs to be installed before I can post."

run_case "4.3 'install the Slack Connector first' fires advisory" \
    0 "$INSTALLED_FIXTURE" advisory "MCP MISDIAGNOSIS LIKELY" \
    "You need to install the Slack Connector first."

run_case "4.4 'MCP server is not configured' fires advisory" \
    0 "$INSTALLED_FIXTURE" advisory "MCP MISDIAGNOSIS LIKELY" \
    "The MCP server is not configured. Set it up in settings.json."

run_case "4.5 'MCP tools aren't available' fires advisory" \
    0 "$INSTALLED_FIXTURE" advisory "MCP MISDIAGNOSIS LIKELY" \
    "The MCP tools aren't available in this session."

run_case "4.6 advisory mentions the actual recovery path" \
    0 "$INSTALLED_FIXTURE" advisory "Open a new chat in the same Claude Code window" \
    "The Slack Connector isn't installed."

run_case "4.7 advisory references #60428" \
    0 "$INSTALLED_FIXTURE" advisory "#60428" \
    "The Slack Connector isn't installed."

run_case "4.8 advisory lists installed connectors" \
    0 "$INSTALLED_FIXTURE" advisory "slack@claude-plugins-official" \
    "The Slack Connector isn't installed."

echo "=== Group 5: name-matching ==="

run_case "5.1 specifically names matched installed connector" \
    0 "$INSTALLED_FIXTURE" advisory "Specifically, 'slack@claude-plugins-official' is already installed" \
    "The Slack Connector isn't installed."

run_case "5.2 named connector not in installed set: cautions about name" \
    0 "$INSTALLED_FIXTURE" advisory "double-check the name before" \
    "The Notion Connector isn't installed."

echo "=== Group 6: strict mode ==="

run_case "6.1 strict mode: misdiagnosis + installed → exit 2" \
    2 "$INSTALLED_FIXTURE" strict "MCP MISDIAGNOSIS LIKELY" \
    "The Slack Connector isn't installed."

run_case "6.2 strict mode: no misdiagnosis → exit 0" \
    0 "$INSTALLED_FIXTURE" strict "" \
    "Slack message sent."

run_case "6.3 strict mode: misdiagnosis + nothing installed → exit 0" \
    0 "$EMPTY_FIXTURE" strict "" \
    "The Slack Connector isn't installed."

echo "=== Group 7: settings shapes ==="

run_case "7.1 mcpServers shape: misdiagnosis fires" \
    0 "$MCPSERVERS_FIXTURE" advisory "MCP MISDIAGNOSIS LIKELY" \
    "The Slack Connector isn't installed."

run_case "7.2 missing settings.json: stay silent (no false-positive)" \
    0 missing advisory "" \
    "The Slack Connector isn't installed."

run_case "7.3 empty settings.json: stay silent (nothing to contradict)" \
    0 "$EMPTY_FIXTURE" advisory "" \
    "The Slack Connector isn't installed."

echo ""
echo "============================================================"
echo "RESULTS: $PASS passed, $FAIL failed, $((PASS + FAIL)) total"
echo "============================================================"

[ "$FAIL" -eq 0 ]
