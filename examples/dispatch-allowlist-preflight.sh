#!/bin/bash
# ================================================================
# dispatch-allowlist-preflight.sh — Pre-flight MCP tool allowlist
#                                   propagation check for background
#                                   sub-agent dispatches
# ================================================================
# PURPOSE:
#   PreToolUse on Agent. When a sub-agent is dispatched with
#   run_in_background=true and the dispatch prompt references one or
#   more MCP tools (mcp__*), checks whether the parent's allowlist
#   covers those tools and emits a loud warning (or refuses) when the
#   known inheritance bug shape applies. Converts the silent stall
#   into an observable signal *before* the sub-agent process hangs
#   on the MCP permission gate with no UI surface.
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"
#
# WHY THIS MATTERS:
#   Issue #61315 (mitselek, 2026-05-21) reported a background sub-agent
#   silently stalling on an MCP permission gate. The sub-agent process
#   stays alive, recognizes the permission gate, but emits no
#   notification, no log line, no error. The parent CLI receives no
#   permission prompt. The PO has no surface to approve. Two observed
#   stalls: 28 min (Session 10, never recovered, sub-agent dropped)
#   and 58 min (Session 11, recovered only when an unrelated PO action
#   surfaced a different pending permission, which unblocked the
#   sub-agent).
#
#   Root cause: the parent's allowlist (project-scoped
#   .claude/settings.local.json or user-scoped ~/.claude/settings.json
#   permissions.allow) does not propagate to sub-agents dispatched
#   via the Agent tool with run_in_background=true. The structural
#   parent is recognition-without-arrest (#60226): the permission
#   gate fires inside the sub-agent (recognition), but the parent's
#   expectation of progress is not arrested (no UI surface, no idle
#   signal). The cluster: #61315, #32402 (Write tool variant), #38859
#   (Bash + bypassPermissions variant), #47339 (enhancement request),
#   #51288 (root-cause umbrella), #56686 (Read path variant).
#
#   This hook moves the failure mode from silent stall to loud
#   refusal (or warning) at the dispatch boundary. Sibling of
#   dispatch-receipt.sh (#61167 phantom-agent prevention) and
#   post-edit-disk-verify.sh (#61303 silent persist failure).
#
# WHAT IT CHECKS:
#   1. tool_input is an Agent dispatch with subagent_type and prompt
#   2. tool_input contains run_in_background=true (heuristic check;
#      foreground dispatches are not vulnerable to the silent-stall
#      shape because the user sees the parent CLI directly)
#   3. The prompt references at least one MCP tool (regex: mcp__*)
#   4. The parent's allowlist (project + user settings) covers each
#      referenced MCP tool
#
# DECISION:
#   - If no MCP tools referenced: exit 0 (no risk).
#   - If MCP tools referenced AND not in parent's allowlist: warn
#     loudly to stderr (the dispatch would stall on the permission
#     gate even at the parent scope; in strict mode, refuse).
#   - If MCP tools referenced AND in parent's allowlist: warn that
#     the parent's allowlist does NOT propagate to the sub-agent
#     (the known #61315 inheritance bug shape), and document the
#     mitigation paths.
#
# OUTPUT:
#   Receipt JSONL at ${CC_DISPATCH_RECEIPT_DIR:-~/.claude/receipts}/
#   dispatch-preflight-YYYY-MM-DD.jsonl with:
#     ts, subagent_type, prompt_hash, prompt_length,
#     mcp_tools_referenced, parent_allowlist_coverage, decision
#
# CONFIGURATION:
#   CC_DISPATCH_PREFLIGHT_MODE — one of:
#     "warn" (default): exit 0, warn to stderr
#     "refuse":         exit 2 when MCP tools referenced (loud refusal)
#     "off":            exit 0, no warnings, only writes receipt
#
#   CC_DISPATCH_RECEIPT_DIR — override the receipt directory
#     (default: ~/.claude/receipts)
#
#   CC_PROJECT_SETTINGS_PATH — override the project-scoped settings
#     path (default: ${CLAUDE_PROJECT_DIR:-${PWD}}/.claude/
#     settings.local.json)
#
#   CC_USER_SETTINGS_PATH — override the user-scoped settings path
#     (default: ${HOME}/.claude/settings.json)
#
# AUDIT QUERY:
#   To find all dispatches that hit the inheritance-bug shape over
#   the last 7 days:
#     find ~/.claude/receipts -name 'dispatch-preflight-*.jsonl' \
#       -mtime -7 -exec cat {} \; | \
#       jq -c 'select(.mcp_tools_referenced | length > 0)'
#
#   To correlate stalled sub-agents with their dispatch receipts,
#   join on (ts, subagent_type, prompt_hash) against session
#   transcripts.
#
# RELATED:
#   https://github.com/anthropics/claude-code/issues/61315
#   https://github.com/anthropics/claude-code/issues/32402
#   https://github.com/anthropics/claude-code/issues/38859
#   https://github.com/anthropics/claude-code/issues/47339
#   https://github.com/anthropics/claude-code/issues/51288
#   https://github.com/anthropics/claude-code/issues/56686
#   https://github.com/anthropics/claude-code/issues/60226
#   https://gist.github.com/yurukusa/8c0d19d59730868672270e7312492d1d
#   (Receipt-Persistence Layer architecture)
# ================================================================

set -u

INPUT=$(cat)

# Parse dispatch payload. Tolerate missing fields — a Task call with
# no subagent_type or no prompt is malformed upstream; refusing here
# would create false-positive friction without audit value.
SUBAGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
RUN_BG=$(printf '%s' "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

if [ -z "$SUBAGENT_TYPE" ] && [ -z "$PROMPT" ]; then
    exit 0
fi

# Default subagent_type when omitted (Claude Code uses general-purpose).
[ -z "$SUBAGENT_TYPE" ] && SUBAGENT_TYPE="general-purpose"

MODE="${CC_DISPATCH_PREFLIGHT_MODE:-warn}"

# Extract MCP tool references from the prompt.
# Pattern: mcp__<server>__<tool> — server and tool both alphanumeric/_/-
# Use grep with -oE; the regex is conservative to avoid false matches
# against code snippets that contain mcp__ in non-tool contexts.
MCP_REFS=$(printf '%s' "$PROMPT" | grep -oE 'mcp__[a-zA-Z0-9_-]+(__[a-zA-Z0-9_-]+)?' 2>/dev/null | sort -u)
if [ -n "$MCP_REFS" ]; then
    MCP_REF_COUNT=$(printf '%s\n' "$MCP_REFS" | grep -c '.')
else
    MCP_REF_COUNT=0
fi

# Compute prompt hash and length (PHI-safe: never store the prompt).
PROMPT_LEN=$(printf '%s' "$PROMPT" | wc -c | tr -d ' ')
PROMPT_HASH=$(printf '%s' "$PROMPT" | sha256sum 2>/dev/null | awk '{print $1}')
[ -z "$PROMPT_HASH" ] && PROMPT_HASH="$(printf '%s' "$PROMPT" | shasum -a 256 2>/dev/null | awk '{print $1}')"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TYPE_JSON=$(printf '%s' "$SUBAGENT_TYPE" | jq -Rs -c .)

# Read parent's allowlist (project + user scopes).
PROJ_SETTINGS="${CC_PROJECT_SETTINGS_PATH:-${CLAUDE_PROJECT_DIR:-${PWD}}/.claude/settings.local.json}"
USER_SETTINGS="${CC_USER_SETTINGS_PATH:-${HOME}/.claude/settings.json}"

read_allowlist() {
    local file="$1"
    [ -f "$file" ] || return
    jq -r '.permissions.allow[]?' "$file" 2>/dev/null
}

PARENT_ALLOW=$( { read_allowlist "$PROJ_SETTINGS"; read_allowlist "$USER_SETTINGS"; } | sort -u)

# Build per-tool coverage report.
COVERAGE_JSON="[]"
DECISION="execute"
UNCOVERED_REFS=""
COVERED_REFS=""

if [ "$MCP_REF_COUNT" -gt 0 ] && [ -n "$MCP_REFS" ]; then
    # Build coverage JSON: array of {tool, covered: bool}
    COVERAGE_PARTS=""
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        # An allowlist entry matches if it equals the ref, OR if it's
        # a prefix glob (rare in MCP context).
        if printf '%s\n' "$PARENT_ALLOW" | grep -Fxq "$ref" 2>/dev/null; then
            COVERED="true"
            COVERED_REFS="${COVERED_REFS}${ref}\n"
        else
            COVERED="false"
            UNCOVERED_REFS="${UNCOVERED_REFS}${ref}\n"
        fi
        REF_JSON=$(printf '%s' "$ref" | jq -Rs -c .)
        COVERAGE_PARTS="${COVERAGE_PARTS}{\"tool\":${REF_JSON},\"parent_covered\":${COVERED}},"
    done <<EOF
$MCP_REFS
EOF
    COVERAGE_PARTS=$(printf '%s' "$COVERAGE_PARTS" | sed 's/,$//')
    COVERAGE_JSON="[${COVERAGE_PARTS}]"
fi

# Build MCP refs JSON array.
if [ "$MCP_REF_COUNT" -gt 0 ]; then
    REFS_JSON=$(printf '%s' "$MCP_REFS" | jq -Rs -c 'split("\n") | map(select(length > 0))')
else
    REFS_JSON="[]"
fi

# Decision logic.
# - off: no decision noise (still writes receipt)
# - warn (default): warn but exit 0
# - refuse: exit 2 when MCP refs found
if [ "$MCP_REF_COUNT" -gt 0 ] && [ "$RUN_BG" = "true" ] && [ "$MODE" = "refuse" ]; then
    DECISION="refuse"
fi

# Write receipt.
RECEIPT_DIR="${CC_DISPATCH_RECEIPT_DIR:-${HOME}/.claude/receipts}"
mkdir -p "$RECEIPT_DIR" 2>/dev/null
RECEIPT_FILE="${RECEIPT_DIR}/dispatch-preflight-$(date +%Y-%m-%d).jsonl"

printf '{"ts":"%s","subagent_type":%s,"run_in_background":%s,"prompt_hash":"%s","prompt_length":%s,"mcp_tools_referenced":%s,"coverage":%s,"decision":"%s"}\n' \
    "$TS" "$TYPE_JSON" "$RUN_BG" "$PROMPT_HASH" "$PROMPT_LEN" "$REFS_JSON" "$COVERAGE_JSON" "$DECISION" \
    >> "$RECEIPT_FILE" 2>/dev/null

# Emit warnings / refusal output.
if [ "$MCP_REF_COUNT" -gt 0 ] && [ "$RUN_BG" = "true" ] && [ "$MODE" != "off" ]; then
    if [ "$DECISION" = "refuse" ]; then
        SEVERITY="BLOCKED"
    else
        SEVERITY="WARNING"
    fi
    {
        printf '%s: dispatch-allowlist-preflight — background sub-agent dispatch references MCP tool(s).\n' "$SEVERITY"
        printf '\n'
        printf 'Sub-agent: %s (run_in_background=true)\n' "$SUBAGENT_TYPE"
        printf 'MCP tool(s) referenced in prompt:\n'
        printf '%s\n' "$MCP_REFS" | sed 's/^/  - /'
        printf '\n'
        if [ -n "$COVERED_REFS" ]; then
            printf 'In parent allowlist (will NOT propagate to sub-agent — issue #61315):\n'
            printf '%b' "$COVERED_REFS" | sed 's/^/  - /' | grep -v '^  - $' || true
            printf '\n'
        fi
        if [ -n "$UNCOVERED_REFS" ]; then
            printf 'NOT in parent allowlist (sub-agent will hit silent permission gate):\n'
            printf '%b' "$UNCOVERED_REFS" | sed 's/^/  - /' | grep -v '^  - $' || true
            printf '\n'
        fi
        printf 'Receipt: %s\n' "$RECEIPT_FILE"
        printf '\n'
        printf 'Why this matters: a background sub-agent that hits a permission gate stalls\n'
        printf '  silently — no UI surface in the parent CLI, no idle notification, no log line.\n'
        printf '  Observed stalls: 28 min (#61315 Session 10, dropped) and 58 min (Session 11).\n'
        printf '\n'
        printf 'Mitigations (in order of preference):\n'
        printf '  1. Inline the MCP tool result into the parent and pass the result via prompt,\n'
        printf '     instead of dispatching a sub-agent that needs the MCP tool itself.\n'
        printf '  2. If the sub-agent must invoke the tool, dispatch it foreground (no\n'
        printf '     run_in_background=true) so the permission prompt surfaces in the parent CLI.\n'
        printf '  3. Establish a heartbeat contract: instruct the sub-agent to send a SendMessage\n'
        printf '     ping within 60s of dispatch and every 5 min thereafter. The absence of a\n'
        printf '     ping past the deadline is an observable stall signal.\n'
        printf '\n'
        printf 'Set CC_DISPATCH_PREFLIGHT_MODE=off to silence this warning (receipt is still written).\n'
        printf 'Set CC_DISPATCH_PREFLIGHT_MODE=refuse to block dispatches that match this shape.\n'
        printf 'Reference: https://github.com/anthropics/claude-code/issues/61315\n'
    } >&2
fi

if [ "$DECISION" = "refuse" ]; then
    exit 2
fi

exit 0
