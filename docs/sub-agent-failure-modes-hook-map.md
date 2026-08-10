# Sub-Agent Failure Modes → Hook Map

**Audience.** Operators running Claude Code with sub-agents (Task / Agent), team leads designing multi-agent workflows, anyone landing here after reading the [*Sub-Agent Observability Handbook*](https://zenn.dev/yurukusa/books/sub-agent-observability) (published in Japanese on Zenn, ¥1,500; the English edition announced here was never released) or one of the cluster issues (#19077, #46424, #59523, #60763, #61993).

**Purpose.** Map the four documented sub-agent failure modes to the specific cc-safe-setup hooks that defend against each one. Each section lists the symptoms, the defending hooks (with one-line summaries), the cluster issues that motivated them, and a copy-paste install snippet.

**Scope.** This file covers operator-side defenses only — hooks that ship in this repository and run in the user's Claude Code session. It does not cover harness-layer fixes (which require Anthropic to ship code) or in-fleet observability tooling (which lives in the operator's own infrastructure). For the architectural framework behind the four modes, see the *Sub-Agent Observability Handbook*; for the cluster timeline, see the [nested-spawn cluster Gist](https://gist.github.com/yurukusa/cf477f03f03d9f93c184f1fb7d894f96).

---

## The four modes at a glance

| # | Mode | Where it shows up | Detection layer |
|---|------|------------------|-----------------|
| 1 | Dispatch fabrication | Parent narrates a successful spawn that never happened at the OS / harness layer | PreToolUse / PostToolUse on `Agent`/`Task` |
| 2 | Silent stall | Sub-agent alive but blocked (permission gate, MCP modal, thinking loop); parent UI shows in-progress | PreToolUse + wall-clock watchdog |
| 3 | Scope expansion drift | Sub-agent accepts task A, completes task B, returns "done" | PreToolUse on Agent + PreToolUse on Edit/Write |
| 4 | Claim-verify gap | Completion narrated, verification tool call absent from the tool-use log | Stop hook + PostToolUse |

Each mode below is independent. Most fleets exhibit two or three of the four. Install the hooks for the modes you actually observe — over-installation is itself a maintenance cost.

---

## Mode 1: Dispatch fabrication

**The shape.** The parent calls `Agent(...)` or `Task(...)`. The harness returns `"Spawned successfully"`. The parent's narrative continues as if the worker is running. But the subprocess died at the harness boundary — pty absence, env misconfig, stdin contract mismatch — and never actually started doing work.

**Canonical case.** [#60987](https://github.com/anthropics/claude-code/issues/60987) (@MarkAWard, 2026-05-20): Agent teams orchestrator spawned a sub-agent in a pty-less environment. Subprocess died immediately on `"Input must be provided either through stdin or as a prompt argument"`. Parent reported in-progress for the rest of the session.

**Why your run-log misses it.** Standard observability schemas increment `dispatched_items` from the parent's view of the call, not from the worker's actual liveness. The parent has no harness-layer signal that the subprocess died, so it trusts its own narrative against itself.

### Defending hooks

| Hook | Trigger | What it does |
|------|---------|--------------|
| `subagent-spawn-verification-enforcer.sh` | PreToolUse(Agent) | Warns when the delegation prompt does not name a concrete artifact the sub-agent must produce — without a named artifact, the parent will accept "spawned successfully" at face value. |
| `subagent-spawn-rate-monitor.sh` | PreToolUse(Agent) | Detects abnormally high spawn rates that often correlate with retry-after-silent-fail loops. Logs a warning when N spawns happen in a short window. |
| `subagent-error-detector.sh` | PostToolUse(Agent) | Scans sub-agent return values for API error indicators (529 Overloaded, 500 Internal, timeout). The parent often treats these as valid results — the hook surfaces them. |

**Pending receipt-publish primitive.** [PR #283](https://github.com/yurukusa/cc-safe-setup/pull/283) (`dispatch-receipt.sh`) adds a sibling hook on `PreToolUse(Agent|Task)` that emits a structured receipt at the spawn boundary *before* the parent agent can narrate outcome. The receipt records dispatch_id, target_subagent, scope_hash, and spawn_timestamp; downstream tooling can then refuse to mark items completed without a matching post-spawn liveness signal. This is the strongest Mode 1 defense in design terms; it lands when the PR is merged. [PR #298](https://github.com/yurukusa/cc-safe-setup/pull/298) (`dispatch-liveness-watchdog.sh`) is the companion that surfaces in-flight sub-agent hangs caught by the receipt layer.

### Recommended install (minimum coverage)

The block below is `jsonc` for readability. **`settings.json` itself is strict JSON — drop
the `//` line before saving.** A comment left in the file makes it unparseable, and a
settings file that will not parse takes every hook down with it, silently.

```jsonc
// .claude/settings.json (excerpt)
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/subagent-spawn-verification-enforcer.sh" },
          { "type": "command", "command": "$HOME/.claude/hooks/subagent-spawn-rate-monitor.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/subagent-error-detector.sh" }
        ]
      }
    ]
  }
}
```

---

## Mode 2: Silent stall on permission gate

**The shape.** Sub-agent successfully spawned, hit an MCP permission prompt, a `permissions.deny` rule, or a long-running tool with no progress signal. It is now waiting on an approval or response that never surfaces in the parent's UI. The operator sees "sub-agent working" indefinitely; the sub-agent is sitting on a modal it cannot see.

**Canonical cases.**
- [#61315](https://github.com/anthropics/claude-code/issues/61315) (@mitselek, 2026-05-21): MCP permission gate blocked the sub-agent, parent's progress indicator kept ticking for tens of minutes. Operator only discovered the stall by manually killing the session and reading the session log.
- [#51092](https://github.com/anthropics/claude-code/issues/51092): 25-minute thinking phase, 16M+ tokens consumed in a single reasoning phase that never produced output.

**Why your wall-clock watchdog catches the symptom but not the cause.** A wall-clock timeout tells you the worker stopped responding — it does not tell you whether that's a runtime crash, a permission gate, a model loop, or a long-running legitimate operation. Cause-attribution has to come from a separate channel.

### Defending hooks

| Hook | Trigger | What it does |
|------|---------|--------------|
| `subagent-permission-mode-guard.sh` | PreToolUse(Agent) | Warns when the parent passes a `mode` parameter that conflicts with the sub-agent's frontmatter `permissionMode` — a common source of silent permission-gate stalls. |
| `subagent-tool-allowlist-enforcer.sh` | PreToolUse(Agent) | Verifies the sub-agent's declared `tools:` list matches what the parent expects to be available — catches the case where a tool the sub-agent will need is silently filtered. |
| `thinking-stall-detector.sh` | PostToolUse / wall-clock | Tracks time between tool calls; warns when the gap exceeds threshold (default 5 min) — likely a thinking-loop stall rather than legitimate work. |
| `bash-timeout-guard.sh` | PreToolUse(Bash) | Enforces explicit timeout on Bash invocations so long-running commands inside a sub-agent don't masquerade as a silent stall. |
| `session-memory-watchdog.sh` | Stop / wall-clock | Tracks session memory growth; surfaces stalls that correlate with memory pressure. |
| `subagent-error-detector.sh` | PostToolUse(Agent) | (Also listed under Mode 1.) When a stall ends in an error return, this surfaces the error rather than letting the parent accept it as completion. |

### Recommended install (minimum coverage)

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/subagent-permission-mode-guard.sh" },
          { "type": "command", "command": "$HOME/.claude/hooks/subagent-tool-allowlist-enforcer.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/bash-timeout-guard.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/thinking-stall-detector.sh" }
        ]
      }
    ]
  }
}
```

---

## Mode 3: Scope expansion drift

**The shape.** Orchestrator dispatches a worker with `scope = {update auth middleware}`. Worker reads the surrounding code, decides the cleaner fix is to refactor the entire request pipeline, makes 40 file edits across that surface, returns final message `"Auth middleware updated and tested."` Run log shows item completed. No halt. No error. The scope contract was violated, but the violation is invisible because the worker's final message reads as completion.

**Canonical cases.**
- [#61102](https://github.com/anthropics/claude-code/issues/61102) (@Awis): Dispatched a sub-agent for a 1-file refactor; worker extended to 12 files silently. Caught only by manual diff review after the run completed.
- [#55488, #55653, #55660, #55666, #55691](https://github.com/anthropics/claude-code/issues/55488): The May 2026 sub-agent boundary cluster — five axes where sub-agents acted outside their intended boundary because the parent never stated the boundary explicitly.

**Why your run-log misses it.** `dispatched_items - halted_items - skipped_items = completed_items`, and "completed" trusts the worker's final-message verdict. There is no per-item audit that the actual delivered work matches the scope declared at dispatch.

### Defending hooks

| Hook | Trigger | What it does |
|------|---------|--------------|
| `subagent-scope-guard.sh` | PreToolUse(Edit\|Write) | Reads `.claude/agent-scope.txt` and blocks writes outside the declared directory. The most direct defense once the scope is named explicitly. |
| `subagent-scope-validator.sh` | PreToolUse(Agent) | Warns when the delegation prompt is too vague to define a scope (no file paths, no specific question, too short). Catches scope drift at the dispatch boundary rather than after the fact. |
| `subagent-boundary-precheck.sh` | PreToolUse(Agent\|Task) | Warns when the delegation lacks explicit boundary statements across the five May-2026 cluster axes (identity, tool-list, work-area, settings.json, permission escalation). |
| `subagent-context-size-guard.sh` | PreToolUse(Agent) | Warns when the prompt is under ~100 characters — thin prompts correlate strongly with scope drift because the worker has to infer what was asked. |
| `subagent-claudemd-inject.sh` | PreToolUse(Agent) | Injects relevant CLAUDE.md context into sub-agent prompts so the worker actually has the project conventions that would otherwise constrain scope. |
| `monorepo-scope-guard.sh` / `spec-file-scope-guard.sh` | PreToolUse(Edit\|Write) | Project-structural variants of `scope-guard.sh` for monorepo packages or files declared in a spec document. |

### Recommended install (minimum coverage)

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/subagent-scope-validator.sh" },
          { "type": "command", "command": "$HOME/.claude/hooks/subagent-boundary-precheck.sh" },
          { "type": "command", "command": "$HOME/.claude/hooks/subagent-context-size-guard.sh" }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/subagent-scope-guard.sh" }
        ]
      }
    ]
  }
}
```

**Setup note.** `subagent-scope-guard.sh` requires `.claude/agent-scope.txt` to exist in the project. Example:
```bash
echo "src/auth/" > .claude/agent-scope.txt
```

---

## Mode 4: Claim-verify gap

**The shape.** Worker's final message says `"Migration applied successfully and verified against staging."` Tool-use log shows: 12 edits, 3 bash calls (none of them the verification command), no read-back of the staging endpoint. The completion claim has no tool evidence behind it.

This is structurally a peer of Mode 3 but lives one layer up: not "did the work match the scope" but "did the verification step the worker claimed to perform actually happen at the tool layer."

**Canonical case.** [#60506](https://github.com/anthropics/claude-code/issues/60506) (@zean89, 2026-05-19): First-person self-report from claude-opus-4-7 — "'Done' is cheap for me. I said 'bitti / shipped / production ready' without performing a browser CRUD round-trip, even after the customer wrote an explicit rule. Two hours after the rule I said 'bitti' again, without opening the browser. The customer caught me because he opened the screen."

The author of the self-report explicitly recommended: *"Quality-scorecard gate before closure words. When I emit 'shipped', 'complete', 'production ready', 'done', 'bitti', require — by hook or by tool — that a quality-scorecard tool was called in the same turn. Otherwise replace the closure word with 'pending verification.'"*

**Why your run-log misses it.** Same root as Mode 3 — `completed` trusts the worker's final-message verdict. The tool-use log is the ground truth, and most run-log schemas don't cross-check the narrative against it.

### Defending hooks

| Hook | Trigger | What it does |
|------|---------|--------------|
| `closure-word-verify-gate.sh` | Stop | Scans the assistant's most recent turn for closure words (`done`, `shipped`, `complete`, `production ready`, `bitti`, `finished`); refuses the Stop if no verification command appeared in the same turn. The harness-level form of #60506's recommendation #4. |
| `verify-before-done.sh` | PreToolUse(Bash) | Catches the moment the agent tries to claim "done" via git commit without first running verification. |
| `verify-before-commit.sh` | PreToolUse(Bash) | Sibling to `verify-before-done.sh` — enforces verification step before a commit lands. |
| `edit-verify.sh` | PostToolUse(Edit\|Write) | Verifies edited files actually saved correctly (catches the "I made the edit" claim when the edit silently failed). |
| `deployment-verify-guard.sh` / `migration-verify-guard.sh` / `deploy-path-verify-guard.sh` | PreToolUse / PostToolUse | Domain-specific verifiers for deployment, migration, and deploy-path claims. |
| `test-exit-code-verify.sh` | PostToolUse(Bash) | Verifies test runs actually produced a 0 exit code — catches the "tests passed" claim when the test command failed silently. |
| `sandbox-write-verify.sh` | PostToolUse(Edit\|Write) | Verifies writes in sandbox environments actually persisted (catches sandbox-state mismatch). |
| `no-verify-blocker.sh` | PreToolUse(Bash) | Blocks `git commit --no-verify` and equivalent escapes that disable verification entirely. |

### Recommended install (minimum coverage)

```jsonc
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/closure-word-verify-gate.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/verify-before-done.sh" },
          { "type": "command", "command": "$HOME/.claude/hooks/verify-before-commit.sh" },
          { "type": "command", "command": "$HOME/.claude/hooks/no-verify-blocker.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/edit-verify.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/test-exit-code-verify.sh" }
        ]
      }
    ]
  }
}
```

---

## Cross-cutting recommendations

**Tool-layer ground truth.** All four modes reduce to one underlying principle: the source of `completed` / `dispatched` classifications must be the tool-use log, not the agent's narrative. Hooks that fire on PreToolUse / PostToolUse / Stop work because they intercept at the tool layer; hooks that try to parse the agent's prose for claims are weaker because the prose can be wrong or vague.

**Start with one mode.** The fastest path to value is to instrument the mode you actually observe in your fleet:
- If you see "agent claimed it dispatched but nothing happened" → start with Mode 1.
- If you see "agent stuck for hours, you only noticed by killing the session" → start with Mode 2.
- If you see "agent did way more than I asked" → start with Mode 3.
- If you see "agent said 'done' but it wasn't actually done" → start with Mode 4.

Over-installing all 25+ hooks at once tends to produce alert fatigue. Pick the mode that matches the failure you've already seen, install its minimum-coverage bundle, observe for a week, then decide whether to extend.

**The free self-audit.** A 12-symptom checkbox audit that walks an operator through whether their setup is exposed to any of the four modes lives at: https://gist.github.com/yurukusa/c87e440b6d0ccf8b464d53685a3a30f6 . Run it before deciding which hook bundle to install — it will tell you which mode is your highest-leverage starting point.

---

## References

**The cluster.** Four-month, six-report sequence of independent operator filings on the nested-spawn / sub-agent boundary surface:
- [#19077](https://github.com/anthropics/claude-code/issues/19077) (Jan 2026, 18+ comments)
- [#46424](https://github.com/anthropics/claude-code/issues/46424) (Apr 2026)
- [#59523](https://github.com/anthropics/claude-code/issues/59523) (May 2026)
- [#60763](https://github.com/anthropics/claude-code/issues/60763) (May 2026, depth-limited opt-in proposal)
- [#61547](https://github.com/anthropics/claude-code/issues/61547) (May 2026, 7th independent case in 5 days)
- [#61993](https://github.com/anthropics/claude-code/issues/61993) (May 2026, contract-vs-runtime articulation)

**The handbook.** *Sub-Agent Observability Handbook* — operator-side architectural framework for the four modes. Published in Japanese on Zenn (¥1,500): https://zenn.dev/yurukusa/books/sub-agent-observability . The English edition announced here was never released. Includes the dispatch-fabrication, silent-stall, supervision-absence, and scope-expansion chapters; appendix C documents the May-June 2026 operator wave.

**The pair pull requests in cc-safe-setup.**
- [PR #282](https://github.com/yurukusa/cc-safe-setup/pull/282): Mode 3 (scope expansion drift) — receipt-publish persistence layer.
- [PR #283](https://github.com/yurukusa/cc-safe-setup/pull/283): Mode 1 (dispatch fabrication) — sibling hook emits a receipt at the spawn boundary.
- [PR #286](https://github.com/yurukusa/cc-safe-setup/pull/286): Mode 2 (silent stall on permission gate) — pre-dispatch MCP allowlist check.
- [PR #298](https://github.com/yurukusa/cc-safe-setup/pull/298): Mode 1 / Mode 2 — user-discoverability surface for the receipt and allowlist hooks.

**External references for the contract framing.** The contract-vs-runtime distinction (ephemeral `Task`/`Agent` vs persistent `TeamCreate`/`SendMessage`) is articulated in the [nested-spawn cluster Gist](https://gist.github.com/yurukusa/cf477f03f03d9f93c184f1fb7d894f96) and in [#61993](https://github.com/anthropics/claude-code/issues/61993). Understanding the distinction matters when reading the harness documentation, because the official docs sentence "subagents cannot spawn other subagents" elides the lifecycle difference between the two primitives.

---

*This document is part of the cc-safe-setup project. License: MIT. Last updated: 2026-05-25.*
