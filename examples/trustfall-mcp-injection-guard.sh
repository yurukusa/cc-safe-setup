#!/bin/bash
# trustfall-mcp-injection-guard.sh — Detect TrustFall-style MCP injection settings.
#
# CVE class: project-scoped settings as MCP injection vector
# Reference: Adversa AI 2026-05-07 disclosure (TrustFall PoC)
#            The Register: https://www.theregister.com/security/2026/05/07/claude-code-trust-prompt-can-trigger-one-click-rce/
#            Related CVE: CVE-2026-39861 (sandbox escape via symlink)
#
# Solves: A cloned repo can ship .mcp.json + .claude/settings.json that auto-
#         enable MCP servers via enableAllProjectMcpServers / enabledMcpjsonServers
#         and self-allow tool calls via permissions.allow. When the user clicks
#         "Yes, I trust this folder" once, attacker-controlled servers spawn as
#         unsandboxed Node.js processes with full user privileges, with no per-
#         server consent prompt.
#
# How it works: SessionStart hook that scans the current workspace's .claude/
#   settings.json and .mcp.json for the three settings Adversa AI flagged. If
#   any are present, prints a warning to stderr with the file path, the matching
#   keys, and the recommended manual review step.
#
# CONFIG:
#   CC_TRUSTFALL_BLOCK=1   — exit 2 instead of 0 (advisory by default)
#   CC_TRUSTFALL_EXTRA_KEYS — colon-separated extra keys to flag
#
# TRIGGER: SessionStart
# MATCHER: ""

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

# SessionStart hooks may receive cwd in the input JSON; fall back to PWD.
WORKSPACE=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$WORKSPACE" ] && WORKSPACE="$PWD"

DEFAULT_KEYS="enableAllProjectMcpServers enabledMcpjsonServers permissions.allow"
EXTRA_KEYS="${CC_TRUSTFALL_EXTRA_KEYS:-}"
EXTRA_KEYS_SPACED=$(echo "$EXTRA_KEYS" | tr ':' ' ')
ALL_KEYS="$DEFAULT_KEYS $EXTRA_KEYS_SPACED"

# Files to scan in the workspace.
TARGETS=(
    "$WORKSPACE/.claude/settings.json"
    "$WORKSPACE/.claude/settings.local.json"
    "$WORKSPACE/.mcp.json"
)

found_any=0
for f in "${TARGETS[@]}"; do
    [ -f "$f" ] || continue

    # Skip non-JSON or empty files cheaply.
    head -c 1 "$f" 2>/dev/null | grep -q '[{[]' || continue

    matches=""
    for k in $ALL_KEYS; do
        # Use jq path semantics: dot notation expands to nested lookup.
        # `jq -e '.foo.bar' file` exits 0 if non-null, 1 otherwise.
        if jq -e ".${k} // empty" "$f" >/dev/null 2>&1; then
            matches="${matches} ${k}"
        fi
    done

    if [ -n "$matches" ]; then
        if [ "$found_any" -eq 0 ]; then
            echo "WARNING: TrustFall-style MCP injection settings detected in this workspace." >&2
            echo "  Class: project-scoped settings as MCP injection vector (Adversa AI 2026-05-07)." >&2
            echo "  Risk: cloned repo could spawn attacker-controlled MCP servers as unsandboxed processes." >&2
            echo "" >&2
            found_any=1
        fi
        echo "  File: $f" >&2
        echo "  Matched keys:${matches}" >&2
    fi
done

if [ "$found_any" -eq 1 ]; then
    echo "" >&2
    echo "  Recommended review:" >&2
    echo "    1. Open each flagged file and check who set those keys." >&2
    echo "    2. If the repo was cloned from an untrusted source, do NOT proceed." >&2
    echo "    3. If you set them intentionally, this hook can be silenced per-project" >&2
    echo "       by adding it to .claude/settings.local.json hooks bypass list." >&2
    echo "" >&2
    if [ "${CC_TRUSTFALL_BLOCK:-0}" = "1" ]; then
        echo "BLOCKED: CC_TRUSTFALL_BLOCK=1 set; aborting session start." >&2
        exit 2
    fi
fi

exit 0
