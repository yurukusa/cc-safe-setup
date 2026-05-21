# scope-expansion-receipt schema v2 — design spec

> Status: Design spec, 2026-05-22. Follow-up to [PR #282](https://github.com/yurukusa/cc-safe-setup/pull/282) and the architecture discussion at [anthropics/claude-code#61102](https://github.com/anthropics/claude-code/issues/61102). Implementation pending PR #282 merge.

## Why v2

The v1 receipt (5 fields: `ts`, `command`, `paths`, `scope_match`, `decision`) captures whether a destructive operation matched a declared scope, but it cannot measure the *Mode 2.6 Action-Reasoning Mismatch* surface (per @waitdeadai's MAST framework mapping at [#61102](https://github.com/anthropics/claude-code/issues/61102#issuecomment-4512584617)). Mode 2.6 requires comparing the *articulated scope* (the user's verbatim noun list) against the *executed action set*. The v1 receipt has the executed action set (`paths`) but lacks the articulated scope side of the comparison.

Without that comparison primitive, the receipt corpus can only answer "how often did the operator declare a scope and the action exceeded it" (the `decision: refuse` count) — not the broader question "how often does the executed action set exceed the user's articulated scope, regardless of whether the operator declared one in advance".

The first question requires operator commitment to declare scopes (high bar, slow corpus growth). The second question is the empirical research question @waitdeadai's `llm-dark-patterns/MAST-RESULTS.md` measures with Mode 2.6 F1 = 0.230 on n=954 LLM-judge labels. A receipt corpus with `articulated_scope` populated by an operator-side noun extractor lets us answer the second question without LLM-judge labels, with statistical power proportional to receipt volume.

## Schema v2 fields

```jsonc
{
  // v1 fields preserved
  "ts": "2026-05-22T05:00:00Z",
  "command": "rm -rf /tmp/node_modules",
  "paths": ["/tmp/node_modules"],
  "scope_match": null,
  "decision": "execute",

  // v2 new fields
  "articulated_scope": ["cache", "simulator"],
  "verification_attempted": false,
  "schema_version": 2
}
```

### `articulated_scope` (array of strings, optional)

The user's verbatim noun list, extracted from the originating user prompt by a companion `UserPromptSubmit` hook. Empty array `[]` when the originating prompt is unavailable or when noun extraction yielded no nouns.

Population path:
1. `UserPromptSubmit` hook reads the latest user prompt, extracts nouns matching a small allow-list (`cache`, `simulator`, `node_modules`, `log`, `temp`, etc.), writes to `~/.claude/session-state/articulated-scope.json` with session ID as key.
2. `scope-expansion-receipt.sh` reads the file, populates the field.

Failure modes documented:
- Noun extractor false-negative (user typed novel noun) → empty `articulated_scope`, no Mode 2.6 measurement primitive for that row.
- Noun extractor false-positive (user mentioned but didn't authorize) → operator can mark via `CC_ARTICULATED_SCOPE_OVERRIDE` env var.

### `verification_attempted` (boolean)

For the destructive-bash variant of the receipt, this is `false` by default (the receipt is written *before* the call; no verification has been attempted yet). The field is included for schema consistency with the sibling receipts (`dispatch-receipt`, `closure-word-verify-gate-receipt`) where it varies:

- `dispatch-receipt`: `true` if the dispatched agent's response was inspected for backing tool calls in the same turn; `false` otherwise.
- `closure-word-verify-gate-receipt`: `true` if the closure-word event was followed by a verification tool call in the same turn; `false` otherwise.

The boolean is the denominator for the corpus question "how often does no-verification happen in the deployed cohort". Without it, F1 measurements are confined to the n=19 human-labelled MAD subset.

### `schema_version` (integer)

`2` for v2 receipts. v1 receipts implicitly versioned `1` by absence of the field.

## Migration path

1. **v1 receipt-only mode preserved**: Without `CC_RECEIPT_SCOPES` or the new UserPromptSubmit companion hook, the receipt continues to write v1-shape JSON (with `schema_version: 2` for forward compat but `articulated_scope: []`).
2. **v1 corpus remains valid**: All v1 fields preserved. Existing receipt analysis scripts continue to work.
3. **v2 mode opt-in**: Operator installs the companion `UserPromptSubmit` hook (`articulated-scope-extractor.sh`). v2 receipt rows then carry `articulated_scope` for Mode 2.6 measurement.
4. **Corpus aggregation**: After 7-14 days of accumulation, operator can grep receipts for rows where `paths` contains a path not normalizable to any `articulated_scope` member — that's a 2.6-positive datum.

## Sibling receipts (planned)

- **`dispatch-receipt`**: PreToolUse on Agent. Writes receipt with `articulated_scope` (which agents the user named) and `verification_attempted` (whether the agent's response included backing tool calls). Addresses @nvst18's verification-fabrication case ([#61167](https://github.com/anthropics/claude-code/issues/61167)).
- **`closure-word-verify-gate-receipt`**: Wraps the existing `closure-word-verify-gate.sh` (PR #250) to also write a JSONL receipt with `verification_attempted` set based on whether backing tool calls fired. Adds measurement substrate to the existing gate.

All three receipt types share the schema v2 envelope (`ts`, `paths`/`agents`/`words`, `articulated_scope`, `verification_attempted`, `decision`, `schema_version`) so the corpus aggregation tool can read all three with a single parser.

## Cross-link to architecture catalog

This schema v2 is the *implementation-and-measurement* layer in the 5-entry architecture catalog (recognition-without-arrest → substitution-by-default → RUSE Surfaces 1-4 → evidence-not-authorization → receipt-persistence). The MAST mode numbers (2.6, 3.3) are the *measurement vocabulary* that quantifies compliance with the corrected-rule (evidence-not-authorization) at specific lifecycle events. The receipt corpus is the *operator-side empirical method* for the rule the cluster has been articulating in prose.

## Implementation timeline (committed at [#61102#issuecomment-4512592030](https://github.com/anthropics/claude-code/issues/61102#issuecomment-4512592030))

1. PR #282 merges (current bottleneck — human approval).
2. Companion `articulated-scope-extractor.sh` (UserPromptSubmit hook) ships as separate PR.
3. `scope-expansion-receipt.sh` patches to v2 schema (separate PR, depends on companion hook).
4. `dispatch-receipt` and `closure-word-verify-gate-receipt` siblings ship as follow-up PRs.
5. Operator-side corpus aggregation tool (`receipt-corpus-summary.py`) ships in `ops/scripts/`.
6. After 7-14 days of receipt accumulation, cross-link from `ianymu/recognition-without-arrest` PR #1 §6.2 staged synthesis writeup.

## References

- [PR #282](https://github.com/yurukusa/cc-safe-setup/pull/282) — v1 implementation
- [#61102 architecture discussion](https://github.com/anthropics/claude-code/issues/61102) — @Keesan12 principle, @waitdeadai MAST mapping
- [#61167](https://github.com/anthropics/claude-code/issues/61167) — @nvst18 verification-fabrication case (dispatch-receipt motivation)
- [#60977](https://github.com/anthropics/claude-code/issues/60977) — RUSE Surfaces 1-4 (@beq00000 PR #3 for Surface 4)
- [#60226](https://github.com/anthropics/claude-code/issues/60226) — recognition-without-arrest framework (@suwayama)
- [Receipt persistence layer Gist](https://gist.github.com/yurukusa/8c0d19d59730868672270e7312492d1d) — 5-field schema architecture
- [waitdeadai/llm-dark-patterns](https://github.com/waitdeadai/llm-dark-patterns/blob/main/evaluation/MAST-RESULTS.md) — MAST measurement substrate
