# cc-safe-setup
**[日本語の README はこちら / Japanese README](docs/README.ja.md)**

One command to add safety hooks to [Claude Code](https://docs.claude.com/en/docs/claude-code). It installs a set of `PreToolUse`, `PostToolUse`, `SessionStart`, `Stop`, and `SubagentStop` hooks that stop destructive or irreversible operations *before* they run, and that surface silent failures.

```sh
npx github:yurukusa/cc-safe-setup
```

The command is interactive: it shows what each hook does and lets you choose which to install into your `~/.claude/settings.json` (or a project-local `.claude/settings.json`). Nothing is installed without your confirmation. MIT licensed.

> **Why not `npx cc-safe-setup`?** The npm release is stuck at 29.8.0 (2026-04-20) while this repository is at 30.0.4, and the gap is not cosmetic — 29.8.0 lets three destructive commands through that the current code blocks. Details, including the comparison table, are in [The npm release is behind this repository](#the-npm-release-is-behind-this-repository) below.

Reading this in order, rather than by section: **[The Claude Code Safety Field Manual](https://leanpub.com/claude-code-safety-field-manual)** is this repository's documentation laid out as a path — the pre-flight checklist, what each guard actually refuses, how to make one fire on purpose so you can watch it work, and what to read in the log afterwards. About 2,000 words, and the minimum price is zero.

## Install as a Claude Code plugin

The core guard sets are also published as Claude Code plugins from this repository. They install from inside Claude Code and track the default branch, so they do not depend on the npm release at all.

```sh
/plugin marketplace add yurukusa/cc-safe-setup
/plugin install safety-essentials@cc-safe-setup
```

| Plugin | What it blocks |
| --- | --- |
| `safety-essentials` | `rm -rf`, force-push, `git reset --hard`, writes to `.env`, package publish |
| `git-protection` | force-push, direct pushes to `main`/`master`, hard reset, interactive rebase, `git clean -fd` |
| `credential-guard` | writes and edits to `.env` and service-account files, API keys in shell commands |
| `token-guard` | reads over 100KB, a per-session read budget, subagent fan-out, a token budget that asks for `/compact` |

These are the guards only. The example-hook library, `--doctor`, `--audit`, and the rest of the CLI come from the npm package or from this repository directly.

## The npm release is behind this repository

`npx cc-safe-setup` currently installs **29.8.0**, published 2026-04-20. This repository is at **30.0.4**. Publishing is blocked on renewing an npm credential, so npm keeps serving 29.8.0 until that is done.

The gap is not cosmetic. Fed the same JSON on stdin, the guards shipped in 29.8.0 allow three operations that 30.0.4 refuses:

| Command seen by the hook | 29.8.0 | 30.0.4 |
| --- | --- | --- |
| `rm -rf $HOME/x` — home directory reached through a shell variable | allowed | blocked |
| `foo & git reset --hard` — a single `&` used as the separator | allowed | blocked |
| `true && git add .env` — a secret staged through a chained command | allowed | blocked |

29.8.0 on npm ships **698** example hooks; this repository has **914**. The 216 that are missing from the published package include `agents-md-sync-checker`. (Counted 2026-08-26 from the published tarball and this tree.)

To install the current code directly from this repository:

```sh
npx github:yurukusa/cc-safe-setup
```

That resolves to the default branch. To pin an exact revision, append a commit SHA — `npx github:yurukusa/cc-safe-setup#<sha>`. Pin by SHA rather than by tag: the tag names here come from an older numbering that no longer tracks `package.json`.

## Why this exists

Claude Code can run shell commands, edit files, and call tools on your behalf. Most of the time that is fine. But a single command — `rm -rf`, a force-push, `terraform destroy`, `php artisan migrate:fresh`, a `git checkout --orphan` followed by `git rm -rf .` — can destroy work in a way that is not recoverable, and it can happen without an error or a warning.

Claude Code's built-in safety checks match shell-level danger patterns. Many destructive operations do not look like those patterns: a framework verb, a tool-call, or a config file poisoned from outside the tool boundary all slip past. These hooks add a second layer that inspects the operation at the tool boundary and refuses the dangerous ones, while letting normal work through.

## What you need installed

**Nothing from npm** — this package has no dependencies and installs none.

**One JSON reader, though.** A hook is handed its tool call as JSON on stdin, so it needs
something that can read JSON. The eight core hooks try `jq`, then `python3`, then `node`, and
if none of the three is present they print a warning that says they are **not** protecting you,
then allow the command (blocking every call would make Claude Code unusable, which is a
failure, not safety).

The example hooks are stricter about this than the core ones: **798 of the 914 use `jq` with no
fallback** — of the 809 that touch `jq` at all, only 11 fall back to `python3` or `node`. Without `jq` they read an empty command and quietly do nothing — no error, no log
line, and they still appear in your `settings.json`. If you take examples from `examples/`,
install `jq` first.

```sh
jq --version || sudo apt-get install -y jq   # or: brew install jq
```

This used to be described as "dependency-free", which was wrong in the direction that matters:
it let someone on a minimal container believe they were protected when the hooks were reading
nothing. Corrected 2026-08-03 after counting the actual tool calls in the shipped scripts.

## What gets installed

Hooks are small shell scripts. Each is one file, does one thing, and exits with code `2` to block or `0` to allow. They fall into a few groups:

- **Destructive-operation guards** — refuse `rm -rf` on protected paths, force-push, `git reset --hard`, whole-tree `git rm`, framework database resets (`migrate:fresh`, `db:reset`, `prisma migrate reset`), cloud teardown verbs (`terraform destroy`, `aws … terminate`, `kubectl delete namespace`), and move-then-delete sequences.
- **Data-loss prevention** — a recycle bin for deleted files, backups before refactors, detection of NUL-corrupted writes, and guards for the `mv`/glob/`rm` and worktree failure modes.
- **Cost and quota** — token-spike early warnings, per-session budget limits, subagent fan-out limits, and warnings when usage is silently routed to API billing.
- **Silent-failure surfacing** — detectors for fabricated tool results, unverified "done" claims, forged system-reminder markup from sub-agents, and config poisoned from outside the tool boundary (read-only audits that warn, never edit).
- **Session and config protection** — backups of `settings.json`, drift detection, and recovery helpers.
- **Code-quality checks** (opt-in) — syntax checks, test-before-commit, and language-specific linters that run after edits.

Run `npx github:yurukusa/cc-safe-setup --list` to see every available hook with its description.

## How it works

Claude Code calls a hook before (or after) a tool runs and passes it JSON on stdin describing the tool call. The hook reads the command, decides, and communicates through its exit code:

```sh
#!/bin/sh
CMD=$(cat | jq -r '.tool_input.command // empty')
case "$CMD" in
  *"migrate:fresh"*|*"db:wipe"*)
    echo "Blocked: destructive database reset. Use an incremental migration." >&2
    exit 2 ;;   # exit 2 = block the tool call
esac
exit 0          # exit 0 = allow
```

Because the check happens at the tool boundary, it fires regardless of how the command was constructed, and it works in auto-accept mode where a human is not reviewing each step.

## Writing your own hook

A hook is any executable that reads the tool-call JSON on stdin and returns `0` (allow) or `2` (block, with a message on stderr). Drop it in your hooks directory and reference it from `settings.json` under the matching trigger (`PreToolUse`, `PostToolUse`, `SessionStart`, `Stop`, `SubagentStop`, `PermissionRequest`) with a `matcher` for the tool it should watch. See `examples/` for working scripts to copy.

## Safety audit and CI

`npx github:yurukusa/cc-safe-setup --audit` reports which classes of danger are and are not guarded.

Most of what it checks lives inside `settings.json`. One check does not: it reads the safety nets your `CLAUDE.md` **names** against the hooks your settings files actually **register**, and reports the two mismatches that no single-file check can see — a rule naming a script that exists nowhere, and a hook sitting in your hooks directory that appears in no settings file at all. Both files are individually valid in that second case; the guard simply never runs.

You can run the same audit in CI to keep a project's safety posture from regressing:

```yaml
# .github/workflows/safety.yml
- run: npx github:yurukusa/cc-safe-setup --audit --ci
```

`--audit` is what a script can decide on its own. For the contradictions that need your
session logs and CI read alongside your config, there are
[written audits](#written-audits-29-and-219) below — asynchronous, and nothing is ever
run in your environment.

### Proving a hook fires

`--audit` reads configuration. It cannot tell you whether a registered hook actually
refuses anything, and that is where most of the damage in `examples/` came from: a
guard that is present, registered, and silent.

`audit/` holds four small scripts for the other half.

```bash
# does this guard refuse the operation it was written to refuse?
audit/fire.sh ~/.claude/hooks/YOUR-HOOK.sh Bash "command=<the dangerous command>"
#   exit 2 = refused, exit 0 = Claude Code runs it

# same hook, on a machine with no jq, no python3 and no node
audit/fire.sh --bare ~/.claude/hooks/YOUR-HOOK.sh Bash "command=<the dangerous command>"
```

The `--bare` run is the one worth doing today. **798 of the 914 example hooks here parse
their input with `jq` and have no fallback.** Without a JSON parser they print a warning
to stderr and exit `0` — and Claude Code stops for exit code `2`, not for warnings.

`audit/count-hooks.py` counts registrations across all three settings files;
`audit/find-dead-hooks.sh` lists registrations whose script is not on disk (those fail to
launch, which Claude Code treats as non-blocking, so nothing surfaces);
`audit/selftest.sh` proves that detector really detects, because a detector that has never
found anything is not yet evidence of anything. `audit/audit-checklist.md` is a 50-point
sheet covering hooks, git, secrets, cost, autonomous operation and multi-agent work.

## Your installed hooks do not update themselves

Installing a hook copies the file. **Nothing ever copies it back.** A hook installed in March
keeps running its March logic forever, including bugs fixed here months later.

```bash
npx github:yurukusa/cc-safe-setup --outdated
```

This reports which of your installed hooks no longer match what ships today, and exits `1`
if any do, so it can run in CI. It only reports — it never overwrites, because a file that
differs may be your own edit.

**If you ran this before 2026-08-12, run it again.** Until then it compared your hooks
directory against `examples/` only, and the core guards — the ones `--install` writes by
default — are not files under `examples/`; they live in `scripts.json`. So every core guard
was reported as *"not shipped by this project — not checked"*, whatever its state.

That mattered. On the machine where this was found, three core guards were two and a half
months behind, and feeding the same input to the installed and shipped copies showed **six
dangerous command shapes that the shipped version blocks and the installed one let
through** — among them `cd /tmp && git push --force origin main` and `cd /tmp && git add
.env`. Each of those commands *on its own* was blocked by both copies, which is what makes
it a real gap rather than a bad measurement.

Core guards are not in `examples/`, so `--install-example` cannot fetch one. To see what
ships today and compare it yourself:

```bash
npx github:yurukusa/cc-safe-setup --show-core branch-guard > /tmp/shipped.sh
diff ~/.claude/hooks/branch-guard.sh /tmp/shipped.sh
```

`--show-core` prints to stdout and writes nothing.

## Rolling this out to a team

If you are the person who has to justify Claude Code to the rest of your organization, these are written for that job. All free, all usable as-is — no sign-up, no inquiry.

| | What it answers |
|---|---|
| [Team adoption safety checklist](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/75a565d9582fd31860f7c1a2e4cc938e/raw/team-adoption-checklist-jp.html) | The 7 things to settle before you hand this to developers, plus a shared policy template and a CI gate you can paste (JP) |
| [Settings reference](https://yurukusa.github.io/cc-safe-setup/settings-reference.html) | What each `settings.json` key actually does, and the ones that silently do nothing when written in the wrong place |
| [Cost governance for teams](https://yurukusa.github.io/cc-safe-setup/team-cost-governance-jp.html) | The three gaps the official usage limits don't cover, and how to close them with free hooks — cited to the official docs (JP) · [EN](https://yurukusa.github.io/cc-safe-setup/team-cost-governance.html) |
| [Monthly compliance report sample](https://yurukusa.github.io/cc-safe-setup/org-guard-monthly-report-sample.html) | What a monthly "is it actually working" report looks like, for SOC2 or a customer audit answer (fictional company, marked as such) |
| [Safety audit](https://yurukusa.github.io/cc-safe-setup/safety-audit.html) | Which classes of danger your current setup does and does not guard |

One paid thing exists, and it needs no inquiry either: the [Team Safety Rollout Pack](https://yurukusa.booth.pm/items/8230188) (¥3,000, one-off) bundles the shared policy template, the CI gate with defaults already chosen, and a written walkthrough of real reported incidents.

The hooks themselves stay free (MIT), always, and bug reports and questions are always welcome in issues and discussions.

## Written audits ($29 and $219)

These are not a team-only thing — they were under the section above until 2026-08-12, which was the wrong place. If you have a `CLAUDE.md`, a `settings.json` and a few hooks, you are the case they were written for.

Corporate audits (¥150,000+), training, rollout consulting and monthly retainers **are not offered** — see the [note on the services page](https://yurukusa.github.io/cc-safe-setup/services-jp.html). What that rules out is the *engagement* shape, the kind where someone has to keep showing up. Written audits are a different shape, and three of them are offered: asynchronous, no call, no meeting, and nothing is ever run in your environment.

Two of them read one kind of file each, $29 (¥3,980), returned as a Markdown report in your issue thread. The [CLAUDE.md Audit](SERVICES.md#1-claudemd-audit--29-3980) reads your instruction files. The [Token Burn Audit](SERVICES.md#2-token-burn-audit--29-3980) reads your session logs and `/cost` output, which is where the money actually goes.

The third reads them *against each other*. The [Full-Surface Audit](SERVICES.md#3-full-surface-audit--219-29800), $219 (¥29,800), crosses `CLAUDE.md`, `settings.json`, your hooks, your session logs and your CI config, and reports only the contradictions that fall between the layers — the class of failure that passes every check you can run on any one of those files alone. Ordered through Ko-fi, with a private route for the files and nothing in a public issue; report within 72 hours.

An audit is a thing you cannot see before buying, so all three publish their deliverable in full: [CLAUDE.md sample](docs/claude-md-audit-sample.md), [Token Burn sample](docs/token-burn-audit-sample.md), [Full-Surface sample](docs/full-surface-audit-sample-jp.md) (Japanese). Each is that audit run against my own setup — including the parts where it found my own numbers and my own hooks to be wrong. The Full-Surface one is where it found that the guards running on my own machine were a different program from the ones I ship under the same names.

Before any of them: [cc-token-diet](https://github.com/yurukusa/cc-token-diet) is free, runs locally, and uploads nothing. If it answers your question, you do not need me.

## Windows

The hooks run under WSL2 and Git Bash. A few guards are Windows-specific (path handling, CJK-write corruption, the `ext4.vhdx` growth case). See `docs/windows.md`.

## Troubleshooting

If a hook does not fire, check that it is executable, that its path in `settings.json` is correct, and that the `matcher` names the right tool. `npx github:yurukusa/cc-safe-setup --doctor` checks these and reports what is misconfigured.

## Contributing

Contributions are welcome. Each hook should be a single shell script with a test, and should not pull anything from npm. See [CONTRIBUTING.md](CONTRIBUTING.md) for the layout, the test harness, and how to handle the JSON reader.

## Where these hooks came from

Every hook here exists because something broke first. The incident records behind
them — what failed, what the logs actually looked like, and what finally stopped it —
are written up at length in these:

**In Japanese** — these two are the ones the hooks here were actually written against, and they are the deepest:

- [事故防止の全記録](https://zenn.dev/yurukusa/books/6076c23b1cb18b) — 97 chapters
  of incidents, each traced to the setting or hook that stops it. The introduction, the
  symptom→chapter lookup table you'd reach for mid-incident, Chapters 1-3 and Chapter 100
  are free to read
- [トークン費用の実測](https://zenn.dev/yurukusa/books/token-savings-guide) (¥2,500) — where
  the tokens actually go, measured across 800+ hours rather than reasoned about. 35 chapters;
  the introduction, the symptom→chapter cost table, and Chapter 1 are free to read

**In English:**

- [Claude Code Safety Mastery](https://leanpub.com/claude-code-safety-mastery) (from $19, 56 pages) —
  the defensive hooks in this repository, grouped from the five to install first through Git
  protection and credential guards, and eight dated incidents where the guard itself failed silently
- [Claude Code Migration Playbook](https://leanpub.com/claude-code-migration-playbook) (from $19, 105 pages) —
  stay, switch, or build your own stack: five measurable triggers, a 30-day cost projection for
  each path, a decision tree that returns one recommendation, and a 48-hour rollback if it was wrong
- [Cut Your Claude Code Token Usage in Half](https://leanpub.com/claude-code-token-savings) (from $19, 89 pages) —
  where the tokens actually go, measured across 800+ hours rather than reasoned about:
  overnight cost spikes, sub-agents, thinking tokens, and context-window bloat
- [Claude Code AGENTS.md Interop Handbook](https://leanpub.com/claude-code-agents-md-interop) (from $9.99, 21 pages) —
  which file each of nine tools reads, six ways to keep them in sync, and how to check what
  your own setup actually loads rather than trusting a closed issue

All four are also sold together as
[The Claude Code Operator's Library](https://leanpub.com/b/cc-operators-library) (from $29).
**All four have a free sample you can read before deciding.**

Two of them are on Gumroad as well, if you prefer that store:
[Migration Playbook](https://yurukusa.gumroad.com/l/claude-code-migration-playbook) ($19) and
[the token book](https://yurukusa.gumroad.com/l/azrdt) (¥2,500).

All of them are optional, and every hook in this repository works without them. The reason they are
listed at all is that the Japanese editions do not surface in search or in Zenn's own topic listings
for this account (measured across 19 topics on 2026-08-09: zero appearances), so this README is one
of the few places they can be found from.

## License

MIT. See [LICENSE](LICENSE).
