#!/bin/bash
# Tests for disabled-plugin-spawn-detector.sh
HOOK="$(dirname "$0")/../examples/disabled-plugin-spawn-detector.sh"
PASS=0 FAIL=0

# Per-test sandbox: a fresh $HOME with a writable .claude tree.
SBX=""
setup() {
    SBX=$(mktemp -d)
    mkdir -p "$SBX/.claude/plugins"
    mkdir -p "$SBX/Library/Application Support/Claude/local-agent-mode-sessions"
}
teardown() {
    [ -n "$SBX" ] && rm -rf "$SBX"
    SBX=""
}

# Run hook in sandbox. Args: expected_exit, test_name, extra_env...
run_hook() {
    local expected="$1" desc="$2"; shift 2
    local actual stderr_file
    stderr_file=$(mktemp)
    actual=$(HOME="$SBX" env "$@" bash "$HOOK" 2>"$stderr_file"; echo $?)
    actual=$(printf '%s' "$actual" | tail -n1)
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected, got $actual)"
        echo "    --- stderr ---"
        sed 's/^/      /' "$stderr_file"
        FAIL=$((FAIL + 1))
    fi
    rm -f "$stderr_file"
}

# Run hook and capture stderr; assert it contains a substring.
run_hook_stderr_contains() {
    local needle="$1" desc="$2"; shift 2
    local actual stderr_file
    stderr_file=$(mktemp)
    HOME="$SBX" env "$@" bash "$HOOK" >/dev/null 2>"$stderr_file"
    if grep -qF "$needle" "$stderr_file"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (stderr missing: $needle)"
        echo "    --- stderr ---"
        sed 's/^/      /' "$stderr_file"
        FAIL=$((FAIL + 1))
    fi
    rm -f "$stderr_file"
}

echo "Testing disabled-plugin-spawn-detector.sh"
echo "========================================="

# 1. No settings.json — silent pass.
setup
run_hook 0 "no settings.json passes silently"
teardown

# 2. settings.json without enabledPlugins — pass.
setup
echo '{"theme":"dark"}' > "$SBX/.claude/settings.json"
run_hook 0 "settings.json with no enabledPlugins passes"
teardown

# 3. enabledPlugins all true — pass.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "foo@bar": true, "baz@bar": true } }
JSON
run_hook 0 "all-true enabledPlugins passes"
teardown

# 4. Disabled plugin with no spawn config anywhere — pass.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "nimble@claude-plugins-official": false } }
JSON
run_hook 0 "disabled plugin with no spawn config passes"
teardown

# 5. Disabled plugin with surviving spawn config in Claude Desktop path — warn.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "nimble@claude-plugins-official": false } }
JSON
mkdir -p "$SBX/Library/Application Support/Claude/local-agent-mode-sessions/aaa/bbb/rpm/plugin_xyz"
cat > "$SBX/Library/Application Support/Claude/local-agent-mode-sessions/aaa/bbb/rpm/plugin_xyz/.mcp.json" <<'JSON'
{ "nimble-mcp-server": { "command": "npx", "args": ["-y", "mcp-remote", "https://mcp.nimbleway.com/mcp"] } }
JSON
run_hook 0 "surviving spawn config warns but exits 0 by default"
run_hook_stderr_contains "surviving spawn config" "warning mentions surviving spawn config"
run_hook_stderr_contains "nimble@claude-plugins-official" "warning lists the disabled plugin id"
run_hook_stderr_contains ".mcp.json" "warning shows the spawn file path"
teardown

# 6. With CC_DPSD_BLOCK=1 and surviving config — exit 2.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "nimble@claude-plugins-official": false } }
JSON
mkdir -p "$SBX/Library/Application Support/Claude/local-agent-mode-sessions/aaa/rpm"
cat > "$SBX/Library/Application Support/Claude/local-agent-mode-sessions/aaa/rpm/.mcp.json" <<'JSON'
{ "nimble-mcp-server": { "command": "npx" } }
JSON
run_hook 2 "CC_DPSD_BLOCK=1 blocks when spawn config survives" CC_DPSD_BLOCK=1
teardown

# 7. With CC_DPSD_ALLOW=1 — pass silently even if config survives.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "nimble@claude-plugins-official": false } }
JSON
mkdir -p "$SBX/Library/Application Support/Claude/local-agent-mode-sessions/aaa/rpm"
cat > "$SBX/Library/Application Support/Claude/local-agent-mode-sessions/aaa/rpm/.mcp.json" <<'JSON'
{ "nimble-mcp-server": {} }
JSON
run_hook 0 "CC_DPSD_ALLOW=1 short-circuits the check" CC_DPSD_ALLOW=1
teardown

# 8. Multiple disabled plugins, only one with surviving config.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": {
    "nimble@claude-plugins-official": false,
    "wix@claude-plugins-official": false,
    "kept@bar": true
} }
JSON
mkdir -p "$SBX/Library/Application Support/Claude/local-agent-mode-sessions/aaa/rpm"
echo '{ "wix-server": {} }' > "$SBX/Library/Application Support/Claude/local-agent-mode-sessions/aaa/rpm/.mcp.json"
run_hook_stderr_contains "wix@claude-plugins-official" "warns about the disabled plugin that survived"
teardown

# 9. Disabled plugin in Claude Code's own plugins dir — also detected.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "serena@claude-plugins-official": false } }
JSON
mkdir -p "$SBX/.claude/plugins/cache/claude-plugins-official/serena"
echo '{ "serena-server": {} }' > "$SBX/.claude/plugins/cache/claude-plugins-official/serena/.mcp.json"
run_hook_stderr_contains "serena@claude-plugins-official" "Claude Code plugins dir is also scanned"
teardown

# 10. Enabled plugin with .mcp.json present — never warns.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "active@bar": true } }
JSON
mkdir -p "$SBX/.claude/plugins/cache/active"
echo '{ "active-server": {} }' > "$SBX/.claude/plugins/cache/active/.mcp.json"
run_hook 0 "enabled plugin with spawn config does not warn"
teardown

# 11. CC_DPSD_EXTRA_PATHS picks up custom directories.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "custom@bar": false } }
JSON
mkdir -p "$SBX/custom-store/plugin_a"
echo '{ "custom-server": {} }' > "$SBX/custom-store/plugin_a/.mcp.json"
run_hook_stderr_contains "custom@bar" "extra path scanned via CC_DPSD_EXTRA_PATHS" \
    CC_DPSD_EXTRA_PATHS="$SBX/custom-store"
teardown

# 12. Plugin name with regex metacharacter is matched literally.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "foo.bar@x": false } }
JSON
mkdir -p "$SBX/.claude/plugins/cache/foo.bar"
echo '{ "foo.bar-server": {} }' > "$SBX/.claude/plugins/cache/foo.bar/.mcp.json"
run_hook_stderr_contains "foo.bar@x" "plugin name with dot is matched literally"
teardown

# 13. .mcp.json that does NOT mention the plugin name — not flagged.
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "nimble@claude-plugins-official": false } }
JSON
mkdir -p "$SBX/.claude/plugins/cache/other"
echo '{ "unrelated-server": {} }' > "$SBX/.claude/plugins/cache/other/.mcp.json"
run_hook 0 ".mcp.json unrelated to disabled plugin is not flagged"
teardown

# 14. settings.json with malformed JSON — jq-less fallback still works,
#     jq path silently returns nothing (which is fine for an advisory hook).
setup
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "noisy@bar": false, broken
JSON
mkdir -p "$SBX/.claude/plugins/cache/noisy"
echo '{ "noisy-server": {} }' > "$SBX/.claude/plugins/cache/noisy/.mcp.json"
# Either jq fails (no output, no warning) or the regex fallback succeeds.
# Both are acceptable: the hook must not crash or exit non-zero.
run_hook 0 "malformed settings.json does not crash the hook"
teardown

# 15. CC_DPSD_SETTINGS env var redirects the settings file location.
setup
ALT="$SBX/alt-settings.json"
cat > "$ALT" <<'JSON'
{ "enabledPlugins": { "alt@bar": false } }
JSON
mkdir -p "$SBX/.claude/plugins/cache/alt"
echo '{ "alt-server": {} }' > "$SBX/.claude/plugins/cache/alt/.mcp.json"
run_hook_stderr_contains "alt@bar" "CC_DPSD_SETTINGS overrides the settings path" \
    CC_DPSD_SETTINGS="$ALT"
teardown

# 16. App Support path absent (Linux-only host) — no crash, normal pass.
setup
rm -rf "$SBX/Library"
cat > "$SBX/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "foo@bar": false } }
JSON
run_hook 0 "missing App Support path does not crash on Linux"
teardown

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
