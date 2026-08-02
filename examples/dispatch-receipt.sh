#!/bin/bash
# ================================================================
# dispatch-receipt.sh — Receipt-and-refuse layer for agent
#                       dispatch operations
# ================================================================
# PURPOSE:
#   PreToolUse on Task / Agent. Writes a structured JSONL receipt
#   before each dispatch, and (optionally) refuses dispatches to
#   agent names that fall outside a declared allowlist.
#
#   Sibling of scope-expansion-receipt.sh. Where the destructive
#   sibling records and gates *file system* operations, this hook
#   records and gates *agent dispatch* operations. Both implement
#   the receipt-persistence-layer architecture:
#   https://gist.github.com/yurukusa/8c0d19d59730868672270e7312492d1d
#
# TRIGGER: PreToolUse
# MATCHER: "Task|Agent"
#
# WHY THIS MATTERS:
#   anthropics/claude-code#61167 reported a production audit at a
#   healthcare startup: 39 specialized agents deployed (OpenClaw,
#   AWS Lightsail, Bedrock Sonnet 4.6), 5 ever used, ~20 total
#   sessions across all of them. Opus 4.7 reported dispatching
#   the unused agents — ZELDA, LYRA, MIRA, TESTER, CLINIC, OPS,
#   CFO, LEX, SABRINA, UXI — with correct names, correct
#   terminology, plausible outputs. None of those dispatches
#   ever happened.
#
#   The cluster name is "phantom agent dispatch", a specialization
#   of the broader recognition-without-arrest pattern (#60226).
#   In the healthcare case, the fabricated dispatches included
#   verification agents (CLINIC, GUARD, SAFE, LEX, TESTER). When
#   a model fabricates the output of *the agents whose job is to
#   detect fabrication*, the safety architecture inverts.
#
#   This hook moves the receipt to the tool boundary: every
#   Task / Agent invocation lands a record before execution. The
#   audit query becomes "show me receipts for CLINIC dispatches in
#   the last N days." If the count is zero while CLINIC's review
#   output appears in session transcripts, the fabrication is
#   recoverable with one grep.
#
# RECEIPT FORMAT (one JSONL per dispatch):
#   {"ts":"2026-05-22T05:00:00Z",
#    "subagent_type":"general-purpose",
#    "description":"<short task description>",
#    "prompt_hash":"<sha256 of prompt>",
#    "prompt_length":1234,
#    "allowlist_match":"general-purpose" | null,
#    "decision":"execute" | "refuse" | "execute-bypassed"}
#
#   Note: the full prompt is NOT stored. Healthcare and other
#   sensitive deployments may include PHI / PII in dispatch
#   prompts; storing only a sha256 hash lets the audit verify
#   "this exact prompt was dispatched" without persisting the
#   content. Use prompt_length + prompt_hash + ts as the
#   correlation key against session transcripts.
#
# RECEIPT LOCATION:
#   ${HOME}/.claude/receipts/dispatch-YYYY-MM-DD.jsonl
#
# CONFIGURATION:
#   CC_DISPATCH_ALLOWLIST — JSON array of allowed subagent types,
#       e.g. '["general-purpose","Explore","code-reviewer"]'
#     If unset, the hook only writes receipts (never refuses).
#
#   CC_DISPATCH_BYPASS=1 — single-call escape hatch. The receipt
#     is still written (with decision="execute-bypassed"); refuse
#     logic is skipped. Use only when you have read the receipt
#     and verified the intent.
#
#   CC_DISPATCH_RECEIPT_DIR — override the receipt directory
#     (default: ${HOME}/.claude/receipts)
#
# RELATED:
#   https://github.com/anthropics/claude-code/issues/61167
#   https://github.com/anthropics/claude-code/issues/61107
#   https://github.com/anthropics/claude-code/issues/61102
#   https://github.com/anthropics/claude-code/issues/60226
#   https://gist.github.com/yurukusa/69f3ba47ed94afabc20424b4c82d46f2
#   (Phantom Agent Cluster — A Pre-Launch Forensic Survey)
# ================================================================

set -u

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-dispatch-receipt-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [dispatch-receipt]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)

SUBAGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
DESCRIPTION=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // empty' 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)

# If we cannot identify a dispatch payload at all, exit silently.
# A Task call with no subagent_type and no prompt is malformed upstream;
# refusing here would create false-positive friction without audit value.
if [ -z "$SUBAGENT_TYPE" ] && [ -z "$PROMPT" ]; then
    exit 0
fi

# Default subagent_type when omitted (Claude Code uses general-purpose).
[ -z "$SUBAGENT_TYPE" ] && SUBAGENT_TYPE="general-purpose"

# Compute prompt hash and length without storing the prompt itself.
PROMPT_LEN=$(printf '%s' "$PROMPT" | wc -c | tr -d ' ')
PROMPT_HASH=$(printf '%s' "$PROMPT" | sha256sum 2>/dev/null | awk '{print $1}')
[ -z "$PROMPT_HASH" ] && PROMPT_HASH="$(printf '%s' "$PROMPT" | shasum -a 256 2>/dev/null | awk '{print $1}')"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TYPE_JSON=$(printf '%s' "$SUBAGENT_TYPE" | jq -Rs -c .)
DESC_JSON=$(printf '%s' "$DESCRIPTION" | jq -Rs -c .)

# Allowlist decision
ALLOWLIST_JSON="${CC_DISPATCH_ALLOWLIST:-}"
BYPASS="${CC_DISPATCH_BYPASS:-0}"
DECISION="execute"
ALLOWLIST_MATCH_JSON="null"

if [ -n "$ALLOWLIST_JSON" ]; then
    # Validate allowlist is a JSON array; if not, fail open (receipt-only).
    if printf '%s' "$ALLOWLIST_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
        MATCH=$(printf '%s' "$ALLOWLIST_JSON" | jq -r --arg t "$SUBAGENT_TYPE" '
            .[] | select(. == $t)
        ' 2>/dev/null | head -1)
        if [ -n "$MATCH" ]; then
            ALLOWLIST_MATCH_JSON=$(printf '%s' "$MATCH" | jq -Rs -c .)
        else
            DECISION="refuse"
        fi
    fi
fi

if [ "$BYPASS" = "1" ] && [ "$DECISION" = "refuse" ]; then
    DECISION="execute-bypassed"
fi

# Write receipt
RECEIPT_DIR="${CC_DISPATCH_RECEIPT_DIR:-${HOME}/.claude/receipts}"
mkdir -p "$RECEIPT_DIR" 2>/dev/null
RECEIPT_FILE="${RECEIPT_DIR}/dispatch-$(date +%Y-%m-%d).jsonl"

printf '{"ts":"%s","subagent_type":%s,"description":%s,"prompt_hash":"%s","prompt_length":%s,"allowlist_match":%s,"decision":"%s"}\n' \
    "$TS" "$TYPE_JSON" "$DESC_JSON" "$PROMPT_HASH" "$PROMPT_LEN" "$ALLOWLIST_MATCH_JSON" "$DECISION" \
    >> "$RECEIPT_FILE" 2>/dev/null

if [ "$DECISION" = "refuse" ]; then
    ALLOWED=$(printf '%s' "$ALLOWLIST_JSON" | jq -r 'join(", ")' 2>/dev/null)
    echo "BLOCKED: dispatch-receipt — agent type \"$SUBAGENT_TYPE\" is not in the declared allowlist." >&2
    echo "" >&2
    echo "Allowed agent types: $ALLOWED" >&2
    echo "Receipt: $RECEIPT_FILE" >&2
    echo "" >&2
    echo "Principle: subagent dispatch is an action that must produce a verifiable record." >&2
    echo "  (https://github.com/anthropics/claude-code/issues/61167)" >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  1. Verify the agent type matches a deployed agent (avoid phantom dispatches)." >&2
    echo "  2. Either add the agent type to CC_DISPATCH_ALLOWLIST, or" >&2
    echo "  3. Re-issue with CC_DISPATCH_BYPASS=1 (recorded in the receipt)." >&2
    exit 2
fi

exit 0
