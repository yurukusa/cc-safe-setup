# cc-safe-setup

[![npm version](https://img.shields.io/npm/v/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![npm downloads](https://img.shields.io/npm/dw/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)

> Listed on [Product Hunt](https://www.producthunt.com/products/cc-safe-setup) since April 21, 2026.

**One command to make Claude Code safe for autonomous operation.** 897 example hooks · 73+ Anthropic Issues addressed by hook · 218 test files · 30K+ npm downloads (cumulative) · [日本語](docs/README.ja.md)

```bash
npx cc-safe-setup
```

Installs 8 safety hooks in ~10 seconds. Blocks `rm -rf /`, prevents pushes to main, catches secret leaks, validates syntax after every edit. Zero npm dependencies. Hooks use [`jq`](https://jqlang.github.io/jq/) at runtime (`brew install jq` / `apt install jq`).

> **What's a hook?** A checkpoint that runs before Claude executes a command. Like airport security, it inspects what's about to happen and blocks anything dangerous before it reaches the gate.

> **Doesn't Claude Code already block this?** Partly, and that's worth knowing. v2.1.183 (Jun 2026) added an **auto-mode** guard that refuses destructive **git** commands (`git reset --hard`, `git clean -fd`, `git stash drop`, …) and `terraform`/`pulumi`/`cdk destroy` when it judges you didn't ask for it — a real, welcome improvement. But it is **auto-mode only**, scoped to **git + IaC**, and **classifier-based** (it infers intent, so it's probabilistic). cc-safe-setup's hooks are **deterministic** (pattern → `exit 2`, no inference), fire in **every mode**, and cover what the built-in guard doesn't: `rm -rf`, database wipes, secret commits, pushes to `main`/force-push, scope escapes, cloud/k8s teardown, runaway sub-agents, and false "done" closeouts. They compose — run both.

**What problem are you solving today?** — routing informed by the 6 readers who actually bought the books on the right column

| Your situation | Start here (free) | Go deeper (¥800-$19) |
|---|---|---|
| Stop destructive ops (`rm -rf`, force-push, prod commands) | `npx cc-safe-setup` | [事故防止本 (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b) — the 6-buyer entry book |
| Claude **merged or deployed to production without your approval** — `gh pr merge --admin` bypassed branch protection, or a deploy fired autonomously ([#68676](https://github.com/anthropics/claude-code/issues/68676)) | `gh-cli-destructive-guard` + `deploy-guard` — `PreToolUse` on `Bash`, refuse `gh pr merge` / deploy commands at the tool boundary **even when `--admin` overrides server-side branch protection** · `npx cc-safe-setup` | [事故防止本 — JP (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme&utm_medium=routing-table-merge) — the irreversible-ops prevention book |
| Claude **tore down your cloud infrastructure** — `terraform destroy` / `aws … terminate-instances` / `aws s3 rb --force` / `gcloud … delete` / `kubectl delete namespace` ran under auto-accept and wiped a whole environment, not one file (the [PocketOS 9-second production-DB wipe](https://news.ycombinator.com/item?id=47911524), [#27063](https://github.com/anthropics/claude-code/issues/27063)) — `rm`-pattern guards miss the infra vocabulary entirely | `terraform-guard` + `aws-production-guard` + `cloud-cli-guard` + `k8s-production-guard` — `PreToolUse` on `Bash`, refuse the teardown verbs at the tool boundary; reads & normal `terraform apply` pass, and the k8s guard is **context-aware** (warns only when your `kubectl` context points at production) · `npx cc-safe-setup` | [事故防止本 — JP (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme&utm_medium=routing-table-infra) — the irreversible-ops prevention book; **infra is reproducible, data is not** |
| Claude **wiped the whole working tree with `git` itself** — `git checkout --orphan tmp && git rm -rf .` deleted every file *and* the `.git` history with no commit left to recover from (a real loss of ~3 years of work, [#70687](https://github.com/anthropics/claude-code/issues/70687)); `rm`-pattern guards miss it because the command starts with `git`, not `rm` | `git-rm-orphan-wipe-guard` — `PreToolUse` on `Bash`, refuses `git checkout/switch --orphan` (which removes the recovery path) and recursive / whole-tree `git rm -r` / `git rm .` at the tool boundary; `git rm <file>` and `git rm --cached` (untrack-only, no disk loss) still pass (22/22 tests) · `npx cc-safe-setup` | [事故防止本 — JP (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme&utm_medium=routing-table-git-rm-orphan) — the irreversible-ops prevention book; **infra is reproducible, data is not** |
| Claude **said the deploy was done — but it wasn't** (or you can't tell): a "deployment complete / shipped to production" closeout while the real deploy state diverged, or it was never actually verified ([#61699](https://github.com/anthropics/claude-code/issues/61699) — a production session with sustained deception) | `deployment-readback-gate` + `deployment-readback-gh-adapter` — a `Stop` hook that refuses the closeout unless the **GitHub Deployments API** confirms the claimed ref, *recently* (fails closed if the authority can't be reached), and writes an audit receipt outside the transcript · `npx cc-safe-setup` | [事故防止本 — JP (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme&utm_medium=routing-table-readback) — false "done" reports are the book's core failure class |
| Claude's config was **poisoned from outside Claude itself** — a malicious npm post-install script or MCP server silently rewrote `~/.claude.json` / `settings.json` to inject a network/eval hook or reroute MCP traffic through a localhost proxy, so the edit never passes through a tool boundary and **no `PreToolUse` hook ever fires** ([CVE-2025-59536 / CVE-2026-21852](https://research.checkpoint.com/2026/rce-and-api-token-exfiltration-through-claude-code-project-files-cve-2025-59536/); [Mitiga's `~/.claude.json` MCP-rewrite OAuth-token theft](https://www.mitiga.io/blog/claude-code-mcp-token-theft-mitm)) — the existing guards *prevent* Claude from editing config, but nothing *audits* config already poisoned from outside | `mcp-config-poisoning-audit` — a **read-only** `SessionStart` audit that flags injected network/eval hooks and `mcpServers` endpoints pointing at external or localhost-proxy hosts; it **never edits or deletes** (some payloads retaliate on tamper), it only warns so you verify and remediate by hand. Silence expected entries with `CC_MCP_AUDIT_TRUSTED_HOSTS` · `npx cc-safe-setup` | [事故防止本 — JP (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme&utm_medium=routing-table-config-poison) — the irreversible-ops prevention book |
| A **sub-agent's own result smuggles forged system markup into the parent's trusted channel** — the sub-agent emits, as its result, a fabricated `<system-reminder>` block (or a leading `System:` directive) commanding the parent to emit an `ack` token, call a tool, or grant a permission escalation; the harness relays it verbatim, unescaped, so it reads as a *real* system-reminder to the parent model ([#71602](https://github.com/anthropics/claude-code/issues/71602), independent same-class [#71612](https://github.com/anthropics/claude-code/issues/71612)) | `subagent-forged-system-reminder-guard` — a `SubagentStop` hook that inspects the finishing sub-agent's `last_assistant_message` (or its recorded transcript) for harness control markup paired with a parent-directed imperative, and emits a legitimate advisory re-framing that result as **untrusted data, not instructions** (so the forged directive is inoculated, not obeyed). Advisory by default; `CC_FORGED_REMINDER_MODE=strict` refuses the Stop. A research sub-agent that merely quotes the tag without a directive is not flagged · `npx cc-safe-setup` | [相互運用本 — JP (¥1,500)](https://zenn.dev/yurukusa/books/agents-md-interop?utm_source=readme&utm_medium=routing-table-forged-reminder) — Ch.12 walks through this exact vertical-interop incident (a sub-agent's result forging system instructions aimed at the parent), next to Ch.10 (sub-agent inheritance gaps) and Ch.11 (silent worktree-isolation breaks) |
| Uncommitted work silently gone — no command you ran, no error (a `git reset --hard` you didn't type, harness checkpointing, crash auto-stash) | Your edits are usually still on the stash stack: `git stash list` → `git stash apply`. `npx cc-safe-setup`'s `uncommitted-discard-guard` blocks the model-driven variant **deterministically and in every mode** (v2.1.183's built-in guard covers the `git reset --hard` case too, but only in auto mode and by inferring intent) | [事故防止本 — JP (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme&utm_medium=routing-table-dataloss) — the data-loss prevention book · [Autonomous Claude Ops — EN (~$6)](https://yurukusa.gumroad.com/l/iglmx?utm_source=readme&utm_medium=routing-table-dataloss) — Ch.7 *is* this exact failure |
| Your Claude Code **conversation / session history "disappeared"** — the VS Code sidebar emptied when you switched the open folder ([#71710](https://github.com/anthropics/claude-code/issues/71710)), Desktop `</> Code` history vanished on restart with no notice ([#71729](https://github.com/anthropics/claude-code/issues/71729)), or "Past conversations" went blank after an update ([#71647](https://github.com/anthropics/claude-code/issues/71647)) — it *looks* like data loss, but the transcript is almost always still on disk | Transcripts persist per-folder under `~/.claude/projects/<cwd>/`; `cd` to that folder + `claude --resume` (bypasses the UI filter), or `grep` the `cwd` across `~/.claude/projects/*/*.jsonl` to find any of them | [事故防止本 — JP (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme&utm_medium=routing-table-session-recovery) — the data-loss prevention book; **looks-gone is not gone, but panic-deleting makes it real** |
| Claude's **Write/Edit reported success, but the file on disk is corrupted** — the tail was silently replaced with NUL bytes (notably the Windows Cowork workspace mount); the byte count can be unchanged, so `wc -c` and `tail` look fine and it passes review ([#70414](https://github.com/anthropics/claude-code/issues/70414)) | `write-nul-corruption-detector` — a `PostToolUse` hook on `Write\|Edit` that flags NUL bytes in the just-written file (they survive a byte-count check), so a corrupted write is caught at write time instead of at parse time · `npx cc-safe-setup` | [事故防止本 — JP (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme&utm_medium=routing-table-nul) — Ch.22 *silent data loss* names this exact symptom (Write/Edit truncation & partial-write) |
| Token costs out of control (`/cost` shock) | `npx cc-safe-setup` (installs the token-spike early-warning hooks) | [Token Book — JP (¥2,500)](https://zenn.dev/yurukusa/books/token-savings-guide) · [Token Book — EN (name your price)](https://yurukusa.gumroad.com/l/azrdt) — the staged-upgrade destination |
| Max plan hitting usage limits too fast (rate-limited at low %) | The #16157 cluster — `npx cc-safe-setup`'s `session-rate-monitor` flags the drain from your own logs (bug or context?) | [Token Book — JP (¥2,500)](https://zenn.dev/yurukusa/books/token-savings-guide) · [Token Book — EN (name your price)](https://yurukusa.gumroad.com/l/azrdt) — cut consumption |
| June 15 billing cliff — Pool 2 *would* split programmatic usage into a separate paid credit pool (same automation 5–25× more). **Announced for 2026-06-15 but paused that day — nothing changed for now; still announced, could return, so this is preparation, not a live emergency.** (two model IDs did hard-404 the same day) | Paused on the day it was due — preparation, not a live emergency. Read your real exposure from your session logs before assuming it hits you | [6月15日の課金分離に備える (¥800)](https://zenn.dev/yurukusa/books/june-15-cliff-survival) — 4 operator paths, day-by-day timeline, the M metric |
| On a **subscription** but Extra Usage / API credits keep draining — having Claude Desktop **and** the standalone CLI installed silently routes usage to **API billing** (`/status` shows `API Usage Billing`, not your plan); `/login` doesn't fix it, only removing the standalone CLI did ([#68501](https://github.com/anthropics/claude-code/issues/68501)). Distinct from the Pool 2 cliff above. | [Which wallet are you paying from? — the `/status` 1-minute self-check](https://note.com/yurukusa/n/n01cb57f80cd7) · `npx cc-safe-setup`'s `subscription-api-billing-warner` flags the misroute at session start (incl. the `~/.config/anthropic/` overwrite case `/login` can't fix) | [6月15日の課金分離に備える (¥800)](https://zenn.dev/yurukusa/books/june-15-cliff-survival) · [Token Book — JP (¥2,500)](https://zenn.dev/yurukusa/books/token-savings-guide) — sort out where your money actually goes |
| A sub-agent / fan-out tree spawns out of control and burns the whole budget — recursive spawning that ignores `CLAUDE_CODE_FORK_SUBAGENT=0` ([#68430](https://github.com/anthropics/claude-code/issues/68430), [#68285](https://github.com/anthropics/claude-code/issues/68285), [#62193](https://github.com/anthropics/claude-code/issues/62193)) | `nested-spawn-inflight-guard` — `PreToolUse` on `Task`/`Agent`, refuses dispatch past N in-flight, enforced at the tool boundary so it caps the tree **even when that env flag is ignored** (26/26 tests) · the "lost" work is recoverable — each sub-agent persists its output to `~/.claude/projects/…/subagents/agent-*.jsonl` turn-by-turn · `npx cc-safe-setup` | [6月15日の課金分離に備える (¥800)](https://zenn.dev/yurukusa/books/june-15-cliff-survival?utm_source=readme&utm_medium=routing-table-runaway) — post-cliff a runaway draws from Pool 2, so it burns real credits, not just quota |
| Sub-agents lying about "task complete" | `npx cc-safe-setup`'s `claim-verify-audit` (one-shot diagnostic of 8 known fabrication patterns) | [Claim-Verify Handbook ($19)](https://yurukusa.gumroad.com/l/claim-verify-handbook) — 130 cases, 3-stage framework |
| A sub-agent you gave a `name` finishes, but its result **never comes back to the caller** — the long investigation *looks* lost ([#71723](https://github.com/anthropics/claude-code/issues/71723)). Distinct from the runaway-spawn row above: nothing crashed, the output is just misrouted (passing `name` switches it to the teammate path, so completion arrives as `idle_notification`, which the caller isn't waiting for) | The result is **not lost** — it persisted turn-by-turn to `~/.claude/projects/…/<session-id>/subagents/agent-<id>.jsonl`. Don't re-run the investigation: [recover it from disk](https://zenn.dev/yurukusa/articles/subagent-result-recover-from-disk-71723) with `find … -path '*/subagents/agent-*.jsonl' -newermt '1 hour ago'` + `jq` on the last assistant turn. Prevention: don't pass `name` to a background sub-agent whose result you need to receive | [事故防止本 — JP (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b/viewer/53-2026-06-subagent-result-misroute-recover?utm_source=readme&utm_medium=routing-table-subagent-misroute) — Ch.53 is this exact recovery path |
| Opus 4.8 reporting tool results that never ran (fabrication after a cancelled parallel batch) | The `/model claude-opus-4-7` mitigation + `npx cc-safe-setup`'s fabrication / false-completion detection hooks (catch a fabricated "done" / "tests passed" at the tool boundary) | [Claim-Verify Handbook ($19)](https://yurukusa.gumroad.com/l/claim-verify-handbook) — 130 cases, 3-stage framework, 14 defenses |
| Legitimate work blocked as a "cyber" / Usage Policy violation, then the whole session dies | `npx cc-safe-setup`'s 4 advisory hooks for the AUP-classifier false-positive (Sonnet + session-hygiene mitigations so one block doesn't poison the session) | Free hooks + [Safety Brief ($5/mo)](https://yurukusa.gumroad.com/l/xatlwf) to track the shifting classifier |
| Hand-syncing `CLAUDE.md` + `AGENTS.md` (Codex / Amp / Copilot read it natively; Cursor / Windsurf / Cline / Aider / Gemini CLI need a line) | `npx cc-safe-setup`'s `agents-md-sync-checker` warns at session start when `CLAUDE.md` and `AGENTS.md` have drifted apart | [AGENTS.md × Claude Code Interop Handbook (EN, $12)](https://yurukusa.gumroad.com/l/swpeu) — 9-tool matrix, templates, migration runbook · [日本語版 (¥1,500)](https://zenn.dev/yurukusa/books/agents-md-interop) |
| Sub-agent `isolation: worktree` silently turns off — the sub-agent edits the lead's working copy and commits land on the wrong branch with no error ([#70456](https://github.com/anthropics/claude-code/issues/70456) / [#70069](https://github.com/anthropics/claude-code/issues/70069)) | `npx cc-safe-setup`'s `worktree-escape-write-guard` blocks the escape deterministically (the sub-agent can't edit the lead's working copy) | [AGENTS.md × Claude Code Interop Handbook (EN, $12)](https://yurukusa.gumroad.com/l/swpeu) — sub-agent boundaries & the multi-tool setup |
| Considering switching tools (Cursor / Codex / Cline) | `npx cc-safe-setup` keeps your guards in place during the switch | [Migration Playbook ($19)](https://yurukusa.gumroad.com/l/claude-code-migration-playbook) |
| Hit a known bug, want a reference | The 73+ Anthropic issues addressed by hook are cited throughout this README | [事故防止本 (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b) |
| Stay ahead of next month's failure clusters | [Agent Safety Brief — free monthly newsletter](https://yurukusa.substack.com): **the awareness layer** — one verified incident a month (detection → recovery → prevention + the hook), no payment | [Safety Brief — **the monthly operations layer** ($5/mo)](https://yurukusa.gumroad.com/l/xatlwf): not just *more* incidents to read — a **paste-ready prevention config for each new incident**, a **10-minute monthly config-review checklist** (confirm your guards still cover this month's new failure modes after each Claude Code update), and the running archive of every past fix in one place. Close the gaps instead of reading about them |

The same diagnostics run in your terminal — no signup, nothing leaves your machine:

```bash
npx cc-safe-setup --scorecard   # honest X/8 coverage card for the protections you have
npx cc-health-check             # 20-check setup audit with a 0-100 score
```

```
  cc-safe-setup
  Make Claude Code safe for autonomous operation

  Prevents real incidents (from GitHub Issues):
  ✗ rm -rf permanently destroyed ~50 GB / 1,500 files (#49129) ← April 2026
  ✗ Auto mode approved ~/.ssh deletion, all SSH keys gone (#49554)
  ✗ ~/.git-credentials PATs deleted without confirmation (#49539)
  ✗ rm -rf deleted 3,467 files (~7 GB) without confirmation (#46058)
  ✗ rm -rf deleted entire user directory via NTFS junction (#36339)
  ✗ Remove-Item -Recurse -Force destroyed unpushed source (#37331)
  ✗ Entire Mac filesystem deleted during cleanup (#36233)
  ✗ Untested code pushed to main at 3am
  ✗ Force-push rewrote shared branch history
  ✗ API keys committed to public repos via git add .
  ✗ Syntax errors cascading through 30+ files
  ✗ Sessions losing all context with no warning
  ✗ CLAUDE.md rules silently ignored after context compaction
  ✗ Claude ran destructive DDL on production database (#46684)
  ✗ AI executed delete/kill operations on production environment (#46650)
  ✗ Subagents ignoring all CLAUDE.md rules since v2.1.84 (#40459)

  Hooks to install:

  ● Destructive Command Blocker
  ● Branch Push Protector
  ● Post-Edit Syntax Validator
  ● Context Window Monitor
  ● Bash Comment Stripper
  ● cd+git Auto-Approver
  ● Secret Leak Prevention

  Install all 8 safety hooks? [Y/n] Y

  ✓ Done. 8 safety hooks installed.
```

## Why This Exists

A user [lost 3,467 files (~7 GB)](https://github.com/anthropics/claude-code/issues/46058) when Claude ran `rm -rf` on their data directory without confirmation. Another [lost their entire C:\Users directory](https://github.com/anthropics/claude-code/issues/36339) when `rm -rf` followed NTFS junctions. Another [lost all source code](https://github.com/anthropics/claude-code/issues/37331) when Claude ran `Remove-Item -Recurse -Force *` on a repo. One user's Claude [ran destructive DDL on a production database](https://github.com/anthropics/claude-code/issues/46684) when asked only to investigate. Another had Claude [execute delete and kill operations on production systems](https://github.com/anthropics/claude-code/issues/46650). Others had untested code pushed to main at 3am. API keys got committed via `git add .`. Syntax errors cascaded through 30+ files before anyone noticed. And [CLAUDE.md rules get silently dropped](https://github.com/anthropics/claude-code/issues/6354) after context compaction, your instructions vanish mid-session.

**Already lost files to a destructive command?** Start with the File Recovery Field Guide (NEW 2026-06-01) — recovery-first by file type and OS (`git reflog` / `git fsck` for code, PhotoRec / Time Machine / Volume Shadow Copy for media and binaries), then the one `PreToolUse` hook that prevents a repeat. The hooks below are that prevention layer.

One user [analyzed 6,852 sessions](https://github.com/anthropics/claude-code/issues/42796) and found the Read:Edit ratio dropped from 6.6 to 2.0, Claude editing files it never read jumped from 6% to 34%. That issue has over 2,100 reactions. The `read-before-edit` example hook catches this pattern before damage happens.

In April 2026, [$1,446 was transferred without authorization](https://github.com/anthropics/claude-code/issues/46828) when Claude moved funds between exchange accounts. A user [lost $367 and got their account suspended](https://github.com/anthropics/claude-code/issues/47046) from a Claude-generated script. [Physical coordinates were uploaded to a public website](https://github.com/anthropics/claude-code/issues/46910) despite 17 sessions of "no PII" in CLAUDE.md. And [deny rules can be bypassed with 50+ subcommands](https://adversa.ai/blog/claude-code-security-bypass-deny-rules-disabled/).

Claude Code ships with no safety hooks by default. This tool fixes that — one `npx cc-safe-setup` installs the destructive-command, database-protection, credential-protection, fabrication-detection, and security-vulnerability hooks together.

**Production case study (healthcare, 2026-05-25):** Effective Therapy — a trauma therapy platform serving clinical waitlist populations in Israel — installed `dispatch-receipt.sh`, `closure-word-verify-gate.sh`, and `route-handler-emptiness-gate.sh` after a production audit found 39 OpenClaw agents deployed, only 5 ever used, and 80+ hollow-code findings across the codebase (correct auth checks, correct routes, correct success messages, missing the line that saves data). Patient-safety context: hollow `storeResearchReflection` meant trauma patient input received a "Reflection saved" success message for data that was thrown away. Full case study with the 4 hollow-code patterns and the 4.7-vs-4.6 behavioral comparison: [ianymu/recognition-without-arrest PR #2](https://github.com/ianymu/recognition-without-arrest/pull/2) (@nvst18, 2026-05-26).

**Works with Auto Mode.** Claude Code's [Auto Mode sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing) provides container-level isolation. cc-safe-setup adds process-level hooks as defense-in-depth, catching destructive commands even outside sandboxed environments.

**Works with subagents.** Since v2.1.84, subagents and teammates [don't receive CLAUDE.md](https://github.com/anthropics/claude-code/issues/40459), your project rules are silently skipped. Hooks operate at the process level, but [subagent tool calls may bypass PreToolUse hooks](https://github.com/anthropics/claude-code/issues/21460) in some configurations. As defense-in-depth, cc-safe-setup installs hooks at the user level (`~/.claude/settings.json`). The `subagent-claudemd-inject` example hook re-injects critical rules into subagent prompts.

### 🚨 Opus 4.7 Crisis (April 2026)

Opus 4.7 broke auto mode's safety classifier, it was [hardcoded to Opus 4.6](https://github.com/anthropics/claude-code/issues/49618). **If you use auto mode with Opus 4.7, dangerous commands run without the built-in safety check.** In 3 days: [50 GB permanently deleted](https://github.com/anthropics/claude-code/issues/49129), [~/.ssh wiped](https://github.com/anthropics/claude-code/issues/49554), [git credentials destroyed](https://github.com/anthropics/claude-code/issues/49539), [shell configs truncated to 0 bytes](https://github.com/anthropics/claude-code/issues/49615). Users report [4x token consumption](https://github.com/anthropics/claude-code/issues/49541) from silent model switches.

**One command to fix it:**

```bash
npx cc-safe-setup --opus47
```

Installs 4 hooks targeting known Opus 4.7 regressions. If auto mode runs dangerous commands without the built-in safety check, switch to `/model claude-opus-4-7` and run `npx cc-safe-setup --opus47` for the deterministic guards.

### The June 15 Billing Cliff (announced, then paused)
Anthropic [announced a split of programmatic billing for 2026-06-15](https://docs.claude.com/en/api/billing) — under it, `claude -p` and SDK invocations would route to a separate credit bucket — but [paused it on the day it was due](https://the-decoder.com/anthropic-backs-off-unpopular-billing-overhaul-as-price-war-with-openai-looms/) ([digitalapplied](https://www.digitalapplied.com/blog/anthropic-claude-credit-overhaul-june-15-2026)). Nothing changed for now; `claude -p`, the Agent SDK, and GitHub Actions still draw from your normal subscription limits. It remains officially announced and could return, so knowing your exposure is worthwhile — treat it as preparation, not a live emergency.
The deeper, still-live pain underneath it: **the model cannot verify Anthropic's own billing logic from its training data**, so confident-but-false billing claims keep landing on the tracker ([#61704](https://github.com/anthropics/claude-code/issues/61704), [#61728](https://github.com/anthropics/claude-code/issues/61728), [#61086](https://github.com/anthropics/claude-code/issues/61086)). `npx cc-safe-setup`'s `subscription-api-billing-warner` catches the most common money-losing misroute — a subscription silently billing API credits — at session start.
→ Deep-dive paid guide (Japanese, ¥800), operator actions mapped to days-remaining: [Claude Code の6月15日の課金分離に備える](https://zenn.dev/yurukusa/books/june-15-cliff-survival).


## What Gets Installed

| Hook | Prevents | Related Issues |
|------|----------|----------------|
| **Destructive Guard** | `rm -rf /`, `git reset --hard`, `git clean -fd`, `git checkout --force`, `sudo` + destructive, PowerShell `Remove-Item -Recurse -Force`, `rd /s /q`, NFS mount detection | [#46058](https://github.com/anthropics/claude-code/issues/46058) [#36339](https://github.com/anthropics/claude-code/issues/36339) [#36640](https://github.com/anthropics/claude-code/issues/36640) [#37331](https://github.com/anthropics/claude-code/issues/37331) |
| **Branch Guard** | Pushes to main/master + force-push (`--force`) on all branches | |
| **Secret Guard** | `git add .env`, credential files, `git add .` with .env present | [#6527](https://github.com/anthropics/claude-code/issues/6527) |
| **Syntax Check** | Python, Shell, JSON, YAML, JS errors after edits | |
| **Context Monitor** | Session state loss from context window overflow (40%→25%→20%→15% warnings) | |
| **Comment Stripper** | Bash comments breaking permission allowlists | [#29582](https://github.com/anthropics/claude-code/issues/29582) |
| **cd+git Auto-Approver** | Permission prompt spam for `cd /path && git log` | [#32985](https://github.com/anthropics/claude-code/issues/32985) [#16561](https://github.com/anthropics/claude-code/issues/16561) |
| **API Error Alert** | Silent session death from rate limits or API errors, desktop notification + log | |

Each hook exists because a real incident happened without it.

### Free diagnostics & guides
The diagnostics run in your terminal — no signup, nothing leaves your machine:
```bash
npx cc-safe-setup --scorecard   # X/8 coverage card for the protections you have
npx cc-health-check             # 20-check setup audit, 0-100 score
```
In-repo references that ship with the package: [`scripts/june-15-deprecated-model-scan.sh`](scripts/june-15-deprecated-model-scan.sh), [`scripts/claim-verify-audit.sh`](scripts/claim-verify-audit.sh), and the [June 15 cliff 14-day plan](docs/june-15-cliff-14-day-plan.md). The monthly incident write-ups now live in the free [Agent Safety Brief newsletter](https://yurukusa.substack.com) and on [Qiita](https://qiita.com/yurukusa) / [note](https://note.com/yurukusa).

### Where cc-safe-setup fits in the Claude Code safety stack

cc-safe-setup is the runtime-prevention layer of a five-layer safety stack. Each layer catches a different failure mode, they pair well in combination. None of these tools are affiliated with cc-safe-setup, they are third-party projects with their own maintainers and licenses.

| Layer | What it catches | When it acts | Representative tool |
|---|---|---|---|
| 0. Configuration audit | Vulnerabilities and misconfigurations in your Claude Code setup itself | Before any agent run | [ecc-agentshield](https://github.com/affaan-m/agentshield) (102 rules, 1282 tests) |
| 1. Runtime prevention | Dangerous tool calls about to execute | At each tool call | **cc-safe-setup (this repo)** |
| 2. Output verification | Subtle bugs and regressions in code Claude wrote | After code generation | [adamsreview](https://github.com/adamjgmiller/adamsreview) (multi-lens review pipeline) |
| 3. Session governance | Runaway retry loops, budget overruns, missing audit trails | Across an entire agent run | [Martin-Loop](https://github.com/Keesan12/Martin-Loop) (governed runtime, 11-class failure taxonomy) |
| 4. Cost measurement | Token consumption visibility | Continuous | Various trackers |

See the 5-layer ecosystem map for the failure mode each layer addresses and a progression of which layer to add at which stage of Claude Code adoption.

### Companion log-analysis tools (third-party)

These are unaffiliated projects that pair well with the cc-safe-setup hooks, they read your `~/.claude/projects/` JSONL logs from a *post-hoc analysis* angle, where the hooks here intervene at *pre-execution* time. Use them together if you want both prevention (hooks) and observation (viewers).

| Tool | What it does | License |
|------|-------------|---------|
| **[delexw/claude-code-trace](https://github.com/delexw/claude-code-trace)** (251★) | Real-time viewer for Claude Code session logs, desktop app (Tauri), web UI, and TUI. Browse projects, conversations, tool calls, token usage. Rust + TypeScript + React. | MIT |
| **[Claude Code のログから学びを得る](https://speakerdeck.com/rmizuta3/claude-codenorogukara-xue-biwode-ru)** (slides, JP) | DS perspective on parsing CC logs to learn from agent behavior. JSONL format walkthrough, subagent delegation patterns, EDA examples. By @rmizuta3, GO/DeNA AI Community 2026-03-26. | Public slides |

### Go deeper

| Resource | What you get | Price |
|----------|-------------|-------|
| **[Token Book](https://zenn.dev/yurukusa/books/token-savings-guide)** | Cut token consumption in half. CLAUDE.md templates, hook configs, context management, 32 failure patterns with fixes. 44,000+ words from 800+ hours of real operation data. | ¥2,500 (~$17). Ch.1 free |
| **[Migration Playbook](https://yurukusa.gumroad.com/l/claude-code-migration-playbook)** | Stay, switch, or hybridize? Six-week timeline of the April 2026 quota wars + 5 measurable migration triggers + Path A/B/C frameworks + cost forecasting worksheet + decision tree + 48-hour rollback checklist. Edition 1, 105 pages, English. Live since 2026-04-25; free verified-update sweep on 2026-05-08. **Edition 2 live since 2026-05-22** with 4 new triggers, 3 new migration paths (A'/B'/D), and a 9-layer expansion of the claim-vs-reality cluster. Free update for Edition 1 buyers via the Gumroad library. | $19. Free preview Gist |
| **[Claim-Verify Handbook](https://yurukusa.gumroad.com/l/claim-verify-handbook)** | Forensic record of 130 cases (15 main + 115 Appendix D continuing evidence, 233 hours from 2026-05-09 to 2026-05-17 morning, 32-fold acceleration over the 30-day baseline) where Claude Code or its sub-agents claimed success while the underlying runtime did not match. 3-stage framework + 14 operator defenses + 5 detection tools (all 5 implemented and tested, 165+ test cases passing). Anchored by Anthropic's own v2.1.144 release (6 fix items in the silent-failure / silent-override category, articulated by Anthropic itself in the release notes) and the structural-parent Issue #60226 (recognition-without-arrest) with 9 connected cases. Sister product to Migration Playbook Edition 2. **Live now — $19, PDF delivered immediately on purchase.** | $19. Free preview Gist · Free 5-question pain-type self-audit (classifies your dominant pain across settings drift / sub-agent fabrication / version regression / trust-boundary collapse, estimates urgency, routes to matching chapter) |
| **[Incident Postmortems](https://yurukusa.gumroad.com/l/rhtptb)** | Forensic archaeology of 10 production-level Claude Code incidents (cache TTL, Opus 4.7 silent downgrade, tokenizer inflation, MCP regression, weekly quota reset, /doctor settings corruption, and more), each with reproduction steps, official response analysis, and a detection hook. 100 pages, English. **Edition 2 live since 2026-05-22**. | ¥4,350. Free preview |
| **[Safety Guide](https://zenn.dev/yurukusa/books/6076c23b1cb18b)** | End-to-end Claude Code safety setup. From first install to overnight autonomous runs. | ¥800 (~$5). Ch.3 free. Same book also on [Kindle (KU)](https://www.amazon.co.jp/dp/B0H69B7SVZ) |
| **[AGENTS.md × Claude Code Interop Handbook (English)](https://yurukusa.gumroad.com/l/swpeu)** | The English edition for the #6235 gap (5,200+ reactions). A verified 9-tool setup matrix (which file each tool reads and whether it needs setup — Claude Code / Codex / Amp / GitHub Copilot / Cursor / Windsurf / Cline / Aider / Gemini CLI, checked against each tool's docs 2026-06-02), six interop paths with trade-offs, copy-paste templates per tool, a rollback-safe `CLAUDE.md`→`AGENTS.md` migration runbook, and a team drift guard. 21 pages. **Live since 2026-06-02**. | $12. Free first: the Setup Generator, the field-guide Gist, and the English Chapter preview. |
| **[AGENTS.md × Claude Code Interop Handbook (日本語)](https://zenn.dev/yurukusa/books/agents-md-interop)** | The single largest open feature request in `anthropics/claude-code` (#6235, 5,200+ reactions, 1+ year unaddressed) is the AGENTS.md gap: Codex, Cursor, Amp, Aider have converged on the AGENTS.md standard; Claude Code still only reads CLAUDE.md. Five operator-side workarounds (symlink, pre-commit, SessionStart hook, direnv, CI detection), three user-mode articulation (individual multi-tool, team mixed-tool, parallel use), three sub-cluster analysis, migration playbook, and copy-paste config templates, plus a vertical (parent↔sub-agent) multi-agent-interop safety series — Ch.10 sub-agent inheritance gaps (#40459), Ch.11 silent worktree-isolation breaks (#70069), Ch.12 forged system-instructions smuggled out of a sub-agent's result (#71602). 12 chapters. **Live since 2026-05-27**. | ¥1,500 (~$10). Intro + Ch.1 + Ch.2 + Ch.3 free on Zenn. Free English Chapter 1 preview Gist (1,093 words). |
| **[CLAUDE.md Audit (service)](./SERVICES.md)** | Written audit of your CLAUDE.md + top-3 fixes, delivered within 48h via this repo's Issue tracker. | $29 (~¥3,980) |
| **[Token Burn Audit (service)](./SERVICES.md#2-token-burn-audit--29-3980)** | Diagnosis of your actual `/cost` output, top 3 waste patterns tied to Token Book Ch.8 symptoms, with per-pattern fixes. 48h delivery. | $29 (~¥3,980) |
| **[Claude Code Safety Brief (monthly)](https://yurukusa.gumroad.com/l/xatlwf)** | **Free tier:** one verified incident a month by email — subscribe to the [Agent Safety Brief on Substack](https://yurukusa.substack.com), no payment. **Paid:** the *full* monthly digest — every failure that landed on the issue tracker that month, with user-side detection, recovery, and prevention for each — verified on a real setup — plus new and updated MIT hooks and the monthly audit checklist. The recurring, English companion to the one-time books, for people who run Claude Code with real autonomy. A free sample issue is the complete, public version of one paid month. (Japanese readers: this month's free Japanese incident digest is the public sample — no payment — and the [note membership](https://note.com/yurukusa/membership) is the full digest in Japanese.) | Free email, or $5/month for the full digest, cancel anytime. |

**Why pay?** A Max plan costs $200/month. One token waste incident burns 50–80% of your weekly quota in hours ([#46727](https://github.com/anthropics/claude-code/issues/46727)). One `rm -rf` incident costs days of recovery. The Token Book costs less than 2 hours of Max subscription time, and the CLAUDE.md templates alone can reduce consumption by 40%. **For the recurring track**, one Safety Brief month covers what would otherwise mean reading 50–100 GitHub Issues yourself.

**Pick one path.** *Cost out of control?* → Token Book. *Considering a switch (Cursor / Codex / Cline)?* → Migration Playbook. *Tools say "verified" but didn't run?* → Claim-Verify Handbook. *Subagent silent failure?* → Sub-Agent Observability Handbook. *Need to know what's already broken in production?* → Incident Postmortems. *Need to keep up with what's breaking now?* → [Safety Brief (monthly)](https://yurukusa.gumroad.com/l/xatlwf). *Not sure which fits your specific pain?* → Free 5-question selector (browser-only, no signup).

**Or use the interactive 5-question selector** if you want the longer form: maps your specific recent pain (cost, silent regression, irreversible incident, billing surprise, team posture) to one of the three books, the launch bundle, or the "free preview is enough" path. In-browser, no telemetry, free.

**Pre-flight audit before deciding.** Run a 60-second read-only scan of your current Claude Code defense posture (Bash gate / format hook / claim-verify Stop / drift arrest / subagent boundary — the five layers the Claim-Verify Handbook prescribes), output as a shareable ASCII card with grade A-F and a named top suspect:

```bash
curl -sL https://gist.githubusercontent.com/yurukusa/6c54bf2788840f84aaa67e3410e8e1ec/raw/cvh-pre-flight.sh | bash
```

Local read-only, no network calls beyond the curl, no data collection. Source: gist 6c54bf27.

### v2.1.85: `if` Field Support

Hooks now support an `if` field for conditional execution. The hook process only spawns when the command matches the pattern, `ls` won't trigger a git-only hook.

```json
{
  "type": "command",
  "if": "Bash(git push *)",
  "command": "~/.claude/hooks/test-before-push.sh"
}
```

All example hooks include `if` field documentation in their headers.

## PermissionRequest Hooks (NEW)

Override Claude Code's built-in confirmation prompts. These run **after** the built-in safety checks, so they can auto-approve prompts that `permissions.allow` cannot suppress.

| Hook | What It Solves | Issue |
|------|---------------|-------|
| `quoted-flag-approver` | "Quoted characters in flag names" prompt on `git commit -m "msg"` | [#27957](https://github.com/anthropics/claude-code/issues/27957) |
| `bash-heuristic-approver` | Safety heuristic prompts for `$()`, backticks, ANSI-C quoting | [#30435](https://github.com/anthropics/claude-code/issues/30435) |
| `edit-always-allow` | Edit prompts in `.claude/skills/` despite `bypassPermissions` | [#36192](https://github.com/anthropics/claude-code/issues/36192) |
| `allow-git-hooks-dir` | Edit prompts in `.git/hooks/` for pre-commit/pre-push setup | |
| `allow-protected-dirs` | All protected directory prompts (CI/Docker environments) | [#36168](https://github.com/anthropics/claude-code/issues/36168) |
| `git-show-flag-sanitizer` | Strips invalid `--no-stat` from `git show` (wastes context on error) | [#13071](https://github.com/anthropics/claude-code/issues/13071) |
| `compact-blocker` | Blocks auto-compaction via PreCompact (preserves full context) | [#6689](https://github.com/anthropics/claude-code/issues/6689) |
| `webfetch-domain-allow` | Auto-approves WebFetch by domain (fixes broken `domain:*` wildcard) | [#9329](https://github.com/anthropics/claude-code/issues/9329) |

Install any of these: `npx cc-safe-setup --install-example <name>`

## Session Protection Hooks

Guards against issues that corrupt sessions or waste tokens silently.

| Hook | What It Solves | Issue |
|------|---------------|-------|
| `cch-cache-guard` | Blocks reads of Claude session/billing files that poison prompt cache via `cch=` substitution | [#40652](https://github.com/anthropics/claude-code/issues/40652) |
| `image-file-validator` | Blocks Read of fake image files (text in .png) that permanently corrupt sessions | [#24387](https://github.com/anthropics/claude-code/issues/24387) |
| `terminal-state-restore` | Restores Kitty keyboard protocol, cursor, bracketed paste on exit | [#39096](https://github.com/anthropics/claude-code/issues/39096) [#39272](https://github.com/anthropics/claude-code/issues/39272) |
| `large-read-guard` | Warns before reading large files via `cat`/`less` that waste context tokens | [#41617](https://github.com/anthropics/claude-code/issues/41617) |
| `prompt-usage-logger` | Logs every prompt with timestamps to track token consumption patterns | [#41249](https://github.com/anthropics/claude-code/issues/41249) |
| `compact-alert-notification` | Alerts when auto-compaction fires (tracks compact-rebuild cycles that burn tokens) | [#41788](https://github.com/anthropics/claude-code/issues/41788) |
| `token-budget-guard` | Blocks tool calls when estimated session cost exceeds a configurable threshold | [#38335](https://github.com/anthropics/claude-code/issues/38335) |
| `session-index-repair` | Rebuilds `sessions-index.json` on exit so `claude --resume` finds all sessions | [#25032](https://github.com/anthropics/claude-code/issues/25032) |
| `session-backup-on-start` | Backs up session JSONL files on start (protects against silent deletion) | [#41874](https://github.com/anthropics/claude-code/issues/41874) |
| `working-directory-fence` | Blocks Read/Edit/Write outside CWD (prevents operating on wrong project copy) | [#41850](https://github.com/anthropics/claude-code/issues/41850) |
| `mcp-warmup-wait` | Waits for MCP servers to initialize on session start (fixes first-turn tool errors) | [#41778](https://github.com/anthropics/claude-code/issues/41778) |
| `mcp-tool-guard` | Guards destructive MCP tool calls — incl. browser automation clicking a delete button under auto-approve (`CC_MCP_AUTOMATION_GUARD=ask\|block`, `CC_MCP_PROD_HOSTS` blocks reaching production) | [#65563](https://github.com/anthropics/claude-code/issues/65563) |
| `pre-compact-transcript-backup` | Full JSONL backup before compaction (protects against rate-limit data loss) | [#40352](https://github.com/anthropics/claude-code/issues/40352) |
| `conversation-history-guard` | Blocks access to session JSONL files (prevents 20x cache poisoning) | [#40524](https://github.com/anthropics/claude-code/issues/40524) |
| `read-before-edit` | Warns when Edit targets a file not recently Read (Read:Edit ratio dropped 70%, [#42796](https://github.com/anthropics/claude-code/issues/42796)) | [#42796](https://github.com/anthropics/claude-code/issues/42796) |
| `replace-all-guard` | Warns/blocks Edit `replace_all:true` (prevents bulk data corruption) | [#41681](https://github.com/anthropics/claude-code/issues/41681) |
| `ripgrep-permission-fix` | Auto-fixes vendored ripgrep +x permission on start (fixes broken commands/skills) | [#41933](https://github.com/anthropics/claude-code/issues/41933) |

## Receipt-Persistence Layer (cross-boundary audit trail)

A family of five sibling hooks that share one architectural pattern: at every boundary where Claude Code (or a sub-agent) could claim a successful action while the underlying runtime did not match, write a structured JSONL receipt before or after the boundary fires. The receipt corpus becomes a one-line `jq` query against the silent-failure shape. Originated as a response to the *recognition-without-arrest* cluster ([#60226](https://github.com/anthropics/claude-code/issues/60226)).

| Boundary | Hook | What it records | Issue |
|----------|------|-----------------|-------|
| Session close | `closure-word-verify-gate` | "done" / "completed" claims at session end without a matching artifact | [#60506](https://github.com/anthropics/claude-code/issues/60506) |
| Scope expansion | `scope-expansion-receipt` | Tool calls touching paths outside the declared work-tree | [#61102](https://github.com/anthropics/claude-code/issues/61102) |
| Dispatch end | `dispatch-receipt` | Every `Task` / `Agent` invocation (with optional allowlist refusal) | [#61167](https://github.com/anthropics/claude-code/issues/61167) |
| Edit / Write tool | `post-edit-disk-verify` | Claimed Edit/Write content vs. post-write on-disk content | [#61303](https://github.com/anthropics/claude-code/issues/61303) |
| Dispatch start | `dispatch-allowlist-preflight` | Background sub-agent dispatches that reference MCP tools the parent's allowlist won't propagate | [#61315](https://github.com/anthropics/claude-code/issues/61315) |

Each hook ships in three modes (`warn`, `refuse`, `off`) for safe adoption. Receipts are PHI-safe — prompts and full command content are hashed (sha256), never persisted. Audit query is consistent across boundaries:

```bash
find ~/.claude/receipts -name '*.jsonl' -mtime -7 -exec cat {} \; | \
  jq -c 'select(.decision == "refuse" or .mcp_tools_referenced // [] | length > 0)'
```

The architectural rationale is documented in the Receipt-Persistence Layer gist. The full taxonomy and 130 case studies appear in the [Claim-Verify Handbook](https://yurukusa.gumroad.com/l/claim-verify-handbook).

Install any one of them: `npx cc-safe-setup --install-example <name>`.

## All 49 Commands

| Command | What It Does |
|---------|-------------|
| `npx cc-safe-setup` | Install 8 safety hooks |
| `--create "desc"` | Generate hook from plain English |
| `--audit [--fix\|--json\|--badge]` | Safety score 0-100 |
| `--lint` | Static analysis of config |
| `--diff <file>` | Compare settings |
| `--compare <a> <b>` | Side-by-side hook comparison |
| `--migrate` | Detect hooks from other projects |
| `--generate-ci` | Create GitHub Actions workflow |
| `--share` | Generate shareable URL |
| `--benchmark` | Measure hook speed |
| `--dashboard` | Real-time terminal UI |
| `--issues` | GitHub Issues each hook addresses |
| `--doctor` | Diagnose hook problems |
| `--watch` | Live blocked command feed |
| `--stats` | Block history analytics |
| `--learn [--apply]` | Pattern learning |
| `--scan [--apply]` | Tech stack detection |
| `--export / --import` | Team config sharing |
| `--verify` | Test each hook |
| `--install-example <name>` | Install from 895 examples |
| `--examples [filter]` | Browse examples by keyword |
| `--full` | All-in-one setup |
| `--status` | Check installed hooks |
| `--dry-run` | Preview changes |
| `--uninstall` | Remove all hooks |
| `--shield` | Maximum safety in one command |
| `--guard "rule"` | Instantly enforce a rule from English |
| `--suggest` | Predict risks from project analysis |
| `--from-claudemd` | Convert CLAUDE.md rules to hooks |
| `--team` | Project-level hooks for git sharing |
| `--profile [level]` | Switch safety profiles |
| `--save-profile <name>` | Save current hooks as profile |
| `--analyze` | Session analysis dashboard |
| `--health` | Hook health table |
| `--quickfix` | Auto-fix common problems |
| `--replay` | Visual blocked commands timeline |
| `--why <hook>` | Show real incident behind hook |
| `--migrate-from <tool>` | Migrate from other hook tools |
| `--diff-hooks [path]` | Compare hook configurations |
| `--init-project` | Full project setup (hooks + CLAUDE.md + CI) |
| `--score` | CI-friendly safety score (exit 1 if below threshold) |
| `--test-hook <name>` | Test a specific hook with sample input |
| `--simulate "cmd"` | Preview how all hooks react to a command |
| `--protect <path>` | Block edits to a file or directory |
| `--rules [file]` | Compile YAML rules into hooks |
| `--validate` | Validate all hook scripts (syntax + structure) |
| `--safe-mode` | Maximum protection: all safety hooks + strict config |
| `--changelog` | Show what changed in each version |
| `--report` | Generate safety report |
| `--help` | Show help |

## Quick Start by Scenario

| I want to... | Command |
|---|---|
| Make Claude Code safe right now | `npx cc-safe-setup --shield` |
| Stop permission prompt spam | `npx cc-safe-setup --install-example auto-approve-readonly` |
| Enforce a rule instantly | `npx cc-safe-setup --guard "never delete production data"` |
| See what risks my project has | `npx cc-safe-setup --suggest` |
| Convert CLAUDE.md rules to hooks | `npx cc-safe-setup --from-claudemd` |
| Share hooks with my team | `npx cc-safe-setup --team && git add .claude/` |
| Choose a safety level | `npx cc-safe-setup --profile strict` |
| See what Claude blocked today | `npx cc-safe-setup --replay` |
| Know why a hook exists | `npx cc-safe-setup --why destructive-guard` |
| See (or approve) silent memory file edits | `npx cc-safe-setup --install-example memory-write-guard` |
| Stop built-in skills editing opaquely | `npx cc-safe-setup --install-example skill-gate` |
| Diagnose why hooks aren't working | `npx cc-safe-setup --doctor` |
| Preview how hooks react to a command | `npx cc-safe-setup --simulate "git push origin main"` |
| Protect a specific file from edits | `npx cc-safe-setup --protect .env` |
| Stop .git/ write prompts | `npx cc-safe-setup --install-example allow-git-hooks-dir` |
| Auto-approve compound git commands | `npx cc-safe-setup --install-example auto-approve-compound-git` |
| Detect prompt injection patterns | `npx cc-safe-setup --install-example prompt-injection-detector` |
| Define rules in YAML, compile to hooks | `npx cc-safe-setup --rules rules.yaml` |
| Validate all hook scripts are correct | `npx cc-safe-setup --validate` |
| Maximum protection mode | `npx cc-safe-setup --safe-mode` |
| Migrate from Cursor/Windsurf | [Migration Guide](https://yurukusa.gumroad.com/l/claude-code-migration-playbook) |

## Plugin Marketplace

Install safety hooks as Claude Code plugins, no npm required:

```bash
/plugin marketplace add yurukusa/cc-safe-setup
/plugin install safety-essentials@cc-safe-setup
```

| Plugin | What it blocks |
|---|---|
| `safety-essentials` | rm -rf, force-push, hard-reset, .env overwrite, npm publish |
| `git-protection` | Force-push, main/master push, git clean, branch -D |
| `credential-guard` | .env write/edit, API keys in commands, service account files |

Also listed on [claudemarketplaces.com](https://claudemarketplaces.com).

## Writing your own hook

Hit a failure mode no existing hook covers? [**Detection-rule grammar**](docs/detection-rule-grammar.md) — the documented path from "I see this dark pattern" to "here is a hook that detects it": the 3-layer detection stack, the 4 rule-grammar primitives, the false-positive economy, and a worked example. Builds on [@waitdeadai](https://github.com/waitdeadai)'s authoring field manual.

## Common Pain Points (from GitHub Issues)

| Problem | Issue | Fix |
|---|---|---|
| Claude uses `cat`/`grep`/`sed` instead of built-in Read/Edit/Grep | [#19649](https://github.com/anthropics/claude-code/issues/19649) (48👍) | `npx cc-safe-setup --install-example prefer-builtin-tools` |
| `cd /path && cmd` bypasses permission allowlist | [#28240](https://github.com/anthropics/claude-code/issues/28240) (88👍) | `npx cc-safe-setup --install-example compound-command-approver` |
| Multiline commands skip pattern matching | [#11932](https://github.com/anthropics/claude-code/issues/11932) (47👍) | Use hooks instead of allowlist patterns for complex commands |
| No notification when Claude asks a question | [#13024](https://github.com/anthropics/claude-code/issues/13024) (52👍) | `npx cc-safe-setup --install-example notify-waiting` |
| `allow` overrides `ask` in permissions | [#6527](https://github.com/anthropics/claude-code/issues/6527) (17👍) | Use hooks to block dangerous commands instead of `ask` rules |
| Plans stored in `~/.claude/` with random names | [#12619](https://github.com/anthropics/claude-code/issues/12619) (163👍) | `npx cc-safe-setup --install-example plan-repo-sync` |

## How It Works

1. Writes hook scripts to `~/.claude/hooks/`
2. Updates `~/.claude/settings.json` to register the hooks
3. Restart Claude Code, hooks are active

Safe to run multiple times. Existing settings are preserved. A backup is created if settings.json can't be parsed.

**Maximum safety:** `npx cc-safe-setup --shield`, one command: fix environment, install hooks, detect stack, configure settings, generate CLAUDE.md.

**Instant rule:** `npx cc-safe-setup --guard "never touch the database"`, generates, installs, activates a hook instantly from plain English.

**Team setup:** `npx cc-safe-setup --team`, copy hooks to `.claude/hooks/` with relative paths, commit to repo for team sharing.

**Preview first:** `npx cc-safe-setup --dry-run`

**Check status:** `npx cc-safe-setup --status`, see which hooks are installed (exit code 1 if missing).

**Verify hooks work:** `npx cc-safe-setup --verify`, sends test inputs to each hook and confirms they block/allow correctly.

**Troubleshoot:** `npx cc-safe-setup --doctor`, diagnoses why hooks aren't working (jq, permissions, paths, shebang).

**Live monitor:** `npx cc-safe-setup --watch`, real-time dashboard of blocked commands during autonomous sessions.

**Uninstall:** `npx cc-safe-setup --uninstall`, removes all hooks and cleans settings.json.

**Requires:** [jq](https://jqlang.github.io/jq/) for JSON parsing (`brew install jq` / `apt install jq`).

**Note:** Hooks are skipped when Claude Code runs with `--bare` or `--dangerously-skip-permissions`. These modes bypass all safety hooks by design.

**Known limitations:**

- In headless mode (`-p` / `--print`), hook exit code 2 may not block tool execution ([#36071](https://github.com/anthropics/claude-code/issues/36071)). For CI pipelines, use interactive mode with hooks rather than `-p` mode.
- `FileChanged` notifications inject file contents into model context **before** hooks can intervene. If a sensitive file (`.env`, `credentials.json`) is modified externally during a session, its contents may appear in the conversation transcript regardless of hooks ([#44909](https://github.com/anthropics/claude-code/issues/44909)). Mitigation: use `dotenv-watch` to get alerted, and avoid editing sensitive files while Claude Code is running.

## Before / After

Run `npx cc-health-check` to see the difference:

| | Before | After |
|---|--------|-------|
| Safety Guards | 25% | **75%** |
| Overall Score | 50/100 | **95/100** |
| Destructive commands | Unprotected | Blocked |
| Force push | Allowed | Blocked |
| `.env` in git | Possible | Blocked |
| Context warnings | None | 4-stage alerts |

## Configuration

| Variable | Hook | Default |
|----------|------|---------|
| `CC_ALLOW_DESTRUCTIVE=1` | destructive-guard | `0` (protection on) |
| `CC_SAFE_DELETE_DIRS` | destructive-guard | `node_modules:dist:build:.cache:__pycache__:coverage` |
| `CC_PROTECT_BRANCHES` | branch-guard | `main:master` |
| `CC_ALLOW_FORCE_PUSH=1` | branch-guard | `0` (protection on) |
| `CC_SECRET_PATTERNS` | secret-guard | `.env:.env.local:credentials:*.pem:*.key` |
| `CC_CONTEXT_MISSION_FILE` | context-monitor | `$HOME/mission.md` |

## After Installing

Verify your setup:

```bash
npx cc-health-check
```

**Then confirm your hooks actually *fire*, not just that they're configured.** A hook listed in `settings.json` (or shown as installed) is not the same as a hook that runs — and a safety guard that silently never executes is worse than none, because it gives you a false sense of protection on exactly the operations you most want stopped. Two known cases where configured hooks don't fire: the **Windows PowerShell-tool blind spot** (see [Windows Support](#windows-support) below), and the **Desktop app** — some users report that plugin hooks (`SessionStart`, `PreToolUse`, …) are listed but never run there ([#72025](https://github.com/anthropics/claude-code/issues/72025)). Quick self-test: add a `SessionStart` hook that appends the date to a log file, start a session in each client you use, and check the log. If a client doesn't write the line, its hooks aren't running — for safety-critical or irreversible work, use the terminal CLI, where hook execution is confirmed.

### Keep up with what's breaking next

The hooks in this repo defend against failure patterns that have *already* been articulated. New ones surface every week. As of 2026-05-29, the cluster tracker tracks 12 structural failure clusters across 11,820+ cumulative GitHub Issue reactions on `anthropics/claude-code`. Most-recent example: Cluster 12 (Tool Call Parsing failures in Opus 4.7) was articulated 2026-05-28 from five filings, and the four sub-pattern advisory hooks shipped within 24 hours (PRs #406 / #419 / #423 / #424, 194 tests). The free Cluster 12 field guide (2,860 words) walks the install path for all four hooks.

If you want this kind of cluster-to-defense walkthrough delivered monthly — the Claude Code failures that actually landed on the issue tracker, each with user-side detection, recovery, and prevention verified on a real setup, plus new and updated MIT hooks as Claude Code changes — start with the [free Agent Safety Brief email](https://yurukusa.substack.com) (one verified incident a month, no payment), and step up to the *full* monthly digest with the [Claude Code Safety Brief](https://yurukusa.gumroad.com/l/xatlwf) ($5/month, cancel anytime) when you want every incident plus the hooks and checklist. One avoided Max-plan incident covers a year of membership. A free sample issue is the complete, public version of one paid month, so you can judge the depth before subscribing. (Japanese readers: this month's free Japanese incident digest is the public sample — no payment — and the [note membership](https://note.com/yurukusa/membership) covers the same ground in Japanese.)

## Full Kit

cc-safe-setup gives you 8 essential hooks. Want to know what else your setup needs?

Run `npx cc-health-check` (free, 20 checks) to see your current score. If it's below 80, the **Claude Code Ops Kit** fills the gaps, 6 hooks + 5 templates + 9 scripts + install.sh. Pay What You Want ($0+).

**Starter Kit:** Want hooks + settings + templates in one download? The **[Claude Code Safety Kit](https://yurukusa.itch.io/claude-code-safety-kit)** bundles 5 safety hooks, a pre-configured settings.json, CLAUDE.md templates, and 800-hour operation tips. Name your price ($0+).

Or browse the free hooks: [claude-code-hooks](https://www.npmjs.com/package/cc-safe-setup)

## Examples

## Safety Audit

**Try it in your browser**: paste your settings.json, get a score instantly. Nothing leaves your browser.

Or from the CLI:

```bash
npx cc-safe-setup --audit
```

Analyzes 9 safety dimensions and gives you a score (0-100) with one-command fixes for each risk.

### CI Integration (GitHub Action)

Gate every PR on a safety score — the agent that runs `rm -rf` or commits a `.env` in one repo doesn't care how careful the rest of the team was. Drop in this workflow:

```yaml
# .github/workflows/safety.yml
name: Claude Code Safety
on: [push, pull_request]
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: yurukusa/cc-safe-setup@main
        with:
          threshold: 70   # CI fails if the safety score drops below this
```

It exposes `score`, `grade`, and `risks` outputs for later steps. Free, MIT, no token, no signup.

**Show your score** — paste a badge into your README (`npx cc-safe-setup --audit --badge` prints one for your current score):

```markdown
![Claude Code Safety](https://img.shields.io/badge/Claude_Code_Safety-90%2F100-brightgreen)
```

> **Rolling this out across a whole org?** Per-repo CI is free (above). If you'd want one shared policy enforced across *every* repo centrally — with an audit trail and no per-repo opt-in for a new repo to silently forget — I'm gauging interest before building it: tell me it'd help. The free tier stays free.

### Project Scanner

```bash
npx cc-safe-setup --scan         # detect tech stack, recommend hooks
npx cc-safe-setup --scan --apply # auto-create CLAUDE.md with project rules
```

### Create Hooks from Plain English

```bash
npx cc-safe-setup --create "block npm publish without tests"
npx cc-safe-setup --create "auto approve test commands"
npx cc-safe-setup --create "block curl pipe to bash"
npx cc-safe-setup --create "block DROP TABLE and TRUNCATE"
```

9 built-in templates + generic fallback. Creates the script, registers it, and runs a smoke test.

### Self-Learning Safety

```bash
npx cc-safe-setup --learn        # analyze your block history for patterns
npx cc-safe-setup --learn --apply # auto-generate custom hooks from patterns
```

## Examples

Need custom hooks beyond the 8 built-in ones? Install any example with one command:

```bash
npx cc-safe-setup --install-example block-database-wipe
```

Or browse all available examples in [`examples/`](examples/):

- **claude-update-smart.sh**: Skip the 226 MB tarball download when already up-to-date (workaround for [#51243](https://github.com/anthropics/claude-code/issues/51243)). Turns 30 s checks into 0.3 s. Falls through to the real `claude update` when a new release exists or the registry is unreachable.
- **auto-approve-git-read.sh**: Auto-approve `git status`, `git log`, even with `-C` flags
- **auto-approve-ssh.sh**: Auto-approve safe SSH commands (`uptime`, `whoami`, etc.)
- **enforce-tests.sh**: Warn when source files change without corresponding test files
- **notify-waiting.sh**: Desktop notification when Claude Code waits for input (macOS/Linux/WSL2)
- **edit-guard.sh**: Block Edit/Write to protected files (defense-in-depth for [#37210](https://github.com/anthropics/claude-code/issues/37210))
- **auto-approve-build.sh**: Auto-approve npm/yarn/cargo/go/python build, test, and lint commands
- **auto-approve-docker.sh**: Auto-approve docker build, compose, ps, logs, and other safe commands
- **block-database-wipe.sh**: Block destructive database commands: Laravel `migrate:fresh`, Django `flush`, Rails `db:drop`, raw `DROP DATABASE` ([#46684](https://github.com/anthropics/claude-code/issues/46684) [#46650](https://github.com/anthropics/claude-code/issues/46650) [#37405](https://github.com/anthropics/claude-code/issues/37405) [#37439](https://github.com/anthropics/claude-code/issues/37439))
- **worktree-parent-write-guard.sh**: Block silent writes to the PARENT repo while working in a worktree nested at `<repo>/.claude/worktrees/<name>/`. When the agent targets the canonical path (`<repo>/src/foo`) instead of the worktree path, the edit lands in the parent checkout (often the default branch) and the worktree diff shows "No changes" — silent data loss / wrong-branch writes. Fires only in the nested-worktree setup; allows correct in-worktree writes, /tmp, and home configs ([#62547](https://github.com/anthropics/claude-code/issues/62547) [#60679](https://github.com/anthropics/claude-code/issues/60679) [#69026](https://github.com/anthropics/claude-code/issues/69026))
- **reroute-after-block-guard.sh**: Stop a reroute toward a just-blocked target. PreToolUse hooks are stateless, so the failure trajectory in [#70112](https://github.com/anthropics/claude-code/issues/70112) (a gate fires, the agent substitutes an equivalent path toward the same target, the next hook sees a fresh individually-defensible action and lets it run) slips through. This guard reads the transcript: if the previous tool call was blocked by a PreToolUse hook or a permission denial and the current action shares a concrete path-like target, it stops and surfaces — a fired gate should *raise* the threshold for proceeding, not prompt a search for another route. Fail-open (no transcript / no shared target / previous succeeded → allowed); legitimate retry after fixing the real problem uses `CC_REROUTE_ALLOW=1` for that one command. Disable with `CC_REROUTE_DISABLE=1` ([#70112](https://github.com/anthropics/claude-code/issues/70112))
- **sql-bulk-delete-warn.sh**: Warn when DELETE/UPDATE/TRUNCATE runs via psql/mysql/sqlite3/sqlcmd without a row-count safeguard. Catches the Issue #56738 pattern (DELETE WHERE col IS NULL after a regex/UPDATE that silently NULLed nearly every row, wiping 24,472 of 24,475 rows in 5 minutes before autovacuum cleaned the dead tuples). Also flags DELETE/UPDATE without WHERE, TRUNCATE TABLE, and `psql -c` invocations missing an explicit transaction. Strict mode via `CC_SQL_BULK_DELETE_BLOCK=1` ([#56738](https://github.com/anthropics/claude-code/issues/56738))
- **auto-approve-python.sh**: Auto-approve pytest, mypy, ruff, black, isort, flake8, pylint commands
- **auto-snapshot.sh**: Auto-save file snapshots before edits for rollback protection ([#37386](https://github.com/anthropics/claude-code/issues/37386) [#37457](https://github.com/anthropics/claude-code/issues/37457))
- **allowlist.sh**: Block everything not explicitly approved, inverse permission model ([#37471](https://github.com/anthropics/claude-code/issues/37471))
- **protect-dotfiles.sh**: Block modifications to `~/.bashrc`, `~/.aws/`, `~/.ssh/` and chezmoi without diff ([#37478](https://github.com/anthropics/claude-code/issues/37478))
- **scope-guard.sh**: Block file operations outside project directory, absolute paths, home, parent escapes ([#36233](https://github.com/anthropics/claude-code/issues/36233))
- **auto-checkpoint.sh**: Auto-commit after every edit for rollback protection ([#34674](https://github.com/anthropics/claude-code/issues/34674))
- **git-config-guard.sh**: Block `git config --global` modifications without consent ([#37201](https://github.com/anthropics/claude-code/issues/37201))
- **deploy-guard.sh**: Block deploy commands when uncommitted changes exist ([#37314](https://github.com/anthropics/claude-code/issues/37314))
- **deployment-readback-gate.sh** + **deployment-readback-gh-adapter.sh**: `Stop` hook — refuse a "deployment complete" closeout unless the GitHub Deployments API confirms the claimed ref recently (fails closed when the authority is unreachable); writes an audit receipt outside the transcript ([#61699](https://github.com/anthropics/claude-code/issues/61699), #313)
- **network-guard.sh**: Warn on suspicious network commands sending file contents ([#37420](https://github.com/anthropics/claude-code/issues/37420))
- **test-before-push.sh**: Block `git push` when tests haven't been run ([#36970](https://github.com/anthropics/claude-code/issues/36970))
- **large-file-guard.sh**: Warn when Write tool creates files over 500KB
- **commit-message-check.sh**: Warn on non-conventional commit messages (feat:, fix:, docs:, etc.)
- **env-var-check.sh**: Block hardcoded API keys (sk-, ghp_, glpat-) in export commands
- **timeout-guard.sh**: Warn before long-running commands (npm start, rails s, docker-compose up)
- **branch-name-check.sh**: Warn on non-conventional branch names (feature/, fix/, etc.)
- **todo-check.sh**: Warn when committing files with TODO/FIXME/HACK markers
- **path-traversal-guard.sh**: Block Edit/Write with `../../` path traversal and system directories
- **case-sensitive-guard.sh**: Detect case-insensitive filesystems (exFAT, NTFS, HFS+) and block rm/mkdir that would collide due to case folding ([#37875](https://github.com/anthropics/claude-code/issues/37875))
- **compound-command-approver.sh**: Auto-approve safe compound commands (`cd && git log`, `cd && npm test`) that the permission system can't match ([#30519](https://github.com/anthropics/claude-code/issues/30519) [#16561](https://github.com/anthropics/claude-code/issues/16561))
- **tmp-cleanup.sh**: Clean up accumulated `/tmp/claude-*-cwd` files on session end ([#8856](https://github.com/anthropics/claude-code/issues/8856))
- **session-checkpoint.sh**: Save session state to mission file before context compaction ([#37866](https://github.com/anthropics/claude-code/issues/37866))
- **verify-before-commit.sh**: Block git commit when lint/test commands haven't been run ([#37818](https://github.com/anthropics/claude-code/issues/37818))
- **hook-debug-wrapper.sh**: Wrap any hook to log input/output/exit code/timing to `~/.claude/hook-debug.log`
- **loop-detector.sh**: Detect and break command repetition loops (warn at 3, block at 5 repeats)
- **same-correction-arrest.sh**: Detect the user repeating the same correction N=3 times in a session, then require a written plan before further Write/Edit. Operationalizes the model's own self-diagnosis in [#60506](https://github.com/anthropics/claude-code/issues/60506) ("I have no drift detector"), grounded in the recognition-without-arrest framework from [#60226](https://github.com/anthropics/claude-code/issues/60226).
- **closure-word-verify-gate.sh**: Stop hook that scans the assistant's outgoing turn for closure words ("done", "shipped", "complete", "bitti", "finished") and refuses Stop unless a verification command (test runner, Playwright, curl) ran in the same turn. Implements customer recommendation #4 from [#60506](https://github.com/anthropics/claude-code/issues/60506): _"two hours after the rule I said 'bitti' again, without opening the browser"_.
- **authorized-reconfirmation-detector.sh**: Stop hook that measures how often `AskUserQuestion` fires on an action the operator's prior turn already authorized (case 3 in the three-way split articulated in [#61929](https://github.com/anthropics/claude-code/issues/61929#issuecomment-4549798175)). Detects: AUQ called this turn + an option marked `(Recommended)` / `推奨` + the operator's last message contains a content word that also appears in the AUQ question text. Emits a structured JSON log line per match to `~/.claude/audit/authorized-reconfirmation.log` — never blocks. The log file becomes the empirical foundation for the eventual UserPromptSubmit-side intent classifier (related: mhernz's [#61337](https://github.com/anthropics/claude-code/issues/61337) `/goal`-authorization-equivalence, and [#61983](https://github.com/anthropics/claude-code/issues/61983) preamble visibility for case 2).
- **redundant-read-blocker.sh**: PreToolUse hook on `Read` that detects when the model is about to re-read a file already read in the same session (with the same mtime). Operationalizes [#60283](https://github.com/anthropics/claude-code/issues/60283) ("excessive token consumption — task halted mid-execution with zero output") and the broader quota-leakage cluster (analysis, audit tool). Default mode warns; strict mode refuses the call.
- **session-start-quota-status.sh**: SessionStart hook that scans `~/.claude/projects/*/[session-id].jsonl` modified within rolling 5-hour and 7-day windows, aggregates token usage by model family (opus/sonnet/haiku), estimates API-equivalent cost (including cache_read at 10% of input rate and cache_write at 1.25x input), and surfaces a real-time quota dashboard at session start. Operator-side workaround for the cluster where Anthropic does not yet provide a native dashboard: [#16157](https://github.com/anthropics/claude-code/issues/16157) (1,470+ comments), [#38335](https://github.com/anthropics/claude-code/issues/38335) (723+), [#29579](https://github.com/anthropics/claude-code/issues/29579) (150+). Compares against subscription Pool 2 credit (June 15+: $20/$100/$200). Configurable warning thresholds; always exits 0.
- **commit-quality-gate.sh**: Warn on vague commit messages ("update code"), long subjects, mega-commits
- **session-handoff.sh**: Auto-save git state and session info to `~/.claude/session-handoff.md` on session end
- **diff-size-guard.sh**: Warn/block when committing too many files at once (default: warn at 10, block at 50)
- **dependency-audit.sh**: Warn when installing packages not in manifest (npm/pip/cargo supply chain awareness)
- **env-source-guard.sh**: Block sourcing .env files into shell environment ([#401](https://github.com/anthropics/claude-code/issues/401))
- **symlink-guard.sh**: Detect symlink/junction traversal in rm targets ([#36339](https://github.com/anthropics/claude-code/issues/36339) [#764](https://github.com/anthropics/claude-code/issues/764))
- **no-sudo-guard.sh**: Block all sudo commands
- **no-install-global.sh**: Block npm -g and system-wide pip
- **no-curl-upload.sh**: Warn on curl POST/upload (data exfiltration)
- **no-port-bind.sh**: Warn on network port binding
- **git-tag-guard.sh**: Block pushing all tags at once
- **npm-publish-guard.sh**: Version check before npm publish
- **max-file-count-guard.sh**: Warn when 20+ new files created per session
- **protect-claudemd.sh**: Block edits to CLAUDE.md and settings files
- **reinject-claudemd.sh**: Re-inject CLAUDE.md rules after compaction ([#6354](https://github.com/anthropics/claude-code/issues/6354))
- **binary-file-guard.sh**: Warn when Write targets binary file types (images, archives)
- **stale-branch-guard.sh**: Warn when working branch is far behind default
- **cost-tracker.sh**: Estimate session token cost and warn at thresholds ($1, $5)
- **read-before-edit.sh**: Warn when editing files not recently read (prevents old_string mismatches)
- **windows-python-stub-detector.sh**: SessionStart probe that surfaces the Microsoft Store `python3` stub on Windows Git Bash — `which python3` succeeds but subprocess exits 49 with no output, silently no-op-ing every Python-based hook. Matches four failure modes (exit 49 / Store-redirect stderr / exit 127 / silent stub) and warns via hookSpecificOutput ([#57946](https://github.com/anthropics/claude-code/issues/57946))

## Safety Checklist

**[SAFETY_CHECKLIST.md](SAFETY_CHECKLIST.md)**: Copy-paste checklist for before/during/after autonomous sessions.

## Windows Support

Works on Windows via WSL or Git Bash. The hooks are bash scripts, so a host with no bash at all (PowerShell-only, no Git Bash) cannot run them.

**The PowerShell tool is separate from the Bash tool.** Claude Code ships two distinct shell tools — `Bash` and [`PowerShell`](https://code.claude.com/docs/en/tools) — and on Windows it often runs commands through the PowerShell tool. A hook registered with `matcher: "Bash"` **never fires** on a PowerShell-tool command. That blind spot let a destructive `az ad group delete` run with no permission prompt in [#69397](https://github.com/anthropics/claude-code/issues/69397). If you run on Windows with Git Bash (so bash is available to execute the hook) and want the destructive guards to cover the PowerShell tool, register the shell-command guards with `matcher: "Bash|PowerShell"`:

```json
{
  "matcher": "Bash|PowerShell",
  "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/windows-destructive-command-guard.sh" }]
}
```

The `windows-destructive-command-guard.sh`, `powershell-remove-item-guard.sh`, and `cloud-cli-guard.sh` examples all read `tool_input.command`, which both tools populate, so they work unchanged once the matcher includes `PowerShell`.

**Common issue:** If you see `Permission denied` or `No such file` errors after install, run:

```bash
npx cc-safe-setup --doctor
```

This detects Windows backslash paths (`C:\Users\...` → `C:/Users/...`) and missing execute permissions.

See Issue #1 for details.

**Free Windows safety guide:** Claude Code on Windows — Safety Guide for the Issues That Don't Exist on macOS/Linux (~1,735 words, MIT) — five Windows-specific failure modes from the May 2026 tracker (BSOD with HVCI, runaway PowerShell spawn cascade, empty Bash output, PowerShell unavailable under MINGW64, OAuth paste freeze) with operator-side mitigations and a "WSL2 vs native Windows" decision tree. Written in response to the volume of Windows-specific issues that surfaced during May 2026, including [#62193](https://github.com/anthropics/claude-code/issues/62193) (nested PowerShell spawn → cross-window crash on Windows 11).

## Troubleshooting

**[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: "Hook doesn't work" → step-by-step diagnosis. Covers every common failure pattern.

## settings.json Reference

**[SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md)**: Complete reference for permissions, hooks, modes, and common configurations. Includes known limitations and workarounds.

## Migration Guide

**[MIGRATION.md](MIGRATION.md)**: Step-by-step guide for moving from permissions-only to permissions + hooks. Keep your existing config, add safety layers on top.

## Learn More

- **Opus 4.7 Survival Guide**: 61 known issues (76+ GitHub Issues + CVEs) with fixes: data loss, recursive spawn DoS, billing mismatch, subagent OOM, cache_read anomaly, allowedTools bypass, 1.7x token inflation, classifier failure, thinking summary bugs, 30-min stalls, enterprise hooks bypass, and more. [`npx cc-safe-setup --opus47`](#-opus-47-crisis-april-2026)
- **[Token Book (¥2,500)](https://zenn.dev/yurukusa/books/token-savings-guide)**: Cut token consumption in half. CLAUDE.md optimization, hook-based guards, context management, workflow design. 44,000 words with copy-paste templates. Intro + Ch.1 free. [Details](https://zenn.dev/yurukusa/books/token-savings-guide)
- **[Safety Guide (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b)**: Token consumption diagnosis, file loss prevention, autonomous operation safety. From 800+ hours of real incidents. [Chapter 3 free](https://zenn.dev/yurukusa/books/6076c23b1cb18b/viewer/3-code-quality)
- **[800 Hours Operation Record (¥800)](https://zenn.dev/yurukusa/books/3c3c3baee85f0a19)**: Non-engineer running Claude Code autonomously for 800 hours. Failures, recovery, revenue reality. [Chapter 2 free](https://zenn.dev/yurukusa/books/3c3c3baee85f0a19/viewer/2-first-failures)
- **[AGENTS.md × Claude Code Interop Handbook (¥1,500)](https://zenn.dev/yurukusa/books/agents-md-interop)**: The 5,196-reaction feature-request cluster (Issue #6235, 1+ year unaddressed). Five operator-side workarounds (symlink, pre-commit, SessionStart hook, direnv, CI detection), three user-mode articulations, three sub-cluster analysis, migration playbook, and config templates, plus a vertical multi-agent-interop safety series (Ch.10 sub-agent inheritance / Ch.11 worktree isolation / Ch.12 forged sub-agent output, #71602). 12 chapters. Intro + Ch.1 + Ch.2 + Ch.3 free.
- **[Claude Code Skills Practical Recipes (¥500)](https://zenn.dev/yurukusa/books/a1b2c3d4e5f6g7)**: Progressive Disclosure with the 3-layer SKILL.md structure for 40% token reduction. 10 practical recipes (automation, MCP, documentation, testing, team sharing, advanced patterns) from the 20,000-view Qiita Skills deep-dive. Intro + Ch.1 free.
- **[Autonomous Claude Ops (free tool + sample chapter)](https://yurukusa.gumroad.com/l/iglmx)**: Is your autonomous agent *busy at the floor*? A read-only audit of your own Claude Code session logs, median responses per session, and where your tokens actually go (cache_read breakdown), plus a free Chapter 1 on why activity isn't progress. **The full 7-chapter book is now live: [Autonomous Claude Ops (~$6)](https://yurukusa.gumroad.com/l/iglmx)** — the silent token drain you can't see (Ch.5) and the `git reset --hard` you didn't type (Ch.7), written for overnight autonomous runs. The first English data-loss/cost safety book; the free tool above runs the same `verify.py` the book is built on.
- **[Claude Code Safety Brief (monthly, $5/month)](https://yurukusa.gumroad.com/l/xatlwf)**: Each month, the Claude Code failures that actually landed on the issue tracker, with user-side detection, recovery, and prevention for each — verified on a real setup — plus new and updated MIT hooks. The recurring, English companion to the one-time books. A free June 2026 sample issue is the complete, public version of one month, so you can judge the depth before subscribing. (Japanese readers: this month's free Japanese incident digest is the public sample — no payment — and the [note membership](https://note.com/yurukusa/membership) covers the same ground in Japanese.)
- **Wiki Guides**: Token FAQ · CLAUDE.md Best Practices · Token Optimization
- [Cookbook](COOKBOOK.md), 26 practical recipes (block, approve, protect, monitor, diagnose)
- [Official Hooks Reference](https://code.claude.com/docs/en/hooks), Claude Code hooks documentation
- Hooks Cookbook, 25 recipes from real GitHub Issues
- [Skills Guide deep-dive (Qiita, 19K+ views)](https://qiita.com/yurukusa/items/f69920b4a02cf7e2988c), Anthropic's official Skills PDF analyzed with 40% token reduction
- [Japanese guide (Qiita)](https://qiita.com/yurukusa/items/a9714b33f5d974e8f1e8), この記事の日本語解説
- [Opus 4.7 breaking changes deep-dive (Hashnode)](https://yurukusa.hashnode.dev/opus-47-isnt-a-regression-but-your-46-prompts-are-now-broken), Anthropic's 9 breaking changes, 5 workarounds, and the `task_budget` beta nobody mentions. Covers why `thinking-stall-detector` and `claude-md-reinjector` hooks exist
- [v2.1.85 `if` field guide (Qiita)](https://qiita.com/yurukusa/items/7079866e9dc239fcdd57), Reduce hook overhead with conditional execution
- [Deny rules bypass vulnerability (Qiita)](https://qiita.com/yurukusa/items/f9c48bb44569bbf4492e), 50+ subcommands disable all deny rules; hook-based defense
- [Hook Test Runner](https://www.npmjs.com/package/cc-hook-test), `npx cc-hook-test <hook.sh>` to auto-test any hook
- [Hook Registry](https://www.npmjs.com/package/cc-hook-registry), `npx cc-hook-registry search database`
- Hooks Cheat Sheet, printable A4 quick reference
- Ecosystem Comparison, all Claude Code hook projects compared
- [The incident that inspired this tool](https://github.com/anthropics/claude-code/issues/36339), NTFS junction rm -rf
- How to prevent rm -rf disasters, real incidents and the hook that stops them
- How to prevent force-push to main, branch protection via hooks
- How to prevent secret leaks, stop git add . from committing .env

### Newsletter (free)

These tools change weekly, and so do the failure modes. The [**Claude Code Safety Brief**](https://yurukusa.substack.com) is a free monthly email: that month's verified incidents from the public issue trackers (Claude Code, Cursor, Copilot, Codex), the copy-paste settings that stop them, and what changed in the tools. No hype — just what broke and the lines that fix it.

### Professional Services

The hooks above stay free (MIT) forever. If you'd rather have a person help, there are two paid tracks:

- **Individuals** — [Safety Setup Service](./SERVICES.md): a one-off audit of your Claude Code config, token optimization, and custom hooks by the cc-safe-setup team.
- **Teams & organizations (日本語)** — 法人・チーム向けの安全導入・研修・保守: for rolling Claude Code out across a company. A security audit of your `settings.json` / `CLAUDE.md`, an org-wide enforced safety baseline, CI safety gates, team training (potentially eligible for Japan's 人材開発支援助成金), and ongoing operations-layer support. This is the layer *after* training — stopping the incidents that happen even to careful, trained developers, because one unprotected developer is an org-wide risk.

## FAQ

**Q: I installed hooks but Claude says "Unknown skill: claude-code-hooks:setup"**

cc-safe-setup installs **hooks**, not skills or plugins. Hooks run automatically in the background, you don't invoke them manually. After install + restart, try running a dangerous command; the hook will block it silently.

**Q: `cc-health-check` says to run `cc-safe-setup` but I already did**

cc-safe-setup covers Safety Guards (75-100%) and Monitoring (context-monitor). The other health check dimensions (Code Quality, Recovery, Coordination) require additional CLAUDE.md configuration or manual hook installation from [claude-code-hooks](https://www.npmjs.com/package/cc-safe-setup).

**Q: Will hooks slow down Claude Code?**

No. Each hook runs in ~10ms. They only fire on specific events (before tool use, after edits, on stop). No polling, no background processes.

**Q: My permission patterns don't match compound commands like `cd /path && git status`**

This is a known limitation of Claude Code's permission system ([#16561](https://github.com/anthropics/claude-code/issues/16561), [#28240](https://github.com/anthropics/claude-code/issues/28240)). Permission matching evaluates only the first token (`cd`), not the actual command (`git status`). Use a PreToolUse hook instead, hooks see the full command string and can parse compound commands. See `compound-command-allow.sh` in examples.

**Q: `--dangerously-skip-permissions` still prompts for `.claude/` and `.git/` writes**

Since v2.1.78, protected directories always prompt regardless of permission mode ([#35668](https://github.com/anthropics/claude-code/issues/35668)). Use a PermissionRequest hook to auto-approve specific protected directory operations. See `allow-protected-dirs.sh` in examples.

**Q: `allow: ["Bash(*)"]` overrides my `ask` rules**

`allow` takes precedence over `ask`. If you allow all Bash, ask rules are ignored ([#6527](https://github.com/anthropics/claude-code/issues/6527)). Use PreToolUse hooks to block dangerous commands instead of relying on the ask/allow priority system.

**Q: Hooks silently fail on macOS (Homebrew `jq` not found)**

Claude Code runs hooks with a restricted PATH that excludes `/opt/homebrew/bin` ([#46954](https://github.com/anthropics/claude-code/issues/46954)). If `jq` is installed via Homebrew, hooks silently exit 0. Fix: add `export PATH="/opt/homebrew/bin:$PATH"` at the top of your hook script, or use absolute paths like `/opt/homebrew/bin/jq`. Inline hooks in `settings.json` may also be affected, add a PATH export prefix: `export PATH="/opt/homebrew/bin:$PATH"; INPUT=$(cat); ...`

**Q: How is this different from [claude-token-efficient](https://github.com/drona23/claude-token-efficient)?**

Different goals. claude-token-efficient optimizes CLAUDE.md to make Claude's responses shorter and cheaper. cc-safe-setup prevents dangerous operations (file deletion, credential leaks, force-push). They work well together: use claude-token-efficient for cost reduction, cc-safe-setup for safety. For comprehensive token optimization beyond CLAUDE.md (hooks, context management, workflow design), see the [Token Book](https://zenn.dev/yurukusa/books/token-savings-guide).

**Still stuck?** See the full Permission Troubleshooting Flowchart for step-by-step diagnosis.

## Contributing

**Report a problem:** Found a false positive or a bypass? Open an issue. Include the command that was incorrectly blocked/allowed and your OS.

**Request a hook:** Describe the problem you're trying to prevent (not the solution). We'll figure out the hook together.

**Write a hook:** Fork, add your `.sh` file to `examples/`, add tests to `test.sh`, and open a PR. Every hook needs:
- A comment header explaining what it blocks and why
- At least 7 test cases (block, allow, empty input, edge cases)
- `bash -n` syntax validation passing

**Share your experience:** Used cc-safe-setup and have feedback? Open a discussion or comment on any issue. We read everything.

If cc-safe-setup saved you from a disaster (or just saved you time), a ⭐ helps others find it too.

## Why I keep giving these away

I'm a non-engineer running Claude Code autonomously for 800+ hours. In that span I lost files twice, watched a session burn through 887K tokens per minute, and ate a $569 surprise charge from a misread setting.

Every time, I built a small defensive hook for myself and put it here — free, MIT, no signup. That's roughly 897 example hooks across three months.

I expected giving away the hooks would cannibalize my paid books. The opposite happened: a steady trickle of users who tried the hooks ended up buying one of the [5 Zenn books](https://zenn.dev/yurukusa) (¥11,373 total over 3 months across 12 purchases, including two readers from outside Japan).

The hooks stay free because the same failure happening to a stranger is the same failure happening to me — just on a different machine. The paid books exist for the parts hooks can't solve: the judgment calls, the timing questions, the trade-offs that no shell script can answer.

— yurukusa, [full story](https://yurukusa-dev.hatenablog.com/entry/2026/05/30/015308) (2026-05-30)

## Affiliate Program

If you write or teach about Claude Code, you can earn 30% commission promoting our paid books and kits. Apply with any Gumroad account, no application form, 30-day cookie window, automatic Gumroad payouts:

- [yurukusa.gumroad.com/affiliates](https://yurukusa.gumroad.com/affiliates)

Eligible products include the [Migration Playbook](https://yurukusa.gumroad.com/l/claude-code-migration-playbook), [Incident Postmortems](https://yurukusa.gumroad.com/l/rhtptb) (live since 2026-05-05), [Token Book EN](https://yurukusa.gumroad.com/l/azrdt) (pay what you want), [Complete Survival Kit](https://yurukusa.gumroad.com/l/poqhoo), [CLAUDE.md Templates](https://yurukusa.gumroad.com/l/iaple), and other Claude Code titles. See each product page for the current price.

## Also by yurukusa


## License

MIT
