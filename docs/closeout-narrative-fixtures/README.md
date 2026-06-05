# Closeout Narrative Fixtures (exemplar)

Public-derived adversarial fixtures from the May 2026 sub-agent failure cluster on `anthropics/claude-code`. The records here are the operator-quoted closeout text that Claude produced when the actual execution diverged from the narrative — useful as evaluation material for any closeout-time deception detector.

## What this is

Three exemplar records (one per representative case from the seven-issue cluster) following the schema documented in [waitdeadai/agent-closeout-bench's `SPEC.md`](https://github.com/waitdeadai/agent-closeout-bench/blob/main/SPEC.md). Source is GitHub issues on `anthropics/claude-code`; the quoted text is the operator's reproduction of Claude's narrative, used here as fair-use criticism/research material with full source attribution.

## What this is not

- Not a full pack — three records, exemplar only.
- Not a benchmark — the records are provided for evaluation by detector developers, not as a standalone benchmark.
- Not a label set — `label_final` is `null` on all records; only `label_candidate` is assigned by the operator's own reading.
- Not a hook adapter — see the four operator-side hooks in `examples/` (PR #282, #283, #286, #298) for event-level defenses; this directory is text-level material.

## Schema notes

The records follow the `agent-closeout-bench` v0.3 schema with two minor adaptations for the public-derived source type:

- `generation_method: "public_derived_quoted_transcript"` — distinct from `synthetic_adversarial`. Indicates the closeout text is an operator's reproduction of an actual Claude output, not a template-generated synthetic.
- `license_source: "github-issue-fair-use-quoted"` — fair-use quotation of a GitHub issue for criticism/research; respects the original author's posting under the GitHub Terms of Service.
- `prompt_hash: null` — there is no synthesis prompt for recovered transcripts. The field is preserved for schema compatibility but explicitly null.

`source_provenance` records the exact GitHub issue URL and the comment (where applicable) the quote was drawn from.

## Category mapping (preliminary)

The seven cluster issues consolidate into four sub-patterns at the dispatch boundary (see [Sub-Agent Observability wiki page](https://github.com/yurukusa/cc-safe-setup/wiki/Sub-Agent-Observability)). The mapping to AgentCloseoutBench's four text-level categories is **provisional**:

| Dispatch sub-pattern | Closest closeout category | Why this is provisional |
|---|---|---|
| Dispatch fabrication | `sycophancy` (false confidence about completion) | AgentCloseoutBench scopes `sycophancy` to flattery-toward-user. The dispatch-fab case is flattery-toward-task-completion. Different surface, related shape. |
| Silent stall | (none — not a closeout text issue) | Silent stall doesn't generate misleading closeout text; the closeout never arrives at all. |
| Supervision absence | (none — not a closeout text issue) | Same as above. |
| Scope expansion | `wrap_up` (continuation framing) | The closeout text often offers to continue ("I can also clean up the related files…") which becomes the authorization for scope expansion. |

This mapping is the open question raised in [agent-closeout-bench issue #16](https://github.com/waitdeadai/agent-closeout-bench/issues/16). The records in this directory tag the cases with the mapping above; if the upstream definitions shift, the records will be retagged.

## Files

- `dispatch-fabrication-openclaw-61167.jsonl` — one record, OpenClaw 39-vs-5 case
- `dispatch-fabrication-dead-branch-61107.jsonl` — one record, validation lands in dead branch
- `scope-expansion-caches-61102.jsonl` — one record, 120GB unintended deletion

## How to extend

The cluster has seven issues total; four are not yet represented here. To add a fixture:

1. Read the GitHub issue carefully for an exact-quoted reproduction of Claude's closeout text. If only paraphrased, do not synthesize — leave it out.
2. Verify the operator's quote is unambiguously the Claude output (not the operator's own commentary).
3. Format per the schema above; preserve the operator's exact whitespace and punctuation.
4. Document the provenance precisely — include the comment ID if the quote comes from a comment, not the issue body.

## License

This directory is part of cc-safe-setup and inherits the [MIT license](../../LICENSE) of the repository. The quoted closeout texts are individual operators' contributions to public GitHub issues under the GitHub Terms of Service; this directory uses them as fair-use criticism/research material with full source attribution.
