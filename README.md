# cc-safe-setup

[![npm version](https://img.shields.io/npm/v/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![npm downloads](https://img.shields.io/npm/dw/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![tests](https://github.com/yurukusa/cc-safe-setup/actions/workflows/test.yml/badge.svg)](https://github.com/yurukusa/cc-safe-setup/actions/workflows/test.yml)

> Listed on [Product Hunt](https://www.producthunt.com/products/cc-safe-setup) since April 21, 2026.

**One command to make Claude Code safe for autonomous operation.** 746 example hooks · 73+ Anthropic Issues addressed by hook · 9,250+ tests · 30K+ total installs · [日本語](docs/README.ja.md)

```bash
npx cc-safe-setup
```

Installs 8 safety hooks in ~10 seconds. Blocks `rm -rf /`, prevents pushes to main, catches secret leaks, validates syntax after every edit. Zero npm dependencies. Hooks use [`jq`](https://jqlang.github.io/jq/) at runtime (`brew install jq` / `apt install jq`).

> **What's a hook?** A checkpoint that runs before Claude executes a command. Like airport security, it inspects what's about to happen and blocks anything dangerous before it reaches the gate.

[**▶ Live Demo**](https://yurukusa.github.io/cc-safe-setup/demo.html) (see hooks block rm -rf in your browser) · [**Incident Tracker**](https://yurukusa.github.io/cc-safe-setup/incidents.html) (90 real incidents) · [**Cluster Exposure Diagnostic**](https://yurukusa.github.io/cc-safe-setup/cluster-exposure-diagnostic.html) (NEW 2026-05-29: 7 questions → which of the 12 tracked failure clusters you are exposed to) · [**Cluster 12 Sub-Pattern Diagnostic**](https://yurukusa.github.io/cc-safe-setup/cluster-12-tool-call-parsing-diagnostic.html) (NEW 2026-05-29: 4 questions → which of the 4 Opus 4.7 tool-call parsing sub-patterns 12A/12B/12C/12D is hitting your session, with sub-pattern-specific recovery so misapplied /clear doesn't burn context) · [**Cluster 13 Extended-Thinking Wedge Diagnostic**](https://yurukusa.github.io/cc-safe-setup/cluster-13-extended-thinking-wedge-diagnostic.html) (NEW 2026-05-30: 5 questions → which of 13A/B/C/D sub-patterns is hitting you, plus detection of the /loop autonomous-run amplification reported by @LMS927369. Correct env var matrix per cnighswonger's 2.1.148 disassembly — DISABLE_INTERLEAVED_THINKING=1 does NOT actually prevent the failure) · [**Skills Audit Tool**](https://yurukusa.github.io/cc-safe-setup/skills-audit-tool.html) (NEW 2026-05-29: drop your session log, find which Skills never fire — author's own audit: 111 installed, 0 invoked in 10 sessions) · [**Safety Lab Fit Diagnostic**](https://yurukusa.github.io/cc-safe-setup/safety-lab-fit-diagnostic.html) (NEW 2026-05-29: 5 questions → should you subscribe to the ¥500/month CC Safety Lab membership, or are the free hooks here enough?) · [**Token Checkup**](https://yurukusa.github.io/cc-safe-setup/token-checkup.html) (what type are you?) · [**All 8 Tools**](https://yurukusa.github.io/cc-safe-setup/hub.html) · [**Defense Kit**](https://gist.github.com/yurukusa/c44e28ea04acdad7e7ed48c3e01dbb78) (11 incidents → 11 hooks, narrative-per-incident) · [**Drift Matrix**](https://gist.github.com/yurukusa/becd28b2c121ac22e5344a074db530c8) (14 May 2026 cases × 10 hooks, "if I saw X install Y")

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

One user [analyzed 6,852 sessions](https://github.com/anthropics/claude-code/issues/42796) and found the Read:Edit ratio dropped from 6.6 to 2.0, Claude editing files it never read jumped from 6% to 34%. That issue has over 2,100 reactions. The `read-before-edit` example hook catches this pattern before damage happens.

In April 2026, [$1,446 was transferred without authorization](https://github.com/anthropics/claude-code/issues/46828) when Claude moved funds between exchange accounts. A user [lost $367 and got their account suspended](https://github.com/anthropics/claude-code/issues/47046) from a Claude-generated script. [Physical coordinates were uploaded to a public website](https://github.com/anthropics/claude-code/issues/46910) despite 17 sessions of "no PII" in CLAUDE.md. And [deny rules can be bypassed with 50+ subcommands](https://adversa.ai/blog/claude-code-security-bypass-deny-rules-disabled/).

Claude Code ships with no safety hooks by default. This tool fixes that. ([Standalone guard script](https://gist.github.com/yurukusa/87f51b97bb655357dd148b66109d0c14) for quick setup | [Database protection hooks](https://gist.github.com/yurukusa/ad27e541769992e9e0cd15c1b487a1d2) | [Credential protection hooks](https://gist.github.com/yurukusa/7292ead735df0aa673f0485eba5587f3) | [Fabrication detection hook](https://gist.github.com/yurukusa/03f4bbbab61f7ddf31049cc28a01d0d9) | [Security vulnerability hooks](https://gist.github.com/yurukusa/81f79ae6d760b27c17f2cd642ea846d7))

**Works with Auto Mode.** Claude Code's [Auto Mode sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing) provides container-level isolation. cc-safe-setup adds process-level hooks as defense-in-depth, catching destructive commands even outside sandboxed environments.

**Works with subagents.** Since v2.1.84, subagents and teammates [don't receive CLAUDE.md](https://github.com/anthropics/claude-code/issues/40459), your project rules are silently skipped. Hooks operate at the process level, but [subagent tool calls may bypass PreToolUse hooks](https://github.com/anthropics/claude-code/issues/21460) in some configurations. As defense-in-depth, cc-safe-setup installs hooks at the user level (`~/.claude/settings.json`). The `subagent-claudemd-inject` example hook re-injects critical rules into subagent prompts.

### 🚨 Opus 4.7 Crisis (April 2026)

Opus 4.7 broke auto mode's safety classifier, it was [hardcoded to Opus 4.6](https://github.com/anthropics/claude-code/issues/49618). **If you use auto mode with Opus 4.7, dangerous commands run without the built-in safety check.** In 3 days: [50 GB permanently deleted](https://github.com/anthropics/claude-code/issues/49129), [~/.ssh wiped](https://github.com/anthropics/claude-code/issues/49554), [git credentials destroyed](https://github.com/anthropics/claude-code/issues/49539), [shell configs truncated to 0 bytes](https://github.com/anthropics/claude-code/issues/49615). Users report [4x token consumption](https://github.com/anthropics/claude-code/issues/49541) from silent model switches.

**One command to fix it:**

```bash
npx cc-safe-setup --opus47
```

Installs 4 hooks targeting known Opus 4.7 regressions. [Full details →](https://yurukusa.github.io/cc-safe-setup/opus-47-survival-guide.html) · [Emergency Defense Kit (Gist)](https://gist.github.com/yurukusa/6747ea655cc5c374a1ec9ed4fba027e4) · [Safety Scanner](https://yurukusa.github.io/cc-safe-setup/opus47-scanner.html)

### 🚨 The June 15 Billing Cliff (May–June 2026)
Anthropic [splits programmatic billing on 2026-06-15](https://docs.claude.com/en/api/billing) — `claude -p` and SDK invocations route to a separate credit bucket. In May 2026, financial-harm reports started landing on the tracker: [€84.68 over the spending limit from confident-but-false billing claims (#61704)](https://github.com/anthropics/claude-code/issues/61704), [$80 in tokens burned on buggy code presented as working (#61728)](https://github.com/anthropics/claude-code/issues/61728), [tokens wasted on malformed tool calls after assurances they were fixed (#61086)](https://github.com/anthropics/claude-code/issues/61086), [production deployment session with sustained deception (#61699)](https://github.com/anthropics/claude-code/issues/61699). **The model cannot verify Anthropic's own billing logic from its training data.** After June 15, the gap between what the model says about billing and how Anthropic actually bills widens.
**Operator-side defenses available today:**
- **NEW Starter pack** (recommended starting point): [The 5 cc-safe-setup hooks to install today (and why)](https://gist.github.com/yurukusa/825489b6bf73524e1df93facb4236351) — curated entry path through this catalog's ~800 hooks. Picks the five with the highest "value per setup minute" for new operators: `nested-spawn-inflight-guard` (runaway subagent prevention), `bash-fanout-bounded-rewriter` (fan-out inside a single Bash call), `cache-creation-drift-detector` (token spike early warning), `compact-dispatch-watchdog` (silent compaction failure detection), `claim-verify-audit` (one-shot diagnostic of 8 known patterns). Each entry gives What it stops / Why I picked it / Install / Wire-up / Override. Covers macOS, Linux, Windows under WSL2 / Git Bash. ~1,297 words, MIT, 14 verified cited links. Names the five clusters this starter pack does NOT cover and where to read the matching field guides.
- **Free 90-second diagnostic** (interactive): [Did Claude Code charge you wrong?](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/d3a0e2403cc4078aa0183400c137d824/raw/wrong-charge-diagnostic.html) — 5 questions, matches your case to filed reports, produces a refund argument template you can paste into support.anthropic.com. No signup, no telemetry, single HTML.
- **Free billing-axis writeup** (no install): [The Model Can't Verify Its Own Billing](https://gist.github.com/yurukusa/4ca735cb192219581d303afe5f63d2eb) — 4 filed cases, 9-row recognition-without-arrest cluster catalog, 4 operator-side defenses, the refund argument that lands ([日本語版](https://gist.github.com/yurukusa/65d9ce96fab8d767ed0a088fb1e20152))
- **Free Pro Max quota anomaly field guide** (no install): [Pro Max Quota Anomaly — Operator Field Guide](https://gist.github.com/yurukusa/158436e88d169406593d55bd84f0d7e9) — ten-issue cluster snapshot (#16157 / #38335 / #46917 / #45756 / #29579 / #41788 / #13585 / #23706 / #16856 / #19673, ~2,200 cumulative reactions, four version-boundary inflection points), five operator-side measurement paths (ccusage, raw JSONL inspection, claude-code-logger proxy, cc-safe-setup hook integration, Anthropic Console cross-reference) with a pattern-to-path mapping that picks the right tool per symptom. **Three-axis defense hooks now shipped:** `cache-creation-drift-detector` (PR #340), `quota-anomaly-detector` (PR #348), `session-rate-monitor` (PR #349).
- **Free Safety Lab 2026-08 preview** (no install): [When Your Pro Max Quota Empties Faster Than It Should](https://gist.github.com/yurukusa/86913b10332713df380019424f0a50e8) — symptom-to-diagnosis-to-defense walkthrough for the three independent mechanisms behind one surface, with the per-mechanism diagnostic flow and the three-hook installation recipe. Free preview of the 2026-08 chapter; full chapter ships to Safety Lab subscribers on 2026-08-01.
- **Free permission matching cluster field report** (no install): [A 9-Month Enforcement Gap with 30+ Issues and Zero Staff Engagement](https://gist.github.com/yurukusa/7099650644670d4980f7170fbc26950f) — articulation of the 6th cluster tracked in this repo: seven independent failure axes (wildcard compound mismatch, dead-rule accumulation, scope hierarchy break, quote-tracking bypass, deny-rule bypass, syntax contradiction, partial bypass-mode), 25+ issues / ~804 cumulative reactions, meta-issue #30519 articulating the seven axes with 13 referenced sub-issues. **2 of 4 axis-specific hooks shipped 2026-05-27** (`always-allow-pattern-suggester.sh` PR #359 for Axis 2; `bypass-mode-effective-verifier.sh` PR #360 for Axis 7). Shipped-status update with install paths and operator checklists: [Cluster 6 Defense Status Update](https://gist.github.com/yurukusa/2886d513b7e668a70a7e654edf33fa79). Also serves as the working preview for the 2026-09 Safety Lab chapter.
- **Free Safety Lab 2026-05 preview (English)** (no install): [When cache_control Locks Up Your Claude Code Session — and How to Recover the Context](https://gist.github.com/yurukusa/7699c4ca07cfed47d678bd7c04e78060) — symptom-to-diagnosis-to-recovery walkthrough for the 12+ issue cluster (#55369 / #55156 / #55302 / #55283 / #55118 / #54988 / #54421 / #54314 / #53632 / #50738 / #50681 / #50010, etc.) where an empty text block with a `cache_control` marker permanently jams a session. Includes the field-recovery Python script (preserves context), four scenarios where the corruption surfaces, and four prevention practices. English companion to the original [Japanese-language 2026-05 preview Gist](https://gist.github.com/yurukusa/fcfeb14b0b2cae476ebb55b8a9b7975d). This is the 2026-05 chapter of the Safety Lab series; 2026-08 and 2026-09 previews above complete the English-side preview set.
- **Free 2026-05 cluster field report** (no install, comprehensive): [Six Architectural Failure Modes in One Month](https://gist.github.com/yurukusa/6582241e62682e3665c34acc3ee16d86) — original (May 2026) single-Gist entry point articulating six of the seven clusters tracked here (SOH, multi-account, AGENTS.md, Pro Max quota, TUI/Terminal UX, permission matching). The narrative companion to the [Cluster Tracker HTML page](https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html). **Updated synthesis below** covers the 7th cluster (Skills metadata).
- **Free 9-Cluster Framework synthesis** (no install, comprehensive): [The 9-Cluster Framework: Mapping the Structural Failure Surface of Claude Code Operator Defense](https://gist.github.com/yurukusa/f6b5524b0e88fd9443d62fb44ba1619e) — updated (2026-05-28) synthesis covering all nine clusters with the ~11,590 cumulative reactions / 145+ issues snapshot, the mechanism / symptom family / defense path per cluster, three deep structural patterns (documentation-runtime divergence, validation absence, observability absence at the runtime boundary), and how-to-use guidance for four operator scenarios (incident debugging, June 15 billing-split audit, team/production setting, Opus sensitive-workload AUP cluster). 3,300 words. **2026-05-28 update**: Cluster 9 (Usage Policy classifier over-trigger, 25+ open issues filed 2026-05-18 to 2026-05-27, Opus-specific, multilingual false positives) added with corresponding hook shipped same-day.
- **NEW Free Cluster 8 (v2.1.150 server-side prompt injection) defense triple** (no install / three shipped hooks, 2026-05-29): The v2.1.150 release added a function (named `nAA` in the minified source) that reads strings from the `bootstrap` API `client_data` field and the `tengu_heron_brook` GrowthBook feature flag and registers them as peer-level system prompt sections alongside the documented `anti_verbosity` / `thinking_guidance` / `action_caution` sections. Anthropic confirms this is intentional ("we run experiments on our system prompt"); the documented opt-out is `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and `DISABLE_GROWTHBOOK=1`. Reference: [#62061](https://github.com/anthropics/claude-code/issues/62061) (46+ reactions, bytecode-level evidence by @vladkens) and the [v2.1.150 server-side prompt injection audit paths](https://gist.github.com/yurukusa/03839b3c3f88e1cce38fb0f2c127544d) writeup (1,133 words, four audit paths). **Defense triple shipped (3 of 4):** `server-side-prompt-injection-detector.sh` ([PR #383](https://github.com/yurukusa/cc-safe-setup/pull/383)) — SessionStart advisory when either opt-out env var is missing; `cache-residue-detector.sh` ([PR #453](https://github.com/yurukusa/cc-safe-setup/pull/453), 28 tests) — closes the gap that opt-out alone does not perform by detecting cached injection values that persist after opt-out env vars are set; and `proxy-capture-suggester.sh` (2026-05-29, 19 tests) — opt-in SessionStart advisory that surfaces the HTTPS proxy capture path for operators in regulated industries (SOX, HIPAA, FedRAMP, PCI-DSS, EU AI Act Article 12) who need a reconstructible audit trail of the exact system prompt sent at the time of any logged action. When enabled via `CC_PROXY_CAPTURE_SUGGESTER_ENABLE=1`, names four audit tools (mitmproxy with `--save-stream-file`, Burp Suite Community, Charles Proxy, Anthropic SDK `ANTHROPIC_LOG=debug`) with concrete HTTPS_PROXY bridge and SSL_CERT_FILE setup, or — when a proxy is active but `ANTHROPIC_LOG_DIR` is unset — a shorter audit-sink advisory. Privacy: reads only the env var names, never their values. One more audit hook in design: `system-prompt-baseline-checker.sh` (diffs baseline against runtime, requires proxy capture). Also serves as the working preview for the 2026-11 Safety Lab chapter.
- **Free Cluster 9 (Usage Policy classifier over-trigger) field guide** (no install): [Claude Code's AUP False-Positive Cluster: 4 Operator-Side Paths Through It](https://gist.github.com/yurukusa/4fa4751044be45bd83345601ee79c2db) — 1,462-word writeup of the 25+ open-issue cluster (filed 2026-05-18 to 2026-05-27), with the Opus-specific signature, the multilingual / domain-independent evidence, and the four operator-side mitigation paths (Sonnet swap, session warmup, CVP application, retry-on-identical-input). First defense hook shipped 2026-05-28: `aup-false-positive-helper.sh` (PRs #388 and #389, 16 tests, opt-in SessionStart advisory only — never blocks). Second defense hook shipped 2026-05-29: `aup-block-pattern-logger.sh` — PostToolUse advisory-only hook that pairs with the helper by closing the evidence-and-trend gap. Detects five distinct AUP block patterns (`cyber-safeguards`, `safety-guardrails`, `rephrase-rewind`, `usage-policy`, `usage-policy-api` fallback) in tool output and appends a five-field pipe-delimited line to `~/.claude/aup-block-history.log` (timestamp / model / tool / pattern kind / 120-char excerpt). Default mode shows the cumulative count for the current model on stderr so operators can build CVP evidence and notice classifier-shift over time. 23 tests covering all five patterns, pattern priority, log rotation, schema preservation, jq fallback, and never-blocks invariant. Environment toggles: `CC_AUP_BLOCK_LOGGER_DISABLE`, `CC_AUP_BLOCK_LOGGER_QUIET`, `CC_AUP_BLOCK_LOG_PATH`, `CC_AUP_BLOCK_LOGGER_MAX_LINES`. **Third defense hook shipped 2026-05-30**: `model-swap-suggester.sh` — evidence-driven SessionStart advisory that closes the loop between the helper (generic awareness) and the logger (evidence collection) by reading `~/.claude/aup-block-history.log` on session start, counting Opus blocks in a configurable lookback window (default 60 minutes, threshold 3), and emitting a concrete `export ANTHROPIC_MODEL=claude-sonnet-4-7` swap recommendation only when the threshold is crossed. Silent in every other path (model unset, non-Opus pinned, log missing/empty, below threshold, outside window) so it never adds noise to users who have not actually been blocked. Counts all Opus variants in the log (`opus-4-7`, `opus-4-6`, `opus-4-7[1m]`) toward the threshold because the cluster signature is Opus-family-wide. 25 tests covering: env toggle paths (DISABLE / QUIET), model gating (unset / Sonnet / Haiku / Opus), log states (missing / empty / Sonnet-only / mixed), threshold and window semantics (below / at / above / outside), custom env vars (THRESHOLD / WINDOW_MIN / TARGET / garbage fallback), schema robustness (unparseable timestamps skipped without crash), and never-blocks invariant across 8 paths. Environment toggles: `CC_MODEL_SWAP_SUGGESTER_DISABLE`, `CC_MODEL_SWAP_SUGGESTER_QUIET`, `CC_MODEL_SWAP_SUGGESTER_THRESHOLD`, `CC_MODEL_SWAP_SUGGESTER_WINDOW_MIN`, `CC_MODEL_SWAP_SUGGESTER_TARGET`, shares `CC_AUP_BLOCK_LOG_PATH` with the logger. Cluster 9 primary-symptom defense complete (3 of 3 hooks for the block-and-swap path). **Fourth defense hook shipped 2026-05-30** (secondary-pain coverage): `aup-retry-loop-guard.sh` — PostToolUse hook that addresses the retry-loop context-burn pain documented in [#61664](https://github.com/anthropics/claude-code/issues/61664) (Japanese paid user, 2026-05-23: "ブロック発生時も context/credit は消費される", "ブロック→巻き戻し→同じ処理の再実行 で context を浪費"). The first three hooks address awareness / evidence / session-start swap but do not break a retry cycle in progress within a single session. The retry-loop-guard reads `~/.claude/aup-block-history.log` after each tool call, checks whether 3+ blocks (configurable) within a 5-minute window (configurable) all targeted the same tool — the single-tool restriction is the diagnostic signature distinguishing a retry loop from a general session sensitivity. When the pattern fires, emits a one-shot per-session advisory recommending either Option A (`/exit` + restart fresh with Sonnet pinned, safest for quota) or Option B (in-place swap, continues current session). The one-shot lock uses a session identifier resolved in order: `CC_AUP_RETRY_LOOP_GUARD_SESSION_ID` (explicit override), `CLAUDECODE_SESSION_ID`, controlling tty, PPID fallback. 26 tests covering env toggle paths, log states, threshold and window semantics, multi-tool burst rejection, custom target model, one-shot per session with different sessions firing independently, garbage env var fallback, unparseable timestamp skipping, and never-blocks invariant across 7 paths. Environment toggles: `CC_AUP_RETRY_LOOP_GUARD_DISABLE`, `CC_AUP_RETRY_LOOP_GUARD_QUIET`, `CC_AUP_RETRY_LOOP_GUARD_THRESHOLD`, `CC_AUP_RETRY_LOOP_GUARD_WINDOW_MIN`, `CC_AUP_RETRY_LOOP_GUARD_TARGET`, `CC_AUP_RETRY_LOOP_GUARD_STATE_DIR`, `CC_AUP_RETRY_LOOP_GUARD_SESSION_ID`, shares `CC_AUP_BLOCK_LOG_PATH` with the logger. Internal customer-pain research at `~/ops/customer-pain-cluster-9-secondary-pains-2026-05-30.md` (7 secondary pains beyond the primary block symptom; this hook addresses axis 1). **Fifth defense hook shipped 2026-05-30** (secondary-pain coverage continued): `aup-large-tool-output-warner.sh` — PreToolUse hook that addresses the large-security-output trigger surface documented in [#61185](https://github.com/anthropics/claude-code/issues/61185) (filipghoulin, 2026-05-23: "A lab-review skill dispatched a sub-agent that ran `cat /etc/banip/banip.blocklist` on an OpenWRT router. The blocklist has ~17,000 entries. That volume of content in a single tool result, combined with the security shape of the content, appears to have flipped the classifier into a permanent block state for the whole session"). The first four hooks act on the block aftermath (awareness, evidence, swap, retry-loop break); none of them act *before* the offending tool call. Once the classifier fires on a large security-shaped output, the session is already wedged and `/compact`/`/clear` may themselves block — so the only place to address this trigger surface is the PreToolUse boundary. Detects five command shapes that commonly produce large outputs (cat on security-shaped system paths, find recursing under security paths, journalctl/dmesg without size caps, grep -r on security paths) plus a sentinel wordlist (blocklist, denylist, banlist, iplist, iptables-save, ipset save, /etc/banip/, /etc/fail2ban/, /var/log/auth*, /var/log/secure*, firewall.conf) for content that would look security-shaped to the classifier regardless of how it is read. Emits a one-shot per-(session, pattern_hash) stderr advisory recommending narrower variants (`head -N`, `tail -N`, `wc -l`, `grep -c`, `journalctl --since`, `find ... | head`). Skips automatically when the command already has a size cap (head/tail/wc/-n/-quit/--since). 32 tests covering env toggle paths, non-Bash tool skip, empty/malformed input, every category and sentinel, every size-cap skip path, one-shot per-(session, pattern) semantics with different patterns and different sessions firing independently, sentinel-only path (e.g. `iptables-save > /tmp/rules.txt`), advisory content references (#61185, #60366, head -200 recommendation), state directory auto-create, and never-blocks invariant. Environment toggles: `CC_AUP_LARGE_OUTPUT_WARNER_DISABLE`, `CC_AUP_LARGE_OUTPUT_WARNER_QUIET`, `CC_AUP_LARGE_OUTPUT_WARNER_STATE_DIR`, `CC_AUP_LARGE_OUTPUT_WARNER_SESSION_ID`. Internal customer-pain research at `~/ops/customer-pain-cluster-9-secondary-pains-2026-05-30.md` (axis 4: single tool call returning large sensitive-content volume). Cluster 9 five-hook defense surface now covers: helper (axis 0 awareness) + logger (axis 0 evidence) + suggester (axis 0 session-start swap) + retry-loop-guard (axis 1 intra-session retry cycle break) + large-tool-output-warner (axis 4 pre-call large-output prevention). Companion **interactive 4-question diagnostic** at [cluster-9-aup-diagnostic.html](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/ddd7b7487fb114543b33479cacaa36b6/raw/cluster-9-aup-diagnostic.html) outputs the highest-leverage path tailored to your model / frequency / domain / CVP status. Also serves as the working preview for the 2026-12 Safety Lab chapter.
- **NEW Free 13 cost-spike patterns reference** (no install, 2026-05-28): [13 Claude Code Cost-Spike Patterns: 8 from the English market + 5 from 800 hours of operations](https://gist.github.com/yurukusa/ccd2bd793c71521d81eb4cfcd3900755) — 2,077-word integration of the 8 cost-spike patterns documented in the English-language guides (Finout's 8-pattern enumeration, ClaudeFast usage optimization, EasyClaw tokens guide) with 5 additional patterns I have not seen written up elsewhere as of 2026-05-28: CLAUDE.md hooks stderr re-injection (5K–15K tokens/turn), AGENTS.md duplicate context overlap (2K–4K/turn), Pool 2 cliff (12×–175× ratio shift on 2026-06-15), Cowork FUSE-mount context pollution (Cluster 11, Issue #62932 P1), GrowthBook A/B flag override (Cluster 10, Issue #62205). Each of the 13 patterns has symptom / mechanism / defense / citation, with the defense pinned to a specific cc-safe-setup hook where one exists. Three-tier integration (Tier 1: prevention for $8K+ single events; Tier 2: automation for 100K+ sessions; Tier 3: observation for background bloat). Free field reference; the 800-hour operational dataset and per-pattern before/after numbers are in the Japanese [Token Book](https://zenn.dev/yurukusa/books/token-savings-guide) (¥2,500). Companion **interactive 5-question diagnostic** at [cost-spike-pattern-diagnostic.html](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/6e40b1cd01621c6f8019fa439d7f9e37/raw/13-spike-patterns-diagnostic.html) maps you to the 3 most-relevant patterns from the 13 with the cc-safe-setup hook install command for each. No signup, no telemetry, single HTML.
- **NEW Cluster 18 candidate (`/ultrareview` crash burns credit on large PRs — 6-filing accumulation, hook shipped)** (advisory hook shipped, 2026-05-29): Six independent filings within a 72-hour window where `/ultrareview` (cloud-side review feature, 3 free credits / day on Pro) crashes server-side with zero findings returned, yet the operator's daily credit counter is still decremented. Shared error: `Review crashed before producing findings. See session logs for details.` The six filings: [#62696](https://github.com/anthropics/claude-code/issues/62696) (3rd crash burns credit, v2.1.150, anchor), [#62709](https://github.com/anthropics/claude-code/issues/62709) (PR #7 review crashed, 0 findings), [#62787](https://github.com/anthropics/claude-code/issues/62787) (2 consecutive crashes, 2/3 credits burned, 21 files / 84KB diff), [#62876](https://github.com/anthropics/claude-code/issues/62876) (Find phase crash, Setup phase complete), [#63117](https://github.com/anthropics/claude-code/issues/63117) (1 crash decrements credit, 6 files / 2,185 insertions), [#63522](https://github.com/anthropics/claude-code/issues/63522) (same-branch 2 consecutive crashes, 2/3 credits burned). **Three common structural traits**: (1) Large PRs crash at a noticeably higher rate (16+ files or 1,500+ insertions over-represented); (2) Find phase is the failure point — Setup phase completes; (3) Retrying on the same branch burns a second credit for the same crash. **Three operator-side defenses** (the crash is server-side, no hook can prevent it): split the PR before invoking `/ultrareview`; do not retry on the same branch; fall back to `/code-review` (local, no cloud crash exposure). **SessionStart advisory shipped** (this PR): `examples/ultrareview-large-diff-advisor.sh` (22/22 tests passing) — measures current branch diff vs base and surfaces caution / elevated advisories above 6 files or 500 insertions (caution) and 16 files or 1,500 insertions (elevated). All thresholds env-overridable; opt-in QUIET/DISABLE. **Token consumption impact** quantified in the [Token Book Ch18 — /ultrareview の停止で使用枠が消費される集積の候補と利用者の側のトークンへの影響の整理](https://zenn.dev/yurukusa/books/token-savings-guide/viewer/18-2026-05-29-ultrareview-crash-credit) (¥2,500, freshly added 2026-05-29): the failed cloud run plus the local re-review doubles token consumption; the June 15 traffic-pool split routes the failed cloud run through Pool 2 quietly, then double-charges across Pool 1 and Pool 2 when the operator falls back to local. **English field guide** (1,481 words, MIT): [The /ultrareview crash that burns credit: six issues in three days and three user-side defenses](https://gist.github.com/yurukusa/f7363d83e3f4bcbb1bd7cf66a1c64752). Filings count crossed the 4-filing promotion threshold; reactions count (0) has not crossed the 15-reaction threshold yet — tracked as candidate at [cluster-tracker.html](https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html). Internal research document: `~/ops/customer-pain-research-ultrareview-crash-credit-2026-05-29.md`. 2027-06 Safety Lab issue targeted as lead chapter once promotion criteria fully met.
- **NEW Cluster 17 candidate (documented setting fields silently ignored — 4-filing accumulation, sister pattern to Cluster 7)** (no install, 2026-05-29): Four independent filings within a 48-hour window where documented `settings.json` paths or environment variables are silently ignored at runtime — no validation error, no warning, the operator continues believing the setting is applied. **Pair to Cluster 7** which articulates the same validation-pipeline-absence root cause from the opposite direction (fabricated fields silently accepted). The four filings: [#63178](https://github.com/anthropics/claude-code/issues/63178) `--model` flag silently ignored in interactive mode (works in `--print`, v2.1.153), [#63186](https://github.com/anthropics/claude-code/issues/63186) `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` in `settings.json` env block silently ignored at app level (propagates to subprocess only), [#63479](https://github.com/anthropics/claude-code/issues/63479) `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` env var ignored, [#63560](https://github.com/anthropics/claude-code/issues/63560) `~/.claude/settings.json` top-level `model` field silently ignored for interactive sessions (`--model` flag and `ANTHROPIC_MODEL` env var both work). **The common workaround for all four**: switch to env var path via `~/.bashrc` / `~/.zshrc` `export` — the env-var path is honored where the settings.json path silently fails. **Token consumption impact** quantified in the [Token Book Ch17 — 設定の沈黙の無視の集積と利用者の側の token への影響の整理](https://zenn.dev/yurukusa/books/token-savings-guide/viewer/17-2026-05-29-settings-silently-ignored) (¥2,500, freshly added 2026-05-29, 14,267 chars): autocompact misfire produces context bloat (+15-30% cache_creation rate), 1M-context continuation produces 1.8-2.4× token consumption vs intended 200K mode, model-misroute produces 8-15% retry rate. **June 15 cliff impact**: with Pool 2 overage pricing post-2026-06-15, the same silently-ignored settings produce 1.5-5.5× cost amplification vs the pre-cliff baseline (Token Book Ch17 §17.8). Filings count crossed the 4-filing promotion threshold; reactions count (0) has not crossed the 15-reaction threshold yet — tracked as candidate at cluster-tracker.html. Internal research document: `~/ops/customer-pain-research-settings-silently-ignored-2026-05-29.md` (four product hypotheses including the cc-safe-setup `settings-effective-state-checker.sh` hook in design for June 2026). 2027-05 Safety Lab issue targeted as lead chapter once promotion criteria fully met.
- **NEW Free Cluster 16 (v2.1.154+ `system` role serialized into `messages` array — promoted same-day) field guide** (no install, 2026-05-29): [v2.1.154+ Serializes `system` Role into `messages[]` — A Field Guide to Cluster 16 with Operator Workaround](https://gist.github.com/yurukusa/05c120466996734f7bc2ad6d41fdedec) — ~2,786-word English-language writeup. Promoted from candidate to full cluster status at 17:30 JST after the filing count crossed the threshold within 48 hours of v2.1.154 release. Claude Code v2.1.154 onward serializes `system`-role entries (from SessionStart hook context, plugin context, Skill metadata, or compaction summaries) as peer entries inside the `messages[]` array instead of the top-level `system` field, producing `API Error: 400 messages[1].role must be either 'user' or 'assistant', but got 'system'`. Four sub-patterns: **16A** custom agents via `/agents` ([#63457](https://github.com/anthropics/claude-code/issues/63457), 2026-05-29, clean rollback to v2.1.153 fully resolves), **16B** strict Anthropic-compatible providers ([#63366](https://github.com/anthropics/claude-code/issues/63366) + [#63469](https://github.com/anthropics/claude-code/issues/63469) 5 reactions, has-repro, raw API body captured via `OTEL_LOG_RAW_API_BODIES`), **16C** VS Code extension ([#63473](https://github.com/anthropics/claude-code/issues/63473) + [#63510](https://github.com/anthropics/claude-code/issues/63510), same defect propagates through the shared request-assembly path), **16D** long-lived session context operations ([#63396](https://github.com/anthropics/claude-code/issues/63396) Variant 1, compact/clear/model-switch produces invalid `messages[0]` with role `system`). Cross-language confirmation via [#63395](https://github.com/anthropics/claude-code/issues/63395) (Chinese-language macOS VS Code report). **Operator-side workaround (the only path until upstream fix)**: pin to v2.1.153 — `npm install -g @anthropic-ai/claude-code@2.1.153` plus `export CLAUDE_CODE_DISABLE_AUTO_UPDATE=1` to prevent auto-update from overwriting the pin. No cc-safe-setup hook can prevent the 400 at request-assembly time — the defect lives in code paths the hook layer cannot reach. A version-pin advisory hook is in design (SessionStart hook detecting v2.1.154+ and emitting the pin command). Sub-pattern 16B is structurally similar to [#52893](https://github.com/anthropics/claude-code/issues/52893)'s class of provider-side schema-strictness regressions — operators routing through `ANTHROPIC_BASE_URL` to non-Anthropic providers experience a sharper failure mode (request never lands) than operators on the official API endpoint. Tracking [#63469](https://github.com/anthropics/claude-code/issues/63469) as the anchor case for upstream resolution signal; expected fix in v2.1.157 or later. 2027-04 Safety Lab issue may be re-scoped to dual-feature Cluster 14 and Cluster 16 given recency and operator urgency.
- **NEW Free Cluster 15 (Non-English Language Quality Regression) field guide** (no install, 2026-05-29): [Non-English Language Quality Regression in Claude Code (Opus 4.7 / 2.1.121+) — A Field Guide to Cluster 15](https://gist.github.com/yurukusa/9b882f7009d36ad5477c46f890272acc) — ~3,126-word English-language writeup articulating the four sub-patterns, the rigorous Kiwi-based methodology that anchors #62961, the structural reason hooks cannot reach this failure mode (the defect lives in the model's training-data distribution, upstream of every client-side surface), the three operator-side mitigations (model downgrade, system-prompt register enforcement, post-hoc frequency analysis via Kiwi or equivalent per language), the comparison to other recovery-surface-narrow clusters (especially Cluster 13's session-killing analog), and the practical sequence for English-speaking operators managing teams with non-English-speaking members. Also tracked at [cluster-tracker.html#cluster-nonenglish-quality](https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html#cluster-nonenglish-quality) — four sub-patterns across two languages on Opus 4.7 / Claude Code 2.1.121+: **15A** Korean register drift ([#62961](https://github.com/anthropics/claude-code/issues/62961), 7 reactions, has-repro, area:model — Kiwi morpheme analysis across 4,666 sessions / 114.9M output tokens documents the verb `박다` (informal "hammer in" used where formal verbs `명시하다` / `기록하다` / `삽입하다` would be expected) at 18× baseline frequency after v2.1.132, persisting through v2.1.143), **15B** Korean lexical fixation (`영역` repeatedly inserted into unrelated output, [#54339](https://github.com/anthropics/claude-code/issues/54339), v2.1.121 + Opus 4.7), **15C** Korean in-vivo self-diagnosis limit ([#57748](https://github.com/anthropics/claude-code/issues/57748), the model cannot reliably self-diagnose the regression from inside the affected mode), **15D** Turkish English-templated structure ([#57233](https://github.com/anthropics/claude-code/issues/57233), six error categories — calque, word order, register, grammatical particles, idiom literalism, context-inappropriate vocabulary — traced to "English-templated reasoning lexically translated rather than native Turkish generation"). The unifying root cause, articulated by reporters in both languages from the model's own self-explanation: "training data is heavily English-weighted; internal patterns follow English structures; non-English output is generated by lexically substituting target-language words onto English skeletons." **1 shipped advisory hook** (updated 2026-05-30): `non-english-quality-warner.sh` ([PR #487](https://github.com/yurukusa/cc-safe-setup/pull/487), 20 tests passing). SessionStart advisory, fully opt-in via `CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1` (silent by default to avoid noise for English-language operators). When opted in, emits a non-blocking stderr advisory naming the three operator-side workarounds (model downgrade with concrete `export ANTHROPIC_MODEL=claude-sonnet-4-7` command, system-prompt register enforcement with Korean and Japanese rule-shape examples, post-hoc Kiwi-equivalent frequency analysis). Acknowledges the server-side nature of the defect (no client fix), cites #62961 and the 18× signal, references the field guide gist, and explains how to disable once the operator has chosen a workaround or verified the regression is patched for their workflow. The hook does not invent a new mitigation — it surfaces the existing operator-side paths at session start so the operator notices the situation before shipping documents containing slang verbs in formal contexts. The cluster is upstream-only and the defect remains in the model's training-data distribution; the hook's value is **detection latency reduction**, not defect repair. Recovery surface is still the narrowest of all 15 clusters. Two more hooks remain in design (model-downgrade advisory for sessions detected as non-English-heavy, Stop-time per-language frequency analysis runner). 2027-03 Safety Lab issue targeted as lead chapter.

- **NEW Free Cluster 11 (Cowork) field guide** (no install, 2026-05-30): [Cluster 11: Cowork (Desktop Sandbox + Remote Control) — Claude Code field guide](https://gist.github.com/yurukusa/3e8d653171744ed2da78a73f399359ed) — 1,902-word English writeup articulating the seven sub-cluster axes of the largest aggregate cluster in May 2026 (237 open Cowork-related issues in 17 days, intake at 14/day with 21% of those filed in the last 48 hours). The four original sub-clusters (11A filesystem/mount, 11B platform/binary, 11C subscription/access, 11D infrastructure incident) plus three new axes that emerged in the 48-hour expansion since the 2026-05-28 articulation: **11E** hooks do not run in Cowork ([#63360](https://github.com/anthropics/claude-code/issues/63360), [#63047](https://github.com/anthropics/claude-code/issues/63047)) — the operator's CLI-side hook defenses do not protect them inside the Cowork sandbox, **11F** handoff silent failure ([#63307](https://github.com/anthropics/claude-code/issues/63307), [#63809](https://github.com/anthropics/claude-code/issues/63809)) — long-running spawned sessions and inter-session handoffs lose their results (the SOH pattern at the Cowork boundary), **11G** silent authentication expiry ([#63185](https://github.com/anthropics/claude-code/issues/63185)) — 3P Bedrock SSO credentials silently expire without triggering re-auth on day 2+. Three shipped CLI-side defense hooks (`cowork-claude-md-load-checker` PR #409, `cowork-fuse-staleness-watcher` PR #410, `cowork-model-picker-advisor` PR #411). The fundamental limit: CLI-side hooks run outside the Cowork sandbox while the failures happen inside it, so the hooks can warn before the operator switches into Cowork but cannot intercept failures originating entirely inside the sandbox. Three operator-side filters for the adoption decision: (1) if you rely on CLI hooks for cost/safety control, defer Cowork until #63360 ships; (2) if your sessions span multiple days with SSO auth, build a daily re-auth checkpoint; (3) if you depend on the FUSE mount for git ops, install `cowork-fuse-staleness-watcher` before you start and prefer ref-walking ops over working-tree ops.
- **NEW Free Cluster 14 (Silent Data Loss) field guide** (no install, 2026-05-29): [Silent Data Loss in Claude Code — A May 2026 Cluster Across Three Axes](https://gist.github.com/yurukusa/9997820b03732d62699145f174fde35b) — ~1,617-word writeup of 18+ open-issue cluster filed 2026-05-23 through 2026-05-28, all labeled `data-loss` or matching the failure shape, splitting cleanly into three structural sub-axes: **14A** silent transcript garbage collection ([#62041](https://github.com/anthropics/claude-code/issues/62041), [#62272](https://github.com/anthropics/claude-code/issues/62272), [#62959](https://github.com/anthropics/claude-code/issues/62959), [#61852](https://github.com/anthropics/claude-code/issues/61852), [#61952](https://github.com/anthropics/claude-code/issues/61952) — "~20 sessions lost, 2 months of paid work gone", [#62997](https://github.com/anthropics/claude-code/issues/62997), [#63082](https://github.com/anthropics/claude-code/issues/63082), [#63187](https://github.com/anthropics/claude-code/issues/63187)); **14B** consent-boundary collapse on destructive commands (`rm -rf` / `git clean -fd` / `git reset --hard` against paths the user did not explicitly allowlist); **14C** Edit/Write file corruption (silent truncation, encoding corruption — the CJK U+FFFD case [#43746](https://github.com/anthropics/claude-code/issues/43746) is the closed canonical example). **Shipped defense for sub-axis 14B**: `consent-boundary-defender.sh` ([PR #344](https://github.com/yurukusa/cc-safe-setup/pull/344)) — PreToolUse hook on Bash `rm` / `git clean` / `git reset --hard` / `git checkout -- .` commands that refuses the call when the target path is outside the explicitly allowlisted `CC_CONSENT_PATHS` environment variable. Two more advisory hooks in design (14A sidecar copy Stop hook, 14C size-mismatch advisory). Sub-axis 14A is structurally hook-difficult because the deletion is performed by client-internal scheduling, not via a tool call any hook can see — backup hygiene (Time Machine, rsync.net, periodic tar to a separate disk) is the durable operator-side mitigation for that sub-axis. 2027-04 Safety Lab issue targeted as lead chapter.
- **NEW 2026-05-31 Cluster 21 candidate — Plugin lifecycle integrity gap** (1 hook shipped, 5 axes upstream-only): Five independent filings on 2026-05-30 across v2.1.156 / v2.1.157 / v2.1.158 articulating six sub-axes of one structural cluster — the plugin extension surface has missing lifecycle events, gaps in cleanup paths, and silent state corruption that compounds across multi-agent sessions. **21A** additive hook-registration growth ([#64022](https://github.com/anthropics/claude-code/issues/64022), observed 1× → 122× per hook in multi-agent sessions, plugin's own scripts audited — no additive writer, the harness re-runs the plugin-hook load/merge and appends instead of replacing); **21B** variable expansion gap ([#64074](https://github.com/anthropics/claude-code/issues/64074), `${CLAUDE_PLUGIN_ROOT}` expands in hooks but not in the `statusLine` execution context); **21C** cleanup gap ([#64074](https://github.com/anthropics/claude-code/issues/64074), `/plugin uninstall` leaves the `statusLine` entry in `settings.json` — zombie bar after uninstall); **21D** signal gap ([#64017](https://github.com/anthropics/claude-code/issues/64017), `SIGTERM` termination including `timeout` wrapper kills the CLI without firing the Stop hook, external supervisor reads prior-run hook output as if it were current); **21E** environment gap ([#64064](https://github.com/anthropics/claude-code/issues/64064), Stop hooks fail with `node: command not found` and missing plugin directories — hook execution shell does not inherit interactive PATH); **21F** startup gap ([#64018](https://github.com/anthropics/claude-code/issues/64018), no `Startup` / `SessionInit` hook event fires before a conversation exists — statusLine plugins cannot pre-initialize, visible empty status bar at initial prompt). **One operator-side hook shipped 2026-05-31** for the only axis with a non-upstream defense path: `plugin-hooks-json-bloat-detector.sh` ([PR #511](https://github.com/yurukusa/cc-safe-setup/pull/511), SessionStart, 15 tests including the exact 122× growth case from #64022). Walks every `~/.claude/plugins/cache/**/hooks/hooks.json` at session start, counts duplicate command strings per event bucket (PreToolUse / PostToolUse / Stop / etc are counted separately so legitimate cross-event registrations don't trip the detector), warns when any single command exceeds `CC_PLUGIN_HOOKS_BLOAT_THRESHOLD` (default 5) per event, with plugin path / event / command / count in the warning. Fail-soft on JSON errors, hourly debounce, advisory only (`exit 0`). Hooks 21B–21F are upstream-only fixes — the harness needs to provide the missing lifecycle events, variable expansion, cleanup cascade, and signal-handling — though an operator-side detector for 21D (Stop-hook silent on SIGTERM) is shippable via a wrapper that writes its own termination marker before reading any hook output and is on the next-PR list. Tracked at [cluster-tracker.html](https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html). Same structural-cluster shape as Cluster 7 / Cluster 17: validation pipeline and lifecycle pipeline both have unmonitored silent-divergence paths.
- **NEW 2026-05-31 Cluster 13 extension** (no install): [Cluster 13 — 2026-05-31 Extension: Two New Trigger Surfaces, One Candidate Sub-Pattern, and the Fleet-Onset Confirmation](https://gist.github.com/yurukusa/2764fff5e4721565350739a67d1d2eab) — ~2,700-word delta document folding in three new data points from the past 72 hours: (a) Benjamin-Sterrett's confirmation of sub-pattern 13C on Opus 4.8 with **two new trigger surfaces** (mixed-tool-type cancellation `Bash + TaskCreate`, blocking-poll cancellation `Bash(sleep 120; …)`) — the mixed-tool result places the corruption on the parallel-batch cancellation path itself, killing the "Bash-streaming-specific" hypothesis; (b) MMoMM-org's post-`/clear` 400 that doesn't fit cleanly into 13A–13D, tracked as candidate sub-pattern **13H** pending disambiguation; (c) **fleet-onset 2026-05-28 confirmation on `claude-opus-4-8`** tying the cluster surge directly to the 4.8 rollout (consistent with #63412). Updates the operator-side mitigation framework to six tiers, articulates three token-consumption cost surfaces, revises the operator-advisory-hook coverage matrix. Companion to the original Cluster 13 field guide below.
- **NEW Free Cluster 13 (Extended-Thinking Session Wedging) field guide** (no install, 2026-05-29): [Extended-Thinking Session Wedging — A 36-Hour Surge with 4 Sub-Patterns and Operator-Side Recovery Paths](https://gist.github.com/yurukusa/8c6be069f602399238356a9c9b719a45) — ~2,800-word writeup of the 15+ open-issue cluster filed 2026-05-28 onward, ~140 combined reactions on the central cases, reproduced across Claude Code v2.1.143, v2.1.150, v2.1.153, v2.1.154 — version-independent. Four sub-patterns sharing one root failure mode (thinking-block serialization not surviving the round-trip): **13A** resume serialization corruption ([#63147](https://github.com/anthropics/claude-code/issues/63147), 33 reactions, canonical root-cause analysis by @jdrolls), **13B** cancel-during-AskUserQuestion poisoning ([#63143](https://github.com/anthropics/claude-code/issues/63143)), **13C** parallel-tool-batch cancellation corruption ([#63192](https://github.com/anthropics/claude-code/issues/63192)), **13D** intermittent signed-thinking-block replay ([#63335](https://github.com/anthropics/claude-code/issues/63335) + 10+ duplicate-flagged reports). Once triggered, the corrupted assistant message lands in transcript history; every subsequent turn re-sends and re-fails identically. `/exit` or `/clear` are the only escapes — both at the cost of the session's working context. **Two defense hooks shipped (2026-05-29 and 2026-05-30)**: `extended-thinking-resume-warning.sh` ([PR #445](https://github.com/yurukusa/cc-safe-setup/pull/445), 54 tests) — SessionStart hook that detects the 13A precursor shape (thinking blocks with empty text but non-empty signature) in the transcript and emits a non-blocking advisory before resume actually fires the 400. Plus `extended-thinking-loop-guard.sh` (49 tests, shipped 2026-05-30) — opt-in BLOCKING SessionStart complement that addresses the LMS927369 amplification reported [in the #63147 thread on 2026-05-29](https://github.com/anthropics/claude-code/issues/63147#issuecomment-4571317923): under `/loop` or other autonomous-resume harnesses, the one-time 13A failure becomes an unrecoverable infinite loop because nobody is watching stderr in the moment and the non-blocking advisory cannot break the retry cycle. The loop-guard hook is a silent no-op by default (safe to drop into broadly-applied `settings.json`); it arms only when the operator declares autonomous-run intent via `CC_LOOP_GUARD_ENABLED=1`, then exits 2 with a decision block when the precursor is detected so the blocking exit propagates into the loop layer. Three more advisory hooks in design for 13B/13C/13D, targeting June 2026. The cluster's recovery surface is structurally narrower than earlier clusters because the serialization (13A) and cancellation paths (13B, 13C) happen inside Claude Code's transcript writer and streaming-response handler, where hooks cannot reach. Complementary post-hoc transcript repair tool: [`miteshashar/claude-code-thinking-blocks-fix`](https://github.com/miteshashar/claude-code-thinking-blocks-fix) — for operators currently in a wedged session, this is the recommended entry point. Also serves as the working preview for the 2027-02 Safety Lab chapter.
- **NEW 2026-05-30 morning: Cluster 13 extension — three new sub-patterns and 13G defense hook shipped**: 48 hours after the original Cluster 13 field guide above, the open-issue count crossed 180+ with 50+ new filings in the 5/28–5/29 window. Three new sub-patterns emerged that don't fit cleanly under 13A–13D: **13E** Dynamic tool loading (`ToolSearch`) re-modifies signed thinking blocks every turn ([#63792](https://github.com/anthropics/claude-code/issues/63792)) — not a session wedge but a per-turn strip-and-retry cascade burning latency and tokens. **13F** v2.1.154 context-ops (`/compact`, `/clear`, model-switch) emit `system` role at `messages[0]` plus modified signed thinking blocks ([#63396](https://github.com/anthropics/claude-code/issues/63396)) — overlaps with Cluster 16 but distinct via the simultaneous thinking-block corruption. **13G** Opus 4.7→4.8 mid-conversation model-swap incompatibility ([#63607](https://github.com/anthropics/claude-code/issues/63607), [#63606](https://github.com/anthropics/claude-code/issues/63606), [#63612](https://github.com/anthropics/claude-code/issues/63612), [#63412](https://github.com/anthropics/claude-code/issues/63412)) — error text differs (`must remain as original response`, not `cannot be modified`), strip-on-retry does NOT recover, stay-on-4.7 + pin-2.1.152 is the only known full fix. **Third defense hook shipped 2026-05-30**: `opus48-thinking-wedge-advisor.sh` ([PR #471](https://github.com/yurukusa/cc-safe-setup/pull/471), 34 tests) — Notification hook that detects the 13G transition shape (Opus 4.7 → Opus 4.8 model swap with prior signed thinking blocks in the transcript) and emits a stay-on-4.7 advisory with the four central issues referenced. Complements `model-version-change-alert.sh` (which fires on any model change) by articulating the 13G-specific failure mode and workaround. The deep synthesis comment on [#63147](https://github.com/anthropics/claude-code/issues/63147#issuecomment-4580358273) consolidates all seven sub-patterns (13A–13G) with the three escalating operator-side workaround tiers. Three more advisory hooks remain in design for 13B/13C/13E, targeting June 2026.
- **UPDATED 2026-05-29: Free Cluster 12 (Tool Call Parsing failures in Opus 4.7) field guide with four shipped defensive hooks**: [Tool Call Parsing Failures in Opus 4.7 — A Five-Issue Cluster with Four Shipped Defenses](https://gist.github.com/yurukusa/12f64f34cef016917824af913bc6f1b8) — 2,860-word writeup of a five-issue cluster filed 2026-04-17 to 2026-05-27 where Opus 4.7 emits tool calls the harness cannot parse, and the failure recurs deterministically across retries. Central case [#62123](https://github.com/anthropics/claude-code/issues/62123) (21 reactions). Four independent root-cause hypotheses pinned by separate filings, **each now with a shipped advisory hook in this repo**: in-context few-shot poisoning ([#62344](https://github.com/anthropics/claude-code/issues/62344), defense [PR #406](https://github.com/yurukusa/cc-safe-setup/pull/406): `long-session-malformed-tool-call-detector.sh`, 40 tests), extended-thinking serialization defect ([#62467](https://github.com/anthropics/claude-code/issues/62467), defense [PR #419](https://github.com/yurukusa/cc-safe-setup/pull/419): `extended-thinking-tool-use-mismatch-detector.sh`, 43 tests), spurious malformed notice ([#62700](https://github.com/anthropics/claude-code/issues/62700), defense [PR #423](https://github.com/yurukusa/cc-safe-setup/pull/423): `spurious-malformed-notice-detector.sh`, 53 tests), and the legacy XML format mix precursor ([#49747](https://github.com/anthropics/claude-code/issues/49747), defense [PR #424](https://github.com/yurukusa/cc-safe-setup/pull/424): `xml-format-leak-detector.sh`, 58 tests). The four hooks together cover all four sub-patterns at the advisory level — the recovery surface is structurally narrow because hooks cannot reach the model attention / harness parser / serialization layers where failures originate, but the hooks tell operators *which sub-pattern they are seeing* so the right recovery is applied (misapplied `/clear` on 12B or 12C burns context for no benefit). The gist's section 5 documents copy-paste install for all four hooks. Also serves as the working preview for the 2027-01 Safety Lab chapter.
- **Free design philosophy articulation** (no install, comprehensive): [Operator-Side Defense as a Wrapper Layer: A Pattern for Cooperating With Broken Upstream Subsystems Without Replacing Them](https://gist.github.com/yurukusa/c51fedd9b51079c35c62a74f08bf7816) — articulates the principle behind all 790+ hooks in this repo: wrap broken upstream subsystems rather than replace them in user-space. Three wrapper sub-patterns (advisory-only / receipt-emitting / validation-gating), two case studies (Cluster 6 axis-defense suite — 5 of 5 axis-specific hooks now shipped as of 2026-05-29 — vs Cluster 1 receipt-emitting hooks), three failure shapes where wrapping is not enough, and a four-check evaluation framework for third-party hooks before installing. Especially useful when choosing between installing a hook from this repo and writing your own. 2,791 words.
- **NEW Free Claude Code book selector** (5-question interactive, browser-only, 2026-05-29): Five Zenn books ship under similar-sounding titles (incident prevention, token savings, AGENTS.md interop, Skills, June 15 cliff survival). This 5-question tool maps your specific pain × usage stage × monthly cost × incident history × budget to one specific book recommendation (or a bundle, or "no purchase, free preview is enough"), with the per-book score shown so you can override the recommendation if you disagree. JP-language, no signup, no telemetry, single HTML → [Which Book Is For Me?](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/cf1066939bc3c2709d4ca614d61fe77e/raw/which-book-selector.html). Background: the five Zenn books (¥500–¥2,500) collectively accumulated ¥10,071 in sales over 3 months (March–May 2026); the highest-volume seller is the Incident Prevention book (¥800, 6 copies sold, 21 chapters including 4 cluster additions in the last week of May). The tool surfaces which book actually fits your situation rather than leaving readers to guess from titles. Includes optional Safety Lab (¥500/month) cross-sell logic for high-monthly-cost or June-15-affected operators.
- **NEW Free Hook Recommender** (5-question interactive, browser-only): narrow the 790+ hooks in this repo to a 3-5 hook starter pack matched to your cluster (1-7 + session-loss + general hardening) × operator setup (solo / consultant / production) × risk concern × existing install × defense style. Each recommendation includes the install command, the settings.json wire-up location, and a wrapper-layer pattern badge (advisory / receipt / validation / enforcement) so you know what shape each hook is before installing. Output never installs anything → [cc-safe-setup Hook Recommender](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/73bcd6b7214fef8fa171738206ff84dc/raw/hook-recommender.html).
- **NEW Free Cluster 10 field report** (no install, 2026-05-29): [Server-Pushed Feature Flags Are Rewriting Your Claude Code State — A field guide to Cluster 10: GrowthBook A/B overrides](https://gist.github.com/yurukusa/69a3fcd4eac07533276b3103c8b21d9d) — 2,487-word articulation of the 58-issue 2-week surge. Three converging axes (periodic ~9-minute re-sync, no release boundary, five documented override paths). Two anchor cases: #62205 traces `tengu_quill_harbor` + `tengu_permission_friction` silently overriding `defaultMode: bypassPermissions`; #63015 traces `tengu_compact_cache_prefix` gating a compaction dispatch path that fails silently while the statusline reports 100% context used. Three shipped operator-side hooks: `growthbook-flag-monitor.sh` (PR #402), `compact-dispatch-watchdog.sh` (PR #413), `permission-mode-drift-guard.sh`. Names the structural limit: the server-pushed dispatch path itself is unreachable from any operator hook surface. Monthly operator checklist. Also serves as the working preview for the 2026-10 Safety Lab chapter.
- **Free Skills metadata cluster field report** (no install): [The Claude Code Skills Cluster: Operator's Field Guide (May 2026)](https://gist.github.com/yurukusa/d00b2d32505ef67572baacbd6fad3d77) — articulation of the 7th cluster: four failure modes (settings fabrication including the canonical `disabledSkills` no-op #62421, frontmatter not honored, discovery mismatch, partial loading and hook integration gaps), nine representative issues from the 14-day window, three detection paths, and four operator-side defenses. Also serves as the working preview for the 2026-10 Safety Lab chapter. **First defense hook shipped:** `skills-settings-validator.sh` (PR #357) detects fabricated Skills-related settings fields at SessionStart.
- **Free TUI / Terminal UX cluster field guide** (no install): [Cluster 5: TUI / Terminal UX — Operator's Field Guide (May 2026)](https://gist.github.com/yurukusa/df2e63ef35c8d9926be00322c184c64b) — survey of the four sub-clusters within Claude Code's terminal UI failure surface (terminal rendering, input handling, display/visibility, missing TUI features), drawn from the 1,229+ open `area:tui` issues. Documents why this cluster has no hook-level intervention (the surface belongs to Anthropic's React-for-CLI implementation) and the workflow-level workarounds operators can apply today.
- **Free June 15 calculator** (browser-only, no signup): paste your last 30 days of usage, get your projected post-June-15 spend → [Pool 2 estimator](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/b78e1cb9234a5d12b27b61c9d82637d9/raw/june-15-pool2-estimator.html)
- **Free June 15 readiness audit** (10-question): get a readiness score (0-100) with each gap mapped to a Migration Playbook chapter → [June 15 Readiness Audit](https://htmlpreview.github.io/?https://raw.githubusercontent.com/yurukusa/cc-safe-setup/main/docs/tools/june15-readiness-audit.html)
- **NEW Free June 15 cost-of-inaction calculator** (5-question, browser-only): quantify what doing nothing about the June 15 billing split will cost over 14, 30, and 90 days, versus the cost of preparing → [Cost-of-Inaction Calculator](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/3ceb225094ab886b3b6d30d10cd760d1/raw/cost-of-inaction-calculator.html). Uses industry-analyzed workload multipliers (12× light → 18× autonomous-Sonnet point estimates within the 12-175× public range) plus an overage-frequency adjustment to project doing-nothing cost, then maps the result to the appropriate next-step companion tool (Pool 2 Estimator if not yet quantified / Readiness Audit if quantified but no plan / Migration Plan Generator if ready to pick a path). Direct API users are flagged as exempt with no action required.
- **NEW 2026-05-30 afternoon: Free Cliff Audit Comparison tool** (5-input, browser-only, no telemetry, MIT): [Cliff Audit Comparison](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/b0d9920c73fdc7e75ee661e57c849d0d/raw/cliff-audit-comparison.html) — paste your past 7-day `ccusage` numbers (notional cost, cache read tokens, total tokens, output tokens) plus your plan and `claude -p` mix, get per-axis verdicts vs my published benchmark ($3,128/week notional, 99.06% cache read ratio, ~0% Pool 2 exposure). Outputs: cost-ratio classification, cache-ratio band (excellent/good/moderate/low), subscription leverage ratio (with break-even threshold), Pool 1 vs Pool 2 split with cliff-impact verdict, and personalized recommendations linking to cc-safe-setup hooks, Migration Playbook chapters, and the pre-cliff baseline logging checklist. Companion to the audit Gist below — use the Gist for context, the tool for your own number.
- **NEW 2026-05-30: Free Public Operator Audit — what 4 weeks of 24/7 autonomous Claude Code actually looks like in numbers** (no install, 2,126 words): [16 Days to the June 15 Cliff: My Own Claude Code Audit](https://gist.github.com/yurukusa/53db7a1fdd8ca7b59b0adbcce78a501c) — actual `ccusage` numbers from my own Pro Max account on 2026-05-30 (16 days before the cliff). Past 7 days: $3,128 notional cost (covered by $200 Pro Max subscription = 15.6× leverage ratio), 99.06% cache read ratio across 4 weeks, ~0% Pool 2 exposure (almost all interactive sessions, no `claude -p` automation). Documents the four hooks I activated specifically for cliff prep (`cache-creation-drift-detector`, `quota-anomaly-detector`, `session-rate-monitor`, `claim-verify-audit`) with the rationale for each. Includes a 5-command audit you can run on your own account in 5 minutes to compare. Public benchmark / sanity check / "what does heavy autonomous use actually cost" reference. MIT, no telemetry.
- **NEW 2026-05-31: Free Cliff Prep for Hobby Claude Code Users — for the readers whose spend isn't producing revenue** (no install, 2,093 words, MIT): [Cliff Prep for Hobby Claude Code Users](https://gist.github.com/yurukusa/3055362bc9857ab2c41fbf69febfb533) — honest counterpart to the public operator audit above. Most cliff guides (mine included) assume the reader is a working operator optimizing setup before June 15. This one is for the camp who pays for Claude Code as a hobby and hasn't tied it to revenue. Three concrete cases (Pro Max + interactive only / Pro Max + a few cron jobs / elaborate automation that doesn't make money) with a minimal cliff-prep checklist per case. Explicit "don't buy my paid products" framing for hobby users — the Migration Playbook ($19) and Safety Lab (¥500/mo) are operator-fit, not hobby-fit. Companion read for the [r/ClaudeAI cost/billing pain survey Gist](https://gist.github.com/yurukusa/b1fa1fb7f900d1f278c0dcad23e23fd9) which identified the hobby-vs-operator split in this week's community discussion.
- **NEW Free post-cliff operator's calendar** (no install, comprehensive): week-by-week navigation guide for the 30 days AFTER June 15 lands — Week 1 (immediate verification of pre-cliff projection vs actual), Week 2 (plan validation with real post-cliff data), Week 3 (execute Plan B/C/D migration if validation says so), Week 4 (measure trend, verify correction held), Week 5 (lock in steady state, document the cycle) → [Post-Cliff Operator's Calendar](https://gist.github.com/yurukusa/94dc7344ac222c89c15521ada164923f). Each week names the specific data to collect, the cluster signals to watch on the tracker, and which hooks become more valuable post-cliff. 2,390 words. Companion to the pre-cliff Pool 2 Estimator and Cost-of-Inaction Calculator above.
- **Free May 22-24 cost catastrophe analysis** (no install): [Three Cost Catastrophes from May 22-24](https://gist.github.com/yurukusa/f87c20636bbb12dfe03d5f0598768937) — structural analysis of $47K/3-day subagent runaway, 887K-tokens/min parallel-49 burn, and $6K-overnight cache-TTL surprise, mapped to three operator-side preventions (cc-safe-setup PR #298, #286, #283)
- **Free deep-dive on the 887K-tokens/min event**: [How Parallel Sub-Agents Multiply Context Beyond Linear Scaling](https://gist.github.com/yurukusa/c4a8e337af75aad3215c322bc69558d2) — the structural reason 49 agents cost 4x linear estimate, and three stacked defense patterns (velocity guard, parallel cap, wall-clock bound)
- **Decision framework**: [Claude Code Migration Playbook ($19, Edition 2 included)](https://yurukusa.gumroad.com/l/claude-code-migration-playbook) — 14 dated triggers, 3 migration paths, decision tree from your daily burn rate to one of stay/switch/hybridize
- **Operator-side defense for sub-agent silent failures (DSSC framework)**: [Sub-Agent Observability Handbook ($19, ships 2026-05-27 — link goes to the Chapter 1 preview Gist until launch)](https://gist.github.com/yurukusa/1c26934ed95f638354f0063df6c05e48) — **D**ispatch fabrication, **S**ilent stall, **S**cope expansion drift, **C**laim-verify gap. Four sub-patterns articulated from a 7-issue 72-hour cluster filed 2026-05-20 to 05-22 (#60987, #61102, #61107, #61167, #61315, #61405, #61547), with one follow-on report on 05-25 (#62161). Each sub-pattern maps to a cc-safe-setup defense hook (PR #283, #286, #298, #282). Average fleet savings $40-150/month per the [Sub-Agent Failure Cost Calculator](https://gist.github.com/yurukusa/1eabc4fee7f3dfb21f083383b53f2f2a). Free diagnostics: [5-question persona-based self-audit](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/58b8e5cbd3efc9bee3046979083d02cb/raw/sub-agent-persona-self-audit.html) (5 min — classifies your operator persona as Solo Casual / Solo Pro / Consultant / Production Fleet, estimates monthly cost of inaction, recommends chapter + hook combination), **NEW** [5-question chapter selector](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/b6aa6a75731c8e4768da71cfee7bd457/raw/soh-chapter-selector.html) (3 min — recommends which of the 7 chapters to read first based on the symptom you're seeing, your operator setup, experience, and what you want from the read; links directly to the relevant free preview Gist), [12-symptom comprehensive checklist](https://gist.github.com/yurukusa/c87e440b6d0ccf8b464d53685a3a30f6) (slower, every symptom in the cluster), [field report (~2,750 words)](https://gist.github.com/yurukusa/a6aa2ae8b952b3644183f119282bf6b1), [hook map (this repo)](https://github.com/yurukusa/cc-safe-setup/blob/main/docs/sub-agent-failure-modes-hook-map.md)
- **Operator-side defense for multi-account workflows** (work + personal, consultants, enterprise multi-org): [Multi-Account Operator Field Guide](https://gist.github.com/yurukusa/d880ecc984af5d664f003daf85f956e3) ([日本語版](https://gist.github.com/yurukusa/13f46cf96093ef487760efcfb2c1c2b8)) — five patterns for the 1,178-cumulative-reaction GitHub cluster (#18435 + #27302 + #36151). Free [7-question interactive self-audit](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/fc73fec611cc277c756e2102e067e807/raw/multi-account-self-audit.html) classifies your persona (work+personal / consultant / enterprise multi-org) and recommends the pattern combination in five minutes. Two new hooks shipping in this repo: `account-routing-preflight.sh` (SessionStart preflight refusal on mismatch) and `account-billing-log.sh` (Stop hook per-session billing log for consultants invoicing clients)
- **AGENTS.md interop for multi-tool teams** (Claude Code + Codex/Cursor/Amp/Aider): [AGENTS.md Operator Field Guide](https://gist.github.com/yurukusa/d36197848911f025add142abefcde685) ([日本語版](https://gist.github.com/yurukusa/8402b4672147381721dffed6d21a4148)) — five operator-side patterns for the 5,185-reaction interop gap ([#6235](https://github.com/anthropics/claude-code/issues/6235), the single largest open feature request on the tracker). Symlink, pre-commit sync, SessionStart hook merge, direnv-based routing, CI drift detection. Free [6-question interactive self-audit](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/bb22e61a75904771e0c88a0335f5fbfa/raw/agents-md-self-audit.html) classifies your persona (solo / mixed-tool team / OSS maintainer) and recommends the pattern combination factoring in drift severity, scale, platform constraints, and tooling appetite. No new tooling beyond Bash, git, and optionally direnv.
- **Stay ahead of failure clusters before they hit your sessions**: [CC Safety Lab Founder Membership (¥500/month, Founder pricing locked)](https://ko-fi.com/yurukusa/tiers) — monthly delivery of 4-8 new clusters with fixes + 1-2 copy-paste defense hooks within 14 days of each cluster's emergence. One avoided Max-plan incident covers a year of membership. June 2026 centers on the 17-day cliff playbook; July centers on the AGENTS.md interop cluster.
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

### Free diagnostic tools

| Tool | What it does |
|------|-------------|
| **[Token Checkup](https://yurukusa.github.io/cc-safe-setup/token-checkup.html)** | 5 questions → find where your tokens are going (30 seconds) |
| **[Security Checkup](https://yurukusa.github.io/cc-safe-setup/security-checkup.html)** | 6 questions based on real incidents ($1,800+ in losses) |
| **[Version Check](https://yurukusa.github.io/cc-safe-setup/version-check.html)** | Is your CC version affected by cache inflation? |
| **[Failure-Mode Cluster Tracker](https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html)** | Public registry of structural failure clusters in Claude Code (SOH, multi-account, AGENTS.md, Pro Max quota, TUI/UX, permission matching, Skills metadata, v2.1.150 server-side prompt injection, AUP false-positive — combined ~11,590 user reactions across 145+ open issues), with shipped defense hooks and upstream status. Updated as clusters evolve. |
| **NEW [Skills Audit Tool](https://yurukusa.github.io/cc-safe-setup/skills-audit-tool.html)** (2026-05-29) | Drop your Claude Code session log (`~/.claude/projects/*.jsonl`), see which of your installed Skills actually fire vs sit idle. The r/ClaudeAI audit (2026-05) found half of installed skills never activate, burning ~23K context tokens per session; this tool quantifies that waste for your specific setup. Browser-only, no upload, no telemetry. The author's own audit: 111 installed skills, 0 invocations across 10 recent sessions, ≈ 5K context tokens wasted per session. |

### Free guides

| Guide | What it covers |
|-------|----------------|
| **[6-hook fortification for the 2026-04 regression cluster](https://gist.github.com/yurukusa/79eeabd11dbfa29d99e7f2a058391286)** | The April 2026 postmortem recap + which 6 cc-safe-setup hooks would have caught each issue. No signup. |
| **[Find which CC versions ran your cache regression sessions](https://gist.github.com/yurukusa/60b21cc133769e0bedab0b828bca4f90)** | One-line `grep + jq` diagnostic over `~/.claude/` logs. Shows per-day per-version count of sessions affected by [#46829](https://github.com/anthropics/claude-code/issues/46829)/[#46917](https://github.com/anthropics/claude-code/issues/46917). |
| **[`/usage --json`: 5 fields, one ratio that decides whether you migrate](https://yurukusa.hashnode.dev/how-to-read-usage-json-5-fields-one-ratio-that-decides-whether-you-migrate)** | `cache_creation_ratio` cheat sheet for the v2.1.118 `/usage --json` output. Five fields and one ratio with HEALTHY / WATCH / TRIGGER bands so you can decide migration timing from your own logs, no third-party dashboard. |
| **[PocketOS 9-second wipe, 3-prevention audit script](https://gist.github.com/yurukusa/f4e9104ff5bb331b21c9446bffb57d91)** | Read-only audit script (Railway / AWS / GCP / GitHub examples) for the three preventions surfaced by the [2026-04-25 PocketOS production-database wipe](https://yurukusa.hashnode.dev/9-seconds-no-backups-what-the-pocketos-wipe-tells-you-to-harden-before-friday) ([HN 817pt](https://news.ycombinator.com/item?id=47911524)). No destructive commands; prints questions and read-only checks you run yourself. |
| **[Postmortems incident #1 free preview, cache TTL regression Signal + Diagnosis](https://gist.github.com/yurukusa/9f597e27d4a44de85d4c8815a84b4f5d)** | Verbatim chapter excerpt from the Postmortems book (live on Gumroad since 2026-05-05). Three read-only checks (one minute total) to tell whether the [March 2026 cache TTL regression](https://github.com/anthropics/claude-code/issues/46829) hit your sessions, no purchase required. |
| **[Copilot 2026-06-01 transition pre-flight checklist](https://gist.github.com/yurukusa/abf63634d1e0b5856bdbdcb378915bd8)** | Five read-only audit steps to run today before GitHub's "Preview my bill" tool launches in early May. Identifies your tier, inventories your past 30-day usage by surface, and stages the stay/switch/hybridize decision tree against your own numbers. No purchase required. |
| **[Five primary-source-verified Claude Code signals (2026-04-26 to 2026-04-28)](https://gist.github.com/yurukusa/751f4c229b2499ba9e005e25c07d002d)** | 48-hour roundup with audit one-liners. [#52921](https://github.com/anthropics/claude-code/issues/52921) (Max 20× weekly limits resetting on a ~24-hour cycle, Anthropic in-app support acknowledged), [#53489](https://github.com/anthropics/claude-code/issues/53489) (Web MCP connectors lost + v2.1.120 force-rolled-back within 24h), [#53262](https://github.com/anthropics/claude-code/issues/53262) (HERMES.md substring routing), plugin hook path drift cluster, and the 2026-04-25 Anthropic Rate Limits API release. Two issues independently primary-source-verified. |
| **[`claim-verify-audit.sh` — 8 diagnostic checks for the May 2026 failure-mode cluster](scripts/claim-verify-audit.sh)** | One-shot read-only audit (single bash file, MIT). Eight checks against documented patterns: 8.3 short-name allow-rule bypass ([#58614](https://github.com/anthropics/claude-code/issues/58614)), skill bloat token tax ([Reddit 1tbbove](https://www.reddit.com/r/ClaudeAI/comments/1tbbove/)), session backup absence ([#58608](https://github.com/anthropics/claude-code/issues/58608)), `.env` subagent inheritance ([#57068](https://github.com/anthropics/claude-code/issues/57068)), auto-compact drift ([#57490](https://github.com/anthropics/claude-code/issues/57490) + [#58373](https://github.com/anthropics/claude-code/issues/58373)), `bypassPermissions` remote override ([#57810](https://github.com/anthropics/claude-code/issues/57810)), `settings.json` JSON validity ([#57491](https://github.com/anthropics/claude-code/issues/57491)), cache-trail forensic ([#58608](https://github.com/anthropics/claude-code/issues/58608)). Each finding cites the source issue + the prevention chapter. Run with `bash scripts/claim-verify-audit.sh` from any working directory. Also published as a [standalone Gist](https://gist.github.com/yurukusa/e2fb2b2dadab456c5396704a485b789c). |
| **[Claude Code Changelog History Viewer](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/7c288653b4cca5b118a394eb581a2b8d/raw/changelog-history-viewer.html)** | Single-page HTML tool that fetches the live `CHANGELOG.md` from `anthropics/claude-code` and compares against a previous snapshot you paste in. Highlights lines silently removed (documented case: 2026-05-21 commit `65d44eb134e6` silently removed the `/workflows` feature entries — see [companion Qiita post](https://qiita.com/yurukusa/items/b3936d68814783b03e16) for the audit). Includes a cron-friendly shell script for daily local snapshots. No telemetry. CC0. |
| **[Claude Code June 15 2026 Billing Cliff Calculator](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/647710117afc58e6c02b1d7a5fb0a284/raw/june15-cliff-calculator.html)** | Single-page interactive estimator for the 2026-06-15 `claude -p` programmatic-usage credit-pool separation. Input your plan tier (Pro $20 / Max 5× $100 / Max 20× $200), estimated monthly API-equivalent spend, and programmatic share — get the projected overage and a severity rating with five defense-path links. No telemetry. CC0. |
| **[Why Claude Code Hits Limits Instantly — 3 causes, 5 defense paths](https://gist.github.com/yurukusa/44e50a81d858134c95a668965db52f73)** | English long-form (~2,200 words). The structural distinction between server-side rate limiting (`Server is temporarily limiting requests (not your usage limit)`) and per-call quota burn (e.g. 2% of monthly usage in a single call, as reported on [r/ClaudeCode 2026-05-23](https://reddit.com/r/ClaudeCode/comments/1tkbh6l/)). Covers v2.1.149 `/usage` per-category breakdown and the June 15 cliff context. Five concrete defense paths with hook references. CC0. |
| **[Margin Lab confirms Claude Code Opus 4.7 degradation since 2026-05-22 — four operator paths before the June 15 cliff](https://gist.github.com/yurukusa/77bf08523bda41132087a03de4523d7a)** | English long-form (~1,700 words). Independent third-party (Margin Lab) statistical confirmation that Opus 4.7 7-day pass rate fell from 65% baseline to 57% (delta -8 points, exceeds the 4.3% threshold at 95% CI on SWE-Bench-Pro daily evals). Cross-source verification with five r/ClaudeCode posts, the parallel Sonnet 4.5 deprecation, and the HN "Codex dethroned" narrative. Pairs the degradation signal with the four operator paths (interactive collapse / `claude -p` optimization / API migration / mixed routing) and a seven-day audit sequence so operators can translate the aggregate signal into a workload-specific decision before 2026-06-15. CC0. |
| **[Margin Lab が示す Opus 4.7 の5月22日からの劣化と6月15日まで残り18日の4つの対応の経路](https://gist.github.com/yurukusa/3cf7df3036c8ec88238091a34b99c709)** | Japanese long-form (約5,800字). Companion to the English Margin Lab Gist above for Japanese operators. Same Margin Lab statistical evidence (65% baseline → 57% 7-day pass rate, -8 points at 95% CI significance) plus cross-source verification, the four operator paths (Migration Playbook v2 framework), and the seven-day workload audit sequence. Cross-links to the opus-degradation-tracker hook (PR #394) for personal eval-log monitoring. CC0. |
| **[The 4-path decision tree for Anthropic's June 15 Claude Code cliff](https://gist.github.com/yurukusa/fac527fedaae98d10d4d4590ad2552fd)** | English long-form (~2,043 words, 2026-05-28). Single-piece walkthrough of the four operator-side response paths to the June 15 Pool 2 split. Articulates each path's fit/doesn't-fit, the M metric (monthly programmatic cost at standard API rates) and three measurement sources, the 15-minute pre-flight audit, and the embedded operator-side flow through the [credit cliff calculator](https://yurukusa.github.io/claude-code-credit-cliff-calculator/) and the new [4-path picker](https://yurukusa.github.io/june-15-path-picker/) (5 inputs → recommended path with reasoning). CC0. |
| **[Interactive 4-path picker (Japanese, 2026-05-28)](https://yurukusa.github.io/june-15-path-picker/)** | Browser-side decision tool. Five inputs (plan / M value / automation frequency / API-rate budget tolerance / technical capacity) → one of four operator response paths (consolidation / `claude -p` optimization / API migration / mixed routing) with reasoning. Complements the [credit cliff calculator](https://yurukusa.github.io/claude-code-credit-cliff-calculator-ja/) (which answers *how much* will you overage) by answering *which path* you should pick. Self-contained HTML, no signup, no tracking. CC0. |
| **[Three layers of operator-side control in Claude Code: prose, permissions, hooks](https://gist.github.com/yurukusa/a6dfd6244c287534ee5524c2bc7d0261)** | English long-form (~2,500 words). Reference for which surface fits which failure shape: Layer 1 (`CLAUDE.md` prose — drifts under context pressure), Layer 2 (`settings.json` permissions — reliable but tool-class granularity), Layer 3 (hooks — out-of-band, can inspect tool args or transcript). Anchored in [#61929](https://github.com/anthropics/claude-code/issues/61929) (inverted-judgment cluster: field-catalog example + AUQ case-3) and the `authorized-reconfirmation-detector.sh` Stop hook (PR #374) as a worked example. Includes a posture matrix and a `PreToolUse` sketch for the field-catalog failure shape. CC0. |
| **[When Claude Code's API breaks your session: 7 failure shapes and the limits of operator-side recovery](https://gist.github.com/yurukusa/81d849c34e4edad34333d3b031db041d)** | English long-form (~2,200 words). 30-day model-API + guardrail-rejection cluster in `anthropics/claude-code`: [#62123](https://github.com/anthropics/claude-code/issues/62123) tool-call parse, [#60366](https://github.com/anthropics/claude-code/issues/60366) `"hi"` triggers Usage Policy, [#62190](https://github.com/anthropics/claude-code/issues/62190) guardrail over-firing, [#61412](https://github.com/anthropics/claude-code/issues/61412) System role 400, [#60133](https://github.com/anthropics/claude-code/issues/60133) socket close, [#59520](https://github.com/anthropics/claude-code/issues/59520) 429 cascade (the only non-recoverable shape), [#55254](https://github.com/anthropics/claude-code/issues/55254) opaque termination. 9 issues / 103 reactions / no overlap with the named operator-side clusters. Stop-hook sketch that classifies failure shape, writes structured audit log, advises retry-vs-restart per signature. Names the limit clearly: operator-side surface is *post-hoc* here, the durable fix is upstream. CC0. |

### Companion log-analysis tools (third-party)

These are unaffiliated projects that pair well with the cc-safe-setup hooks, they read your `~/.claude/projects/` JSONL logs from a *post-hoc analysis* angle, where the hooks here intervene at *pre-execution* time. Use them together if you want both prevention (hooks) and observation (viewers).

| Tool | What it does | License |
|------|-------------|---------|
| **[delexw/claude-code-trace](https://github.com/delexw/claude-code-trace)** (251★) | Real-time viewer for Claude Code session logs, desktop app (Tauri), web UI, and TUI. Browse projects, conversations, tool calls, token usage. Rust + TypeScript + React. | MIT |
| **[Claude Code のログから学びを得る](https://speakerdeck.com/rmizuta3/claude-codenorogukara-xue-biwode-ru)** (slides, JP) | DS perspective on parsing CC logs to learn from agent behavior. JSONL format walkthrough, subagent delegation patterns, EDA examples. By @rmizuta3, GO/DeNA AI Community 2026-03-26. | Public slides |

### Go deeper

| Resource | What you get | Price |
|----------|-------------|-------|
| **[Token Book](https://yurukusa.github.io/cc-safe-setup/token-book.html)** | Cut token consumption in half. CLAUDE.md templates, hook configs, context management, 32 failure patterns with fixes. 44,000+ words from 800+ hours of real operation data. | ¥2,500 (~$17). Ch.1 free |
| **[Migration Playbook](https://yurukusa.gumroad.com/l/claude-code-migration-playbook)** | Stay, switch, or hybridize? Six-week timeline of the April 2026 quota wars + 5 measurable migration triggers + Path A/B/C frameworks + cost forecasting worksheet + decision tree + 48-hour rollback checklist. Edition 1, 105 pages, English. Live since 2026-04-25; free verified-update sweep on 2026-05-08. **Edition 2 live since 2026-05-22** with 4 new triggers, 3 new migration paths (A'/B'/D), and a 9-layer expansion of the claim-vs-reality cluster. Free update for Edition 1 buyers via the Gumroad library. | $19. [Free preview Gist](https://gist.github.com/yurukusa/d66ffbe472df1231b59445f26fd25da9) |
| **[Claim-Verify Handbook (preview)](https://gist.github.com/yurukusa/5242a540c43769df76a448269e2f182b)** | Forensic record of 130 cases (15 main + 115 Appendix D continuing evidence, 233 hours from 2026-05-09 to 2026-05-17 morning, 32-fold acceleration over the 30-day baseline) where Claude Code or its sub-agents claimed success while the underlying runtime did not match. 3-stage framework + 14 operator defenses + 5 detection tools (all 5 implemented and tested, 165+ test cases passing). Anchored by Anthropic's own v2.1.144 release (6 fix items in the silent-failure / silent-override category, articulated by Anthropic itself in the release notes) and the structural-parent Issue #60226 (recognition-without-arrest) with 9 connected cases. Sister product to Migration Playbook Edition 2. **Sales-page activation pending as of 2026-05-28** — preview Gist + self-audit tool below cover the framework; full PDF release date is being finalized. | Free [preview Gist](https://gist.github.com/yurukusa/5242a540c43769df76a448269e2f182b) · Free [5-question pain-type self-audit](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/f7e750b781a634fd7572ceb565bc3f98/raw/cvh-pain-type-self-audit.html) (classifies your dominant pain across settings drift / sub-agent fabrication / version regression / trust-boundary collapse, estimates urgency, routes to matching chapter) |
| **[Sub-Agent Observability Handbook (preview)](https://gist.github.com/yurukusa/bc61438321b369dbd3765e2bd9702a80)** | The 4 silent-failure modes when Claude Code subagents say "task completed" but the session log shows no tool was called. 7-issue cluster timeline (#60987, #61102, #61107, #61167, #61315, #61405, #61547) and 4 distinct sub-pattern articulation: dispatch fabrication, silent stall, absence of observation and control, scope expansion. Each sub-pattern paired with an operator-side defense hook in cc-safe-setup (PRs #282, #283, #286, #298, #299). 73-page PDF, ~180,000 chars, 7 chapters. **Sales-page activation pending as of 2026-05-28** — the title link goes to the English Chapter 1 preview Gist; full PDF release date is being finalized. | Free Gumroad listing pending; all chapter previews remain free: [Ch.1 (EN)](https://gist.github.com/yurukusa/bc61438321b369dbd3765e2bd9702a80) · [Ch.1 (JP)](https://gist.github.com/yurukusa/1c26934ed95f638354f0063df6c05e48) · [Ch.2](https://gist.github.com/yurukusa/a05bcc06584a48cb14a5c12fc3527959) · [Ch.3](https://gist.github.com/yurukusa/e0a57afab7ede21215d4de9fa015f6d5) · [Ch.4](https://gist.github.com/yurukusa/1e5b608805ad8750acc83681fc556b45) · [Ch.5](https://gist.github.com/yurukusa/c348087ae60d624f2bd3ca83d08742d5) · [meta-analysis](https://gist.github.com/yurukusa/9857a9ed407696ba8483b354917ff161) |
| **[Incident Postmortems](https://yurukusa.gumroad.com/l/rhtptb)** | Forensic archaeology of 10 production-level Claude Code incidents (cache TTL, Opus 4.7 silent downgrade, tokenizer inflation, MCP regression, weekly quota reset, /doctor settings corruption, and more), each with reproduction steps, official response analysis, and a detection hook. 100 pages, English. **Edition 2 live since 2026-05-22**. | See [product page](https://yurukusa.gumroad.com/l/rhtptb) for the current price. [Free preview](https://gist.github.com/yurukusa/9f597e27d4a44de85d4c8815a84b4f5d) |
| **[Safety Guide](https://zenn.dev/yurukusa/books/6076c23b1cb18b)** | End-to-end Claude Code safety setup. From first install to overnight autonomous runs. | ¥800 (~$5). Ch.3 free |
| **[AGENTS.md × Claude Code Interop Handbook](https://zenn.dev/yurukusa/books/agents-md-interop)** | The single largest open feature request in `anthropics/claude-code` (#6235, 5,196 reactions, 1+ year unaddressed) is the AGENTS.md gap: Codex, Cursor, Amp, Aider have converged on the AGENTS.md standard; Claude Code still only reads CLAUDE.md. Five operator-side workarounds (symlink, pre-commit, SessionStart hook, direnv, CI detection), three user-mode articulation (individual multi-tool, team mixed-tool, parallel use), three sub-cluster analysis, migration playbook, and copy-paste config templates. ~67,000 chars, 8 chapters. **Live since 2026-05-27**. | ¥1,500 (~$10). Intro + Ch.1 + Ch.2 + Ch.3 free on Zenn. Free [English Chapter 1 preview Gist](https://gist.github.com/yurukusa/523e709c52f2a8d5303e7d9ee9151e0b) (1,093 words) covering the 5,196-reaction cluster, the industry convergence (Codex/Cursor/Amp/Aider), and the year-plus official-response gap. |
| **[CLAUDE.md Audit (service)](./SERVICES.md)** | Written audit of your CLAUDE.md + top-3 fixes, delivered within 48h via this repo's Issue tracker. | $29 (~¥3,980) |
| **[Token Burn Audit (service)](./SERVICES.md#2-token-burn-audit--29-3980)** | Diagnosis of your actual `/cost` output, top 3 waste patterns tied to Token Book Ch.8 symptoms, with per-pattern fixes. 48h delivery. | $29 (~¥3,980) |
| **[CC Safety Lab Founder](https://yurukusa.github.io/cc-safe-setup/safety-lab.html)** | Stay ahead of Claude Code's monthly failure clusters before they hit your sessions. Each issue ships 4-8 new clusters with fixes + 1-2 copy-paste defense hooks within 14 days of each cluster's emergence, plus a deep-dive failure case and an updated safety checklist. One avoided Max-plan incident covers a year of membership. The recurring companion to the one-time books. | ¥500/month, Founder pricing locked. Free Part 1 previews: [May 2026 (9 incident clusters)](https://yurukusa.github.io/cc-safe-setup/safety-lab-may-preview.html) · [June 2026 (June 15 cliff: 7 prep steps + 3 warnings)](https://yurukusa.github.io/cc-safe-setup/safety-lab-june-preview.html) · [July 2026 (overengineering: 16-month corpus + 3 self-checks)](https://yurukusa.github.io/cc-safe-setup/safety-lab-july-preview.html) |

**Why pay?** A Max plan costs $200/month. One token waste incident burns 50–80% of your weekly quota in hours ([#46727](https://github.com/anthropics/claude-code/issues/46727)). One `rm -rf` incident costs days of recovery. The Token Book costs less than 2 hours of Max subscription time, and the CLAUDE.md templates alone can reduce consumption by 40%. **For the recurring track**, one Safety Lab month covers what would otherwise mean reading 50–100 GitHub Issues yourself; one avoided Max-plan incident pays for a year of membership.

**Pick one path.** *Cost out of control?* → Token Book. *Considering a switch (Cursor / Codex / Cline)?* → Migration Playbook. *Tools say "verified" but didn't run?* → Claim-Verify Handbook. *Subagent silent failure?* → Sub-Agent Observability Handbook. *Need to know what's already broken in production?* → Incident Postmortems. *Need to keep up with what's breaking now?* → Safety Lab. *Not sure which fits your specific pain?* → [Free 5-question selector](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/2c4575864412b0da107d302b3d1172ea/raw/which-book-selector-v2.html) (browser-only, no signup).

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
| `pre-compact-transcript-backup` | Full JSONL backup before compaction (protects against rate-limit data loss) | [#40352](https://github.com/anthropics/claude-code/issues/40352) |
| `conversation-history-guard` | Blocks access to session JSONL files (prevents 20x cache poisoning) | [#40524](https://github.com/anthropics/claude-code/issues/40524) |
| `read-before-edit` | Warns when Edit targets a file not recently Read (Read:Edit ratio dropped 70%, [#42796](https://github.com/anthropics/claude-code/issues/42796)) | [#42796](https://github.com/anthropics/claude-code/issues/42796) |
| `replace-all-guard` | Warns/blocks Edit `replace_all:true` (prevents bulk data corruption) | [#41681](https://github.com/anthropics/claude-code/issues/41681) |
| `ripgrep-permission-fix` | Auto-fixes vendored ripgrep +x permission on start (fixes broken commands/skills) | [#41933](https://github.com/anthropics/claude-code/issues/41933) |

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
| `--install-example <name>` | Install from 727 examples |
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
| Block silent memory file edits | `npx cc-safe-setup --install-example memory-write-guard` |
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
| Migrate from Cursor/Windsurf | [Migration Guide](https://yurukusa.github.io/cc-safe-setup/migration-guide.html) |

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

### Keep up with what's breaking next

The hooks in this repo defend against failure patterns that have *already* been articulated. New ones surface every week. As of 2026-05-29, the [cluster tracker](https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html) tracks 12 structural failure clusters across 11,820+ cumulative GitHub Issue reactions on `anthropics/claude-code`. Most-recent example: Cluster 12 (Tool Call Parsing failures in Opus 4.7) was articulated 2026-05-28 from five filings, and the four sub-pattern advisory hooks shipped within 24 hours (PRs [#406](https://github.com/yurukusa/cc-safe-setup/pull/406) / [#419](https://github.com/yurukusa/cc-safe-setup/pull/419) / [#423](https://github.com/yurukusa/cc-safe-setup/pull/423) / [#424](https://github.com/yurukusa/cc-safe-setup/pull/424), 194 tests). The [free Cluster 12 field guide](https://gist.github.com/yurukusa/12f64f34cef016917824af913bc6f1b8) (2,860 words) walks the install path for all four hooks.

If you want this kind of cluster-to-defense walkthrough delivered monthly — 4-8 newly-found incidents with fixes, one deep-dive failure case, 1-2 copy-paste safety hooks, an updated safety checklist, all archived month-by-month — that's the [CC Safety Lab Founder Membership](https://yurukusa.github.io/cc-safe-setup/safety-lab.html) (¥500/month, Founder pricing locked). One avoided Max-plan incident covers a year of membership. Three full Part 1 previews are free to read so you can judge writing depth before subscribing: [May 2026 — 9 incident clusters from the 2026-04-25 → 2026-05-02 window with issue numbers and remediation steps (~6,000 words)](https://yurukusa.github.io/cc-safe-setup/safety-lab-may-preview.html), [June 2026 — June 15 billing cliff preparation with 7 ordered steps and 3 warnings (~6,500 words)](https://yurukusa.github.io/cc-safe-setup/safety-lab-june-preview.html), and [July 2026 — overengineering complexity trap from thecatfix's 16-month corpus (62 issues, 968M tokens, 19% implementation rate) with 3 self-checks and 3 warnings (~6,500 words)](https://yurukusa.github.io/cc-safe-setup/safety-lab-july-preview.html). Parts 2–6 of each issue (cache_control deep-dive with Python recovery script, monthly safety checklist, two copy-paste hooks, related-product updates) ship to subscribers.

## Full Kit

cc-safe-setup gives you 8 essential hooks. Want to know what else your setup needs?

Run `npx cc-health-check` (free, 20 checks) to see your current score. If it's below 80, the **[Claude Code Ops Kit](https://yurukusa.github.io/cc-ops-kit-landing/?utm_source=github&utm_medium=readme&utm_campaign=safe-setup)** fills the gaps, 6 hooks + 5 templates + 9 scripts + install.sh. Pay What You Want ($0+).

**Starter Kit:** Want hooks + settings + templates in one download? The **[Claude Code Safety Kit](https://yurukusa.itch.io/claude-code-safety-kit)** bundles 5 safety hooks, a pre-configured settings.json, CLAUDE.md templates, and 800-hour operation tips. Name your price ($0+).

Or browse the free hooks: [claude-code-hooks](https://github.com/yurukusa/claude-code-hooks)

## Examples

## Safety Audit

**[Try it in your browser](https://yurukusa.github.io/cc-safe-setup/)**: paste your settings.json, get a score instantly. Nothing leaves your browser.

Or from the CLI:

```bash
npx cc-safe-setup --audit
```

Analyzes 9 safety dimensions and gives you a score (0-100) with one-command fixes for each risk.

### CI Integration (GitHub Action)

```yaml
# .github/workflows/safety.yml
- uses: yurukusa/cc-safe-setup@main
  with:
    threshold: 70  # CI fails if score drops below this
```

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
- **sql-bulk-delete-warn.sh**: Warn when DELETE/UPDATE/TRUNCATE runs via psql/mysql/sqlite3/sqlcmd without a row-count safeguard. Catches the Issue #56738 pattern (DELETE WHERE col IS NULL after a regex/UPDATE that silently NULLed nearly every row, wiping 24,472 of 24,475 rows in 5 minutes before autovacuum cleaned the dead tuples). Also flags DELETE/UPDATE without WHERE, TRUNCATE TABLE, and `psql -c` invocations missing an explicit transaction. Strict mode via `CC_SQL_BULK_DELETE_BLOCK=1` ([#56738](https://github.com/anthropics/claude-code/issues/56738))
- **auto-approve-python.sh**: Auto-approve pytest, mypy, ruff, black, isort, flake8, pylint commands
- **auto-snapshot.sh**: Auto-save file snapshots before edits for rollback protection ([#37386](https://github.com/anthropics/claude-code/issues/37386) [#37457](https://github.com/anthropics/claude-code/issues/37457))
- **allowlist.sh**: Block everything not explicitly approved, inverse permission model ([#37471](https://github.com/anthropics/claude-code/issues/37471))
- **protect-dotfiles.sh**: Block modifications to `~/.bashrc`, `~/.aws/`, `~/.ssh/` and chezmoi without diff ([#37478](https://github.com/anthropics/claude-code/issues/37478))
- **scope-guard.sh**: Block file operations outside project directory, absolute paths, home, parent escapes ([#36233](https://github.com/anthropics/claude-code/issues/36233))
- **auto-checkpoint.sh**: Auto-commit after every edit for rollback protection ([#34674](https://github.com/anthropics/claude-code/issues/34674))
- **git-config-guard.sh**: Block `git config --global` modifications without consent ([#37201](https://github.com/anthropics/claude-code/issues/37201))
- **deploy-guard.sh**: Block deploy commands when uncommitted changes exist ([#37314](https://github.com/anthropics/claude-code/issues/37314))
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
- **redundant-read-blocker.sh**: PreToolUse hook on `Read` that detects when the model is about to re-read a file already read in the same session (with the same mtime). Operationalizes [#60283](https://github.com/anthropics/claude-code/issues/60283) ("excessive token consumption — task halted mid-execution with zero output") and the broader quota-leakage cluster ([analysis](https://gist.github.com/yurukusa/303431f8e32fed5081b6b2b89712c991), [audit tool](https://gist.github.com/yurukusa/0dbe97df416c53c43dd699b72f439060)). Default mode warns; strict mode refuses the call.
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

Works on Windows via WSL or Git Bash. Native PowerShell is not supported (hooks are bash scripts).

**Common issue:** If you see `Permission denied` or `No such file` errors after install, run:

```bash
npx cc-safe-setup --doctor
```

This detects Windows backslash paths (`C:\Users\...` → `C:/Users/...`) and missing execute permissions.

See [Issue #1](https://github.com/yurukusa/cc-safe-setup/issues/1) for details.

**Free Windows safety guide:** [Claude Code on Windows — Safety Guide for the Issues That Don't Exist on macOS/Linux](https://gist.github.com/yurukusa/df363bbbc5fea6c2e8d86ea19201c303) (~1,735 words, MIT) — five Windows-specific failure modes from the May 2026 tracker (BSOD with HVCI, runaway PowerShell spawn cascade, empty Bash output, PowerShell unavailable under MINGW64, OAuth paste freeze) with operator-side mitigations and a "WSL2 vs native Windows" decision tree. Written in response to the volume of Windows-specific issues that surfaced during May 2026, including [#62193](https://github.com/anthropics/claude-code/issues/62193) (nested PowerShell spawn → cross-window crash on Windows 11).

## Troubleshooting

**[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: "Hook doesn't work" → step-by-step diagnosis. Covers every common failure pattern.

## settings.json Reference

**[SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md)**: Complete reference for permissions, hooks, modes, and common configurations. Includes known limitations and workarounds.

## Migration Guide

**[MIGRATION.md](MIGRATION.md)**: Step-by-step guide for moving from permissions-only to permissions + hooks. Keep your existing config, add safety layers on top.

## Learn More

- **[Opus 4.7 Survival Guide](https://yurukusa.github.io/cc-safe-setup/opus-47-survival-guide.html)**: 61 known issues (76+ GitHub Issues + CVEs) with fixes: data loss, recursive spawn DoS, billing mismatch, subagent OOM, cache_read anomaly, allowedTools bypass, 1.7x token inflation, classifier failure, thinking summary bugs, 30-min stalls, enterprise hooks bypass, and more. [`npx cc-safe-setup --opus47`](#-opus-47-crisis-april-2026)
- **[Token Book (¥2,500)](https://zenn.dev/yurukusa/books/token-savings-guide)**: Cut token consumption in half. CLAUDE.md optimization, hook-based guards, context management, workflow design. 44,000 words with copy-paste templates. Intro + Ch.1 free. [Details](https://yurukusa.github.io/cc-safe-setup/token-book.html)
- **[Safety Guide (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b)**: Token consumption diagnosis, file loss prevention, autonomous operation safety. From 800+ hours of real incidents. [Chapter 3 free](https://zenn.dev/yurukusa/books/6076c23b1cb18b/viewer/3-code-quality)
- **[800 Hours Operation Record (¥800)](https://zenn.dev/yurukusa/books/3c3c3baee85f0a19)**: Non-engineer running Claude Code autonomously for 800 hours. Failures, recovery, revenue reality. [Chapter 2 free](https://zenn.dev/yurukusa/books/3c3c3baee85f0a19/viewer/2-first-failures)
- **[AGENTS.md × Claude Code Interop Handbook (¥1,500)](https://zenn.dev/yurukusa/books/agents-md-interop)**: The 5,196-reaction feature-request cluster (Issue #6235, 1+ year unaddressed). Five operator-side workarounds (symlink, pre-commit, SessionStart hook, direnv, CI detection), three user-mode articulations, three sub-cluster analysis, migration playbook, and config templates. ~67,000 chars, 8 chapters. Intro + Ch.1 + Ch.2 + Ch.3 free.
- **[Claude Code Skills Practical Recipes (¥500)](https://zenn.dev/yurukusa/books/a1b2c3d4e5f6g7)**: Progressive Disclosure with the 3-layer SKILL.md structure for 40% token reduction. 10 practical recipes (automation, MCP, documentation, testing, team sharing, advanced patterns) from the 20,000-view Qiita Skills deep-dive. Intro + Ch.1 free.
- **[CC Safety Lab Founder (¥500/月, Ko-fi Membership)](https://yurukusa.github.io/cc-safe-setup/safety-lab.html)**: Monthly digest delivered via Ko-fi member-only post. Each issue: 4–8 incidents (with fixes), 1 deep-dive failure case, 1–2 copy-paste safety hooks, updated safety checklist, and product update notes. The recurring companion to the one-time books, one avoided Max-plan incident covers a year of membership. Founder price locked for charter members. Three free Part 1 previews available: [May 2026 — 9 incident clusters from 2026-04-25→05-02, ~6,000 words](https://yurukusa.github.io/cc-safe-setup/safety-lab-may-preview.html), [June 2026 — June 15 billing cliff prep (7 steps + 3 warnings), ~6,500 words](https://yurukusa.github.io/cc-safe-setup/safety-lab-june-preview.html), and [July 2026 — overengineering complexity trap with the 16-month 62-issue corpus and 3 self-checks, ~6,500 words](https://yurukusa.github.io/cc-safe-setup/safety-lab-july-preview.html). Each preview ships the full Part 1 (not a teaser excerpt) so you can judge writing depth before subscribing; Parts 2–6 ship to subscribers.
- **Wiki Guides**: [Token FAQ](https://github.com/yurukusa/cc-safe-setup/wiki/Claude-Code-Token-FAQ) · [CLAUDE.md Best Practices](https://github.com/yurukusa/cc-safe-setup/wiki/CLAUDE-md-Best-Practices) · [Token Optimization](https://github.com/yurukusa/cc-safe-setup/wiki/Token-Optimization-Guide)
- [Cookbook](COOKBOOK.md), 26 practical recipes (block, approve, protect, monitor, diagnose)
- [Official Hooks Reference](https://code.claude.com/docs/en/hooks), Claude Code hooks documentation
- [Hooks Cookbook](https://github.com/yurukusa/claude-code-hooks/blob/main/COOKBOOK.md), 25 recipes from real GitHub Issues ([interactive version](https://yurukusa.github.io/claude-code-hooks/))
- [Skills Guide deep-dive (Qiita, 19K+ views)](https://qiita.com/yurukusa/items/f69920b4a02cf7e2988c), Anthropic's official Skills PDF analyzed with 40% token reduction
- [Japanese guide (Qiita)](https://qiita.com/yurukusa/items/a9714b33f5d974e8f1e8), この記事の日本語解説
- [Opus 4.7 breaking changes deep-dive (Hashnode)](https://yurukusa.hashnode.dev/opus-47-isnt-a-regression-but-your-46-prompts-are-now-broken), Anthropic's 9 breaking changes, 5 workarounds, and the `task_budget` beta nobody mentions. Covers why `thinking-stall-detector` and `claude-md-reinjector` hooks exist
- [v2.1.85 `if` field guide (Qiita)](https://qiita.com/yurukusa/items/7079866e9dc239fcdd57), Reduce hook overhead with conditional execution
- [Deny rules bypass vulnerability (Qiita)](https://qiita.com/yurukusa/items/f9c48bb44569bbf4492e), 50+ subcommands disable all deny rules; hook-based defense
- [Hook Test Runner](https://github.com/yurukusa/cc-hook-test), `npx cc-hook-test <hook.sh>` to auto-test any hook
- [Hook Registry](https://github.com/yurukusa/cc-hook-registry), `npx cc-hook-registry search database` ([browse online](https://yurukusa.github.io/cc-hook-registry/))
- [Hooks Cheat Sheet](https://yurukusa.github.io/cc-safe-setup/cheatsheet.html), printable A4 quick reference
- [Ecosystem Comparison](https://yurukusa.github.io/cc-safe-setup/ecosystem.html), all Claude Code hook projects compared
- [The incident that inspired this tool](https://github.com/anthropics/claude-code/issues/36339), NTFS junction rm -rf
- [How to prevent rm -rf disasters](https://yurukusa.github.io/cc-safe-setup/prevent-rm-rf.html), real incidents and the hook that stops them
- [How to prevent force-push to main](https://yurukusa.github.io/cc-safe-setup/prevent-force-push.html), branch protection via hooks
- [How to prevent secret leaks](https://yurukusa.github.io/cc-safe-setup/prevent-secret-leaks.html), stop git add . from committing .env

### Free Gists

- [settings.json Complete Template](https://gist.github.com/yurukusa/8ec367cf65042bf9fbd83c35931e7ed1), copy-paste ready safety configuration
- [First 3 Safety Steps](https://gist.github.com/yurukusa/72513272be9a4ee29b058e2b08453e1a), 5-minute safety setup from scratch
- [CLAUDE.md Before/After](https://gist.github.com/yurukusa/f9d7df5930bfb6d36a25673e69720f7e), 40% token reduction through better writing patterns
- [Token Savings Cheat Card](https://gist.github.com/yurukusa/cfe44bfbb3756eccaf51660466913a2d), 5 techniques to cut consumption in half
- [Token Consumption Checklist](https://gist.github.com/yurukusa/db8700a9f9fa331d36664df2868274cb), 10-item diagnostic
- [Outage Survival Kit](https://gist.github.com/yurukusa/a0e31171eecb527d0df1d5498bf5f5d0), what to do when Claude Code is down
- [CLAUDE.md Token Optimizer](https://gist.github.com/yurukusa/2b98fd2e90c0c13f6918c9f915e08e27), 35-line template, 40% token reduction (800h tested)
- [Worktree Safety Hooks](https://gist.github.com/yurukusa/98bd43c5d0d8a6ebbf2cf21bfc1e2907), 3 hooks to protect against worktree deletion and cross-tree destruction
- [Opus 4.7 Emergency Checklist](https://gist.github.com/yurukusa/c95efaee4b670e067369ece08092960c), token burn diagnosis + immediate fixes
- [Cache TTL Mitigation Guide](https://gist.github.com/yurukusa/178d3949cd2bd6fbfc275b408f9711d4), #46829 cache TTL change (1h→5m) impact and 4 mitigations
- [Security Checkup Hooks](https://gist.github.com/yurukusa/81f79ae6d760b27c17f2cd642ea846d7), 4 hooks for financial, PII, deny bypass, and background task protection
- [Cache Breakage Fix](https://gist.github.com/yurukusa/fe6ba0a6aee14207f27ecc84419878b4), 2 root causes of prompt cache invalidation (#47107 git status, #47098 session restart)
- [CLAUDE.md Token Optimization Cheat Sheet](https://gist.github.com/yurukusa/556f67c493a2729ce9b1703f5003a227), 5 CLAUDE.md patterns that reduce token consumption with before/after examples
- [Token Troubleshooting Guide](https://gist.github.com/yurukusa/47b8c3eadb77cf74946f450f992ddac2), fix quota drain, cache bugs, 1M context trap. Symptom-based diagnosis with latest issue references
- [Token Optimization Guide (English)](https://gist.github.com/yurukusa/70ff830c0ad3dff83e53be26cd80bd0a), 3 biggest token levers with hook code, practical walkthrough
- [Token Book Sampler: 5 Techniques](https://gist.github.com/yurukusa/4a867ba301b480f996c5b76e4b6a6fbc), free preview of the Token Book, 5 immediate techniques to reduce consumption
- [Token Optimization Checklist](https://gist.github.com/yurukusa/4b75025beee916f9904f56b79eeb1217), 10-step checklist to cut token consumption in half, with hook configs
- [3 Things That Actually Work](https://gist.github.com/yurukusa/621f6d1cc35816df3da2e07876b44e16), CLAUDE.md sizing, cache TTL, subagent control, based on 800h data
- [Cache TTL Diagnostic](https://gist.github.com/yurukusa/3a5bdcfdd295bef17b3ee00978b299f2), 3 patterns that break prompt cache + fixes
- [Token Book Ch.1 Free Preview](https://gist.github.com/yurukusa/de862573f18d1a0a68d411b696dbcb73), Where are your Claude Code tokens going? The 4 layers of token consumption explained
- [Deny Rules Break After 50 Subcommands](https://gist.github.com/yurukusa/0463d240d7b725218289a556414c72a5), the hook that fixes Claude Code's deny rule bypass vulnerability
- [Opus 4.7 Emergency Kit](https://gist.github.com/yurukusa/1970b20fed95a682b72eb6e857e61d30), 5 commands to protect your data from Opus 4.7 regressions (auto mode broken, 23+ data loss incidents)
- [cache_read Billing Bug Guide](https://gist.github.com/yurukusa/d5dc731dbc69e3ca92d69832bed641cb), Opus 4.7 cache_read billed at full rate. Anthropic confirmed. Max plan users losing quota 3-6x faster
- [Opus 4.7 Survival Guide Summary](https://gist.github.com/yurukusa/5d66f0bcfe3fbfc73e6db106e10c533d), 50 known issues with quick reference table, free diagnostic tools, and one-command fix
- [Opus 4.7 Known Issues Quick Reference](https://gist.github.com/yurukusa/2c1effab34a7554130d2704fdac59dff), 26 issues / 43+ GitHub bugs in one table. Severity ratings and direct issue links
- [4 New Critical Issues (April 18)](https://gist.github.com/yurukusa/37c19b5b7f50fd8bbbeda5e1336c352e), DoS via recursive spawn, subagent OOM, billing mismatch, UI/CLI model mismatch
- [トークン消費を半分にする方法](https://gist.github.com/yurukusa/bf4040a905148d9ca02898a53185fae1), 800時間の実測データ＋設定テンプレート（日本語）
- [How to Cut Token Usage in Half](https://gist.github.com/yurukusa/704d5cf9874f553dad5c46fccf53b09f), 800h real data + config templates (English)
- [Compaction Triple Threat](https://gist.github.com/yurukusa/aa15f2065199c6fac4dcd3796fbaf90f), 3 compaction bugs active simultaneously (#50402 + #50467 + #50492)
- [Sandbox Relative Path Bug (CRITICAL)](https://gist.github.com/yurukusa/a98efb6c561f92c82bcd49125af3b32a), denyWrite/denyRead silently ignores relative paths (#50454)
- [27 Token Symptoms Quick Reference](https://gist.github.com/yurukusa/03a379854fa0f8eca091a75f7aab593b), all 27 known token failure modes with top 5 killers table and April 2026 new symptoms
- [Token Saving Checklist (15 Items)](https://gist.github.com/yurukusa/6bd0d0a38a4887fc36475dd1f765ecd1), ordered by impact: critical (30-50%), important (10-20%), good practice (5-10%)
- [Opus 4.7 Survival Cheatsheet](https://gist.github.com/yurukusa/f2d6e261338eeda70f0ed9507f995c13), 46 known problems, quick fixes under 60 seconds, full reference table
- [Token-Usage Leaderboard Anti-Pattern](https://gist.github.com/yurukusa/ac41d467d97f3711129070d8e311db4f), why internal token leaderboards fail (Goodhart's law), 5 better metrics, and the Uber case study (Fortune 2026-05-26: AI budget burnt in 4 months after leaderboard rollout)

### Professional Services

Need help configuring Claude Code safely? [**Safety Setup Service**](https://yurukusa.github.io/cc-safe-setup/services.html), audit, token optimization, and custom hooks by the cc-safe-setup team.

## FAQ

**Q: I installed hooks but Claude says "Unknown skill: claude-code-hooks:setup"**

cc-safe-setup installs **hooks**, not skills or plugins. Hooks run automatically in the background, you don't invoke them manually. After install + restart, try running a dangerous command; the hook will block it silently.

**Q: `cc-health-check` says to run `cc-safe-setup` but I already did**

cc-safe-setup covers Safety Guards (75-100%) and Monitoring (context-monitor). The other health check dimensions (Code Quality, Recovery, Coordination) require additional CLAUDE.md configuration or manual hook installation from [claude-code-hooks](https://github.com/yurukusa/claude-code-hooks).

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

Different goals. claude-token-efficient optimizes CLAUDE.md to make Claude's responses shorter and cheaper. cc-safe-setup prevents dangerous operations (file deletion, credential leaks, force-push). They work well together: use claude-token-efficient for cost reduction, cc-safe-setup for safety. For comprehensive token optimization beyond CLAUDE.md (hooks, context management, workflow design), see the [Token Book](https://yurukusa.github.io/cc-safe-setup/token-book.html).

**Still stuck?** See the full [Permission Troubleshooting Flowchart](https://gist.github.com/yurukusa/b64217ffcb908fa309dbfcfa368cd84d) for step-by-step diagnosis.

## Contributing

**Report a problem:** Found a false positive or a bypass? Open an [issue](https://github.com/yurukusa/cc-safe-setup/issues/new). Include the command that was incorrectly blocked/allowed and your OS.

**Request a hook:** Describe the problem you're trying to prevent (not the solution). We'll figure out the hook together.

**Write a hook:** Fork, add your `.sh` file to `examples/`, add tests to `test.sh`, and open a PR. Every hook needs:
- A comment header explaining what it blocks and why
- At least 7 test cases (block, allow, empty input, edge cases)
- `bash -n` syntax validation passing

**Share your experience:** Used cc-safe-setup and have feedback? Open a discussion or comment on any issue. We read everything.

If cc-safe-setup saved you from a disaster (or just saved you time), a ⭐ helps others find it too.

## Why I keep giving these away

I'm a non-engineer running Claude Code autonomously for 800+ hours. In that span I lost files twice, watched a session burn through 887K tokens per minute, and ate a $569 surprise charge from a misread setting.

Every time, I built a small defensive hook for myself and put it here — free, MIT, no signup. That's roughly 800 hooks across three months.

I expected giving away the hooks would cannibalize my paid books. The opposite happened: a steady trickle of users who tried the hooks ended up buying one of the [5 Zenn books](https://zenn.dev/yurukusa) (¥10,071 total over 3 months, 6 buyers including one who bought all 5, and two readers from outside Japan).

The hooks stay free because the same failure happening to a stranger is the same failure happening to me — just on a different machine. The paid books exist for the parts hooks can't solve: the judgment calls, the timing questions, the trade-offs that no shell script can answer.

— yurukusa, [full story](https://yurukusa-dev.hatenablog.com/entry/2026/05/30/015308) (2026-05-30)

## Affiliate Program

If you write or teach about Claude Code, you can earn 30% commission promoting our paid books and kits. Apply with any Gumroad account, no application form, 30-day cookie window, automatic Gumroad payouts:

- [yurukusa.gumroad.com/affiliates](https://yurukusa.gumroad.com/affiliates)

Eligible products include the [Migration Playbook](https://yurukusa.gumroad.com/l/claude-code-migration-playbook), [Incident Postmortems](https://yurukusa.gumroad.com/l/rhtptb) (live since 2026-05-05), [Token Book EN](https://yurukusa.gumroad.com/l/azrdt) (pay what you want), [Complete Survival Kit](https://yurukusa.gumroad.com/l/poqhoo), [CLAUDE.md Templates](https://yurukusa.gumroad.com/l/iaple), and other Claude Code titles. See each product page for the current price.

## Also by yurukusa

- [quiet life](https://yurukusa.github.io/quiet-life/), Touch the dark. Something alive appears
- [deep breath](https://yurukusa.github.io/deep-breath/), Breathe with the light
- [star moss](https://yurukusa.github.io/star-moss/), Drag to grow

## License

MIT
