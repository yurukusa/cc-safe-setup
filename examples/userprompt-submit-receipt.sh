#!/bin/bash
# ================================================================
# userprompt-submit-receipt.sh — Companion log for the operator's
#                                articulated scope at the prompt
#                                boundary, joinable to dispatch /
#                                bash / edit receipts
# ================================================================
# PURPOSE:
#   UserPromptSubmit hook. Writes a structured JSONL receipt of the
#   operator's verbatim prompt's sha256 hash and byte length to a
#   companion log file. The dispatch / bash / edit hooks in the
#   receipt-persistence-layer family read the most recent entry of
#   this log within the current session to populate
#   `articulated_scope_hash` and `articulated_scope_length` fields
#   in their own receipts.
#
#   The result is that the receipt corpus answers MAST 2.6
#   (Action-Reasoning Mismatch, Cemri et al. NeurIPS 2025
#   arXiv:2503.13657) operationally — the executed action vs the
#   operator's articulated scope at the prompt boundary — distinct
#   from the LLM-judge labelled definition that compares the model's
#   reasoning text against the model's final action. The cluster
#   discussion of this distinction is at:
#     https://github.com/anthropics/claude-code/issues/61102#issuecomment-4514215413
#
# TRIGGER: UserPromptSubmit
# MATCHER: (none — fires on every prompt)
#
# RECEIPT FORMAT (one JSONL per prompt):
#   {"ts":"2026-05-22T00:36:29Z",
#    "prompt_hash":"<sha256 of prompt>",
#    "prompt_length":1234,
#    "schema_version":1}
#
#   The prompt content itself is NEVER persisted. Only the hash and
#   length, so the receipt corpus stays PHI-safe and the
#   articulated-scope-mismatch measurement at downstream boundaries
#   operates on cryptographic correlation keys instead of text.
#
# RECEIPT LOCATION:
#   ${CC_DISPATCH_RECEIPT_DIR:-~/.claude/receipts}/
#   userprompt-submit-YYYY-MM-DD.jsonl
#
# DOWNSTREAM CONSUMERS:
#   - examples/dispatch-allowlist-preflight.sh (PR #286 / dispatch-start
#     boundary, schema v2)
#   - examples/dispatch-receipt.sh (PR #283 / dispatch-end boundary,
#     schema v2 when adopted)
#   - examples/scope-expansion-receipt.sh (PR #282 / scope-expansion
#     boundary, schema v2 when adopted)
#   - examples/post-edit-disk-verify.sh (PR #285 / Edit-Write boundary,
#     schema v2 when adopted)
#
#   Downstream hooks read the most recent line of this log within the
#   current day's file. For sessions that span midnight UTC, the
#   downstream hook reads from yesterday's file if today's is empty —
#   a refinement deferred to schema v2.1.
#
# CONFIGURATION:
#   CC_DISPATCH_RECEIPT_DIR — override the receipt directory
#     (default: ${HOME}/.claude/receipts)
#
#   CC_USERPROMPT_RECEIPT_OFF=1 — disable this hook entirely, useful
#     for sessions where the operator does not want the articulated
#     scope tracked (the downstream hooks then write
#     articulated_scope_hash: null in their receipts)
#
# AUDIT QUERY:
#   To join a dispatch receipt against the most recent prompt:
#     RECEIPTS=~/.claude/receipts
#     jq -c '. + {linked_articulated_scope:
#                  (input_filename | sub("dispatch-preflight-"; "userprompt-submit-")
#                                  | @sh "" + . + "" | $$(tail -1 .))}' \
#       "$RECEIPTS"/dispatch-preflight-2026-05-22.jsonl
#
#   In practice, the join is done by the `receipts-aggregate` CLI
#   that is the next load-bearing artifact in the cluster's
#   measurement infrastructure.
#
# RELATED:
#   https://github.com/anthropics/claude-code/issues/61102 (Awis case)
#   https://github.com/anthropics/claude-code/issues/61167 (nvst18 case)
#   https://github.com/anthropics/claude-code/issues/61315 (mitselek case)
#   https://github.com/waitdeadai/llm-dark-patterns (MAST measurement)
#   https://gist.github.com/yurukusa/8c0d19d59730868672270e7312492d1d
#   (Receipt-Persistence Layer architecture)
# ================================================================

set -u

if [ "${CC_USERPROMPT_RECEIPT_OFF:-0}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)

# The UserPromptSubmit hook input contains the verbatim prompt at
# .user_message or .prompt depending on the runtime version. Try both.
PROMPT=$(printf '%s' "$INPUT" | jq -r '.user_message // .prompt // empty' 2>/dev/null)

# If we cannot extract a prompt, exit silently — a malformed input
# would create false-positive friction without measurement value.
if [ -z "$PROMPT" ]; then
    exit 0
fi

# Compute hash and length without storing the prompt.
PROMPT_LEN=$(printf '%s' "$PROMPT" | wc -c | tr -d ' ')
PROMPT_HASH=$(printf '%s' "$PROMPT" | sha256sum 2>/dev/null | awk '{print $1}')
[ -z "$PROMPT_HASH" ] && PROMPT_HASH="$(printf '%s' "$PROMPT" | shasum -a 256 2>/dev/null | awk '{print $1}')"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Write receipt.
RECEIPT_DIR="${CC_DISPATCH_RECEIPT_DIR:-${HOME}/.claude/receipts}"
mkdir -p "$RECEIPT_DIR" 2>/dev/null
RECEIPT_FILE="${RECEIPT_DIR}/userprompt-submit-$(date +%Y-%m-%d).jsonl"

printf '{"ts":"%s","prompt_hash":"%s","prompt_length":%s,"schema_version":1}\n' \
    "$TS" "$PROMPT_HASH" "$PROMPT_LEN" \
    >> "$RECEIPT_FILE" 2>/dev/null

exit 0
