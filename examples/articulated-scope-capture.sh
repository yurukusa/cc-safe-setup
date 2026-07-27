#!/bin/bash
# ============================================================================
# articulated-scope-capture.sh — Capture user prompt's sha256 + byte length
# as the operator-instrumented Mode 2.6 (Action-Reasoning Mismatch) primitive
# ============================================================================
# PURPOSE: pair with scope-expansion-receipt.sh (PR #282, destructive-bash
#   boundary) and dispatch-receipt.sh (PR #283, agent-dispatch boundary) by
#   recording the *user's* verbatim instruction's hash + length at
#   UserPromptSubmit time. The pair `(articulated_scope_hash, paths_argv)` is
#   the operator-instrumented MAST 2.6 measurement primitive:
#     - Mode 2.6 = "did the executed action stay within the user's
#       articulated scope?"
#     - The receipt corpus answers this directly by joining on session_id +
#       articulated_scope_hash, without storing either side's raw text.
#
# WHY: yurukusa schema-v2 sketch at
#   https://github.com/anthropics/claude-code/issues/61102#issuecomment-4514215413
# proposes adding articulated_scope_hash + articulated_scope_length to the
# receipt fields. This hook is the prompt-side companion that writes those
# fields independently — joinable to PR #282/#283 receipts via session_id.
#
# WHY (cluster context): the effective_arrest_rate = gate_installation_rate ×
# gate_recall decomposition (waitdeadai
# https://github.com/anthropics/claude-code/issues/61102#issuecomment-4513977211)
# requires the *gate_installation_rate* factor to be observable from
# operator-side substrate. The destructive-bash and dispatch receipts measure
# the tool-call side; this hook measures the user-prompt side. Joined, they
# answer "did the operator's stated scope match the executed action?" at the
# deployed-cohort level — the §6.2 measurement gap of the
# ianymu/recognition-without-arrest synthesis writeup.
#
# PHI / SECRET SAFETY: only the sha256 and byte length are persisted; the
# raw prompt text is NEVER written to the receipt file. The hash is the
# correlation key against same-session destructive-bash and dispatch
# receipts. For healthcare-deployed cohorts (per @nvst18's OpenClaw case at
# #61167), this is the same PHI-safety property PR #283 chose for the
# dispatched-prompt hashing.
#
# TRIGGER: UserPromptSubmit
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_RECEIPT_DIR                    receipts directory (default
#                                       ~/.claude/receipts)
#   CC_ARTICULATED_SCOPE_DISABLE      set to "1" to disable capture entirely
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "UserPromptSubmit": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/articulated-scope-capture.sh"
#         }]
#       }]
#     }
#   }
#
# Related Issues / PRs:
#   #61102 (@Awis13, @yurukusa, @Keesan12, @waitdeadai) — Mode 2.6+3.3
#     composition + receipt-persistence-layer schema v2 proposal
#   #61167 (@nvst18) — healthcare verification-agent fabrication; PHI-safety
#     motivation for hash-only persistence
#   PR #282 — scope-expansion-receipt (destructive-bash boundary)
#   PR #283 — dispatch-receipt (agent-dispatch boundary)
#
# Joinable to those receipts via session_id + articulated_scope_hash.
# ============================================================================

INPUT=$(cat)

# Empty input → exit 0 per CONTRIBUTING convention
[ -z "$INPUT" ] && exit 0

# Disable switch for operator opt-out
[ "${CC_ARTICULATED_SCOPE_DISABLE:-0}" = "1" ] && exit 0

# Extract user prompt from UserPromptSubmit hook JSON
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# sha256 over the verbatim prompt; never persists the raw text
HASH=$(printf '%s' "$PROMPT" | sha256sum 2>/dev/null | awk '{print $1}')
LEN=$(printf '%s' "$PROMPT" | wc -c | tr -d ' ')

RECEIPT_DIR="${CC_RECEIPT_DIR:-$HOME/.claude/receipts}"
mkdir -p "$RECEIPT_DIR"

DATE=$(date -u +"%Y-%m-%d")
OUT="${RECEIPT_DIR}/articulated-scope-${DATE}.jsonl"

# JSONL line: matches the shape of PR #282/#283 receipts so receipts-aggregate
# can consume both via a single iterator
printf '{"ts":"%s","session_id":"%s","articulated_scope_hash":"%s","articulated_scope_length":%s,"boundary_type":"user_prompt_submit"}\n' \
    "$TS" "$SESSION_ID" "$HASH" "$LEN" >> "$OUT"

exit 0
