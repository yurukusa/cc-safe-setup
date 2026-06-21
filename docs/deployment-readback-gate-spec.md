# deployment-readback-gate — Spec

**Status:** design spec (generic decision logic + provider-adapter contract). Tracks issue [#313](https://github.com/yurukusa/cc-safe-setup/issues/313). Receipt schema refined with [@caioribeiroclw-pixel](https://github.com/caioribeiroclw-pixel).

**Audience.** Operators whose Claude Code sessions perform or narrate deployments, and anyone landing here after [anthropics/claude-code#61699](https://github.com/anthropics/claude-code/issues/61699) (model claimed "deployment complete" while the actual deployment state diverged from the claim).

## What this defends against

This is the **Mode 4 (claim-verify gap)** failure from the [sub-agent failure-mode map](./sub-agent-failure-modes-hook-map.md), narrowed to **deployment-completion claims**: the model asserts a deploy succeeded, but the deployment authority (the CI/CD registry, `gh` deployments API, platform API) says otherwise — or was never queried at all. Unlike a narrative log, this gate turns the claim into a **refusable, auditable trust artifact**.

It is distinct from the two existing deploy hooks, and composes with them:

| Hook | Layer | Question it answers |
|------|-------|---------------------|
| `deploy-guard.sh` | PreToolUse (Bash) | "Are there uncommitted changes that will silently revert?" (before deploy) |
| `deploy-path-verify-guard.sh` | PreToolUse (Bash/Write) | "Is the deploy target path actually the mounted one?" (host-vs-container) |
| **deployment-readback-gate** | **Stop** | **"Did the authority actually confirm this deploy, recently?" (after the claim)** |

## Architecture (per #313)

Two layers, so the gate stays provider-agnostic:

- **Provider adapters** (per authority: `gh` deployments, Vercel, Cloud Run, k8s, …) own the readback. Each adapter returns a *normalized* shape: `{ authority, queried_ref, queried_state, readback_time, stale_if_older_than_ms }`. The adapter is the only part that knows the provider's API.
- **The generic Stop hook** consumes the normalized receipt and computes one decision: `allow | refuse-mismatch | refuse-query-failure`. It contains no provider knowledge, so a new authority is added by writing an adapter, never by touching the gate.

The **receipt schema is the stable contract** — not the hook. CI/audit tooling downstream consumes the receipt JSON, and because the receipt is written outside the transcript, the audit unit ("which authority said what, and whether it was fresh") survives even if the session's narrative is lost or rewound.

## Receipt schema (required fields)

```json
{
  "claim_span": "deployment complete for api@abc123",
  "claim_time": "2026-06-16T03:40:00.000Z",
  "target": "api/production",
  "claimed_ref": "abc123",
  "authority": "github_deployments_api",
  "readback_query": "repos/:owner/:repo/deployments?ref=abc123&per_page=1 + statuses",
  "queried_ref": "abc123",
  "queried_state": "success",
  "readback_time": "2026-06-16T03:39:58.000Z",
  "decision": "allow | refuse-mismatch | refuse-query-failure",
  "stale_if_older_than_ms": 300000
}
```

`authority`, `readback_time`, and `stale_if_older_than_ms` are **required, not optional** — without them the receipt cannot be debugged once hooks are routed through MCP gateways / shared harnesses, which is the whole reason for the gate. `readback_time` must come from the **authority's own response** (the deployment/status `created_at`), not from when the hook ran.

## Decision logic

1. **`refuse-query-failure` — fail closed.** If the authority is unreachable or the readback errors, **refuse**. Never coerce an unestablished truth into `allow` ("couldn't check, assume fine"). This is a *distinct incident class* from a mismatch: `refuse-query-failure` means *truth was never established* (the claim might have been correct); `refuse-mismatch` means *truth was established and the claim was wrong*. The receipt preserves the difference for the post-incident reviewer.
2. **`refuse-mismatch`.** Refuse if `queried_ref != claimed_ref` **or** `queried_state != success`.
3. **Staleness — anchored to the claim, not wall-clock.** Refuse if `claim_time - readback_time > stale_if_older_than_ms`. A cached or replayed "success" readback from an hour ago must not be allowed to ratify a claim made now. Anchoring to `claim_time` and sourcing `readback_time` from the authority's response closes the replay gap where a harness re-serves a prior successful readback.
4. **`allow`** only when the readback is fresh **and** matching **and** `success`.

## Implementation status

- [x] Generic Stop-hook decision function (pure: normalized receipt → decision). Shipped as [`examples/deployment-readback-gate.sh`](../examples/deployment-readback-gate.sh) — covers all four branches (`allow`, `refuse-mismatch`, `refuse-query-failure`, `refuse-stale`), fails closed on an unauditable receipt, anchors staleness to the claim, and writes the decided receipt outside the transcript.
- [x] Tests — [`tests/test-deployment-readback-gate.sh`](../tests/test-deployment-readback-gate.sh), 10 cases (all branches + missing-field + unparseable-time + receipt-written), all passing.
- [x] settings.json install snippet (Stop hook) — see the hook header.
- [x] `gh` deployments adapter (first provider) — [`examples/deployment-readback-gh-adapter.sh`](../examples/deployment-readback-gh-adapter.sh). Detects a deployment-completion claim in the Stop closeout (configurable phrase list, with benign-context exclusion so "deployed locally" / "about to deploy" do not trip it), reads the GitHub Deployments API for that ref/environment, and emits the normalized receipt on stdout — piped into the gate. `readback_time` is sourced from the deployment **status** `created_at` (the authority's own timestamp), and unreachable/erroring queries emit `queried_state: "query-failure"` so the gate fails closed. Tests: [`tests/test-deployment-readback-gh-adapter.sh`](../tests/test-deployment-readback-gh-adapter.sh), 26 cases (claim detection, all gate branches via the real gate, strict/advisory target resolution, ref parsing), GitHub API mocked for determinism.

Install (adapter piped into the gate):

```json
{ "hooks": { "Stop": [{ "hooks": [{ "type": "command",
  "command": "~/.claude/hooks/deployment-readback-gh-adapter.sh | ~/.claude/hooks/deployment-readback-gate.sh",
  "env": { "DRG_REPO": "owner/repo", "DRG_ENVIRONMENT": "production" } }] }] } }
```

The generic decision function is the safe place to start because it is deterministic and provider-free; adapters are added incrementally without changing it — the `gh` adapter above is the first, and Vercel / Cloud Run / k8s adapters follow the same output contract.

---

*Credit: receipt-authority + staleness design from [@caioribeiroclw-pixel](https://github.com/caioribeiroclw-pixel) in #313. Motivating incident: anthropics/claude-code#61699.*
