# Writing your own hook: the detection-rule grammar

This repo ships 900+ deployable safety hooks. If one of them matches your problem, install it and move on — start from the [symptom search](https://yurukusa.github.io/cc-safe-setup/search.html), the [routing table in the README](../README.md), or the [starter pack](https://gist.github.com/yurukusa/825489b6bf73524e1df93facb4236351).

This page is for the *other* case: you hit a failure mode that **no existing hook covers**, and you want to write your own. The detection grammar is otherwise implicit in the hook sources — this is the documented path from "I see this dark pattern" to "here is a hook that detects it."

## The authoring methodology

The canonical write-up of *how the detection rules actually work* is **[@waitdeadai](https://github.com/waitdeadai)'s Hook Detection Rule Grammar field manual** — [gist](https://gist.github.com/waitdeadai/1716b66cb510a3f386be7ebf41006c51). It is the authoring-side companion to this repo's hook catalog. It documents:

- **The 3-layer detection stack** — *lexical* (regex over text), *structural* (position-aware parsed text), *semantic* (model / grammar judge). Pick the cheapest layer that produces an unambiguous answer.
- **The 4 rule-grammar primitives** every Stop-suite hook composes from:
  1. **Positive-match** — the trigger. A *closed, high-precision* token list, not a fuzzy pattern (e.g. `done|completed|shipped`, but **not** `good|fine`).
  2. **Negation / exclusion** — exonerates legitimate uses of the trigger, sourced from the surface forms operators actually use (`did not run`, `blocked`, `partial`), not a stylebook.
  3. **Evidence-allowlist** — is the positive claim *backed*? A positive verb is allowed only when paired with concrete, pluggable evidence.
  4. **Hedge-range** — exonerates honest uncertainty, arrests confident bluffing.
- **The false-positive economy** — hooks with an FP rate above ~5% on a representative corpus get disabled by operators within two weeks (and then they are *less* safe than with no hook). The 2–5% band is the tuning zone where precondition guards earn their keep. FP-rate is a safety property, not just a UX one.

Read that manual first if you are writing a new rule. It is Apache-2.0 and authored by waitdeadai, not by this repo.

## A worked example from this repo

[`deployment-readback-gate`](../examples/deployment-readback-gate.sh) + [`deployment-readback-gh-adapter`](../examples/deployment-readback-gh-adapter.sh) (issue [#313](https://github.com/yurukusa/cc-safe-setup/issues/313)) is a Stop hook that catches a false "deployment complete" claim. It maps cleanly onto all four primitives, including an **authority-readback variant of the evidence primitive**: instead of allowlisting a backticked tool name *inside* the text, the adapter goes out-of-band to the GitHub Deployments API and reads the truth from a structurally different source than the claim derives from.

A standalone write-up of that worked example, with the primitive-by-primitive mapping: [gist](https://gist.github.com/yurukusa/5e18c34bf124f8e0cc946798999c3ea1).

## How the two halves compose

Many failure modes need both layers:

- The **PreToolUse** hooks here gate *operations* at the tool boundary (before a destructive command runs).
- The **Stop**-suite hooks (this repo's receipt-and-refuse family, and waitdeadai's [`llm-dark-patterns`](https://github.com/waitdeadai/llm-dark-patterns)) gate *claims* at the closeout boundary (after the model asserts something).

Together they cover the plan→execute→verify surface: refuse the dangerous operation, *and* refuse the unbacked claim that it succeeded.

---

*The detection-rule grammar is [@waitdeadai](https://gist.github.com/waitdeadai/1716b66cb510a3f386be7ebf41006c51)'s. This page is a pointer/companion; corrections and expansions welcome as a PR.*
