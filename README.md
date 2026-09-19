# cc-safe-setup
**[日本語の README はこちら / Japanese README](docs/README.ja.md)**

One command to add safety hooks to [Claude Code](https://docs.claude.com/en/docs/claude-code). It installs a set of `PreToolUse`, `PostToolUse`, `SessionStart`, `Stop`, and `SubagentStop` hooks that stop destructive or irreversible operations *before* they run, and that surface silent failures.

```sh
npx github:yurukusa/cc-safe-setup
```

The command is interactive: it shows what each hook does and lets you choose which to install into your `~/.claude/settings.json` (or a project-local `.claude/settings.json`). Nothing is installed without your confirmation. MIT licensed.

> **Why not `npx cc-safe-setup`?** The npm release is stuck at 29.8.0 (2026-04-20) while this repository is at 30.0.4, and the gap is not cosmetic — 29.8.0 lets twenty-five command shapes through that the current code blocks. Details, including the comparison table, are in [The npm release is behind this repository](#the-npm-release-is-behind-this-repository) below.

Reading this in order, rather than by section: **[The Claude Code Safety Field Manual](https://leanpub.com/claude-code-safety-field-manual)** is this repository's documentation laid out as a path — the pre-flight checklist, what each guard actually refuses, how to make one fire on purpose so you can watch it work, and what to read in the log afterwards. The minimum price is zero.

## Something already broken? Start here

If you arrived from a search with something already broken, start here: the symptom on the
left, and the section that answers it on the right. Every section it points to is a
measurement on a real machine, not a guess. (A third of the visitors here do arrive from a
search engine — 51 of 152 unique visitors in the 14 days to 2026-09-19. The rest come from
links such as a gist or GitHub itself, or with no referrer recorded at all.)

| What you are seeing | Start here | Where |
|---|---|---|
| The hook refuses, and the tool call runs anyway | The refusal is in a shape or a word the event does not read — or the hook exited 1, crashed, or could not find `jq` | [A refusal the tool never reads](#a-refusal-the-tool-never-reads), then [Proving a hook fires](#proving-a-hook-fires) |
| The hook never seems to run at all | The session was started in a way that skips your hooks entirely | [Four ways your guards stop running at all](#four-ways-your-guards-stop-running-at-all) |
| The hook runs, but never on the commands you care about | Your pattern is anchored where your commands are not | [A hook can be installed, current, registered — and still never see you](#a-hook-can-be-installed-current-registered--and-still-never-see-you) |
| You are not sure the hook does anything | You have not fired it on purpose yet | [Proving a hook fires](#proving-a-hook-fires) |
| The hooks are installed but feel out of date | Installed copies are snapshots and do not update themselves | [Your installed hooks do not update themselves](#your-installed-hooks-do-not-update-themselves) |
| `npx cc-safe-setup` behaves unlike this page | npm is serving an older release | [The npm release is behind this repository](#the-npm-release-is-behind-this-repository) |

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
| `credential-guard` | `Write`/`Edit` to paths matching `.env`, `.env.*`, `credentials`, `secret`, `serviceaccount*.json`, `key.json`. API keys in Bash commands are **warned about, not blocked** — see the limits below |
| `token-guard` | reads over 100KB, a per-session read budget, subagent fan-out, a token budget that asks for `/compact` |

These are the guards only. The example-hook library, `--doctor`, `--audit`, and the rest of the CLI come from the npm package or from this repository directly.

### Measured limits of `credential-guard` (2026-09-04, against npm 29.8.0)

These are the exit codes, not the intent. Read them before trusting the row above.

- **Bash is never blocked by this plugin.** Both of its `Bash` hooks print a warning to stderr
  and return 0. `export ANTHROPIC_API_KEY=…`, `curl -H "Authorization: Bearer …"`, and
  `git commit -m "… <key> …"` all run. 0 of 6 shapes were blocked.
- **The same write through Bash is invisible.** `Write` to `~/app/.env` is blocked, but
  `cp k.env ~/app/.env`, `sed -i … ~/app/.env`, `printf … >> ~/app/.env` and `tee` are not.
  Install `examples/secret-file-write-guard.sh` for that (it covers 9 of 11 such shapes;
  `git add .env` belongs to `dotenv-commit-guard.sh`, and writes made inside an interpreter,
  e.g. `python3 -c "open('.env','w')…"`, cannot be seen from the command string at all).
- **"Service-account files" is narrower than it sounds, and case-sensitive.** The patterns are
  `serviceaccount.*\.json`, `key\.json`, `credentials\.json`. So `credentials.json` and
  `application_default_credentials.json` are blocked, but `gcp-service-account.json`,
  `service_account.json`, `serviceAccountKey.json` and `firebase-adminsdk.json` are **not**
  (2 of 7 shapes blocked). A hyphen, an underscore or a capital letter is enough to pass.
- `.env` itself holds up: `.env`, `.env.production`, `.env.local` and `Edit` on `.env` were all
  blocked (4 of 4).

Hooks stop a tool call before it runs. They are not a permission boundary — pair them with
`permissions.deny` and keep secrets outside the repository.

## The npm release is behind this repository

`npx cc-safe-setup` currently installs **29.8.0**, published 2026-04-20. This repository is at **30.0.4**. Publishing is blocked on renewing an npm credential, so npm keeps serving 29.8.0 until that is done.

The gap is not cosmetic. I fired twenty-two command shapes at both versions on 2026-09-03, feeding each guard the same JSON on stdin and running it with `bash` — the shell the installer names when it registers the hook. The guards shipped in 29.8.0 allow **nine** of those shapes that 30.0.4 refuses. Nothing went the other way: there is no shape 29.8.0 blocks and 30.0.4 lets through, and two harmless controls (`rm -rf node_modules`, `git push origin feature`) are allowed by both. Only `exit 2` counts as blocked here; `exit 1`, `exit 127` and a crash all let the command run.

The other thirteen behaved identically in both versions, and they are the plain forms: `rm -rf /`, `cd /tmp && sudo rm -rf /var/log`, `find . -name '*.log' | xargs rm -rf /`, `rm -rf ~/Documents/`, `git reset --hard HEAD~5`, `git clean -fd`, `chmod -R 777 /`, `git push --force origin main`, `git push origin +main`, `git push origin main`, `git add .env`, and the two controls. In other words, 29.8.0 stops the shape you would write in a tutorial and misses the shape a shell actually produces.

All nine:

| Command seen by the hook | Guard | 29.8.0 | 30.0.4 |
| --- | --- | --- | --- |
| `rm -rf \` with `~/Documents` on the next line — one deletion split over two lines | destructive-guard | allowed | blocked |
| `rm --recursive --force /` — long-form spelling of `-rf` | destructive-guard | allowed | blocked |
| a base64 blob decoded and piped into `sh`, carrying `rm -rf ~` | destructive-guard | allowed | blocked |
| `rm -rf "$HOME"` — home directory reached through a quoted variable | destructive-guard | allowed | blocked |
| `git push -uf origin feature` — force bundled into a short-flag cluster | branch-guard | allowed | blocked |
| `cd repo && git push --force origin main` — force push after a separator | branch-guard | allowed | blocked |
| `git -C /repo push --force` — git's own option placed before the verb | branch-guard | allowed | blocked |
| `cd app && git add .env` — a secret staged after a separator | secret-guard | allowed | blocked |
| `git add \` with `.env` on the next line — the same, split over two lines | secret-guard | allowed | blocked |

### Re-measured 2026-09-14: twenty-five, not nine

Two fixes landed here on 2026-09-14 ([#1120](https://github.com/yurukusa/cc-safe-setup/pull/1120),
[#1121](https://github.com/yurukusa/cc-safe-setup/pull/1121), and the follow-up that
carried #1121 into `branch-guard` and `secret-guard`), so the sentence above — written in
the present tense about "the current code" — went stale the same morning it was true.

Fired again that evening, same method, same `bash`, same JSON on stdin. The original
twenty-two shapes still split nine and thirteen: 29.8.0 cannot move. What moved is the
list. Widening it to forty-one shapes puts the gap at **twenty-five**, and nothing still
goes the other way.

The sixteen new ones:

| Shape family | Example | Guard |
| --- | --- | --- |
| git reached through a path | `/usr/bin/git push --force origin main`, `./git push --force origin main`, `/usr/bin/git clean -fd` | branch-guard, destructive-guard |
| git behind a wrapper | `sudo git push --force origin main`, `time …`, `nohup …` | branch-guard |
| git behind an assignment | `env FOO=1 git push --force origin main`, `FOO=1 git push --force origin main` | branch-guard |
| a global option whose value is not a `.git` path | `git --git-dir=/tmp/r/repo.d push --force`, `git --work-tree=/tmp/w --git-dir=… push --force`, `git -c user.name=x push --force`, `git --namespace=ns push --force` | branch-guard |
| the plumbing spelling of a push | `git send-pack --force origin main` | branch-guard |
| `-C` in front of the other verbs | `git -C /repo add .env`, `git -C /repo reset --hard HEAD~5`, `git -C /repo clean -fd` | secret-guard, destructive-guard |

The script that produces this comparison is checked in as
`tests/git-invocation-prefixes-all-guards.test.sh` for the current code; the
version-against-version run is in the book's evidence folder.

If you are reading this to decide whether the gap matters to you: the number is not the
point. The point is that it grows every time this repository improves and never shrinks,
because the published package is frozen.

29.8.0 on npm ships **698** example hooks; this repository has **916**. The 218 that are missing from the published package include `agents-md-sync-checker`. (Counted 2026-08-26 from the published tarball and this tree; the tree was recounted on 2026-09-20 and had gained two since.)

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

The example hooks are stricter about this than the core ones: **757 of the 916 mention `jq`
and contain no `python3` or `node` anywhere in the file** — 810 mention `jq` at all, and 53 of
those also mention a possible fallback. (Counted 2026-09-20 with `grep -l` over `examples/*.sh`;
an earlier edition claimed 798 of 914, which none of three plausible counting rules reproduced,
so the rule is spelled out here instead of the number being carried forward.) Without `jq` they
read an empty command and quietly do nothing — no error, no log line, and they still appear in
your `settings.json`. If you take examples from `examples/`, install `jq` first.

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

`--ci` exits `1` when the audit finds a `CRITICAL` or `HIGH` risk, and `0` otherwise. The line
is drawn there and not at "any risk" because a machine set up the way this tool recommends
still carries a `MEDIUM` finding, and a gate that reddens a correct setup gets deleted by the
first person who sees the build. Set `CC_AUDIT_THRESHOLD` to also fail below a score.

**If you added this step before 2026-09-03, it never failed.** `--ci` was in this README and
in nobody's code: the exit compared the score against a default threshold of `0`, and a score
cannot go below `0`, so the step passed whatever the audit found. That is worse than having no
step, because the belief that a regression would be caught is what stops you looking. It is
implemented now, and `tests/audit-ci-gate.test.sh` fails if it ever stops failing.

`--audit` is what a script can decide on its own. For the contradictions that need your
session logs and CI read alongside your config, there are
[written audits](#written-audits) below — asynchronous, and nothing is ever
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
#   (a hook that refuses through JSON exits 0 and still blocks — this line will call it
#    "allowed". See "A refusal the tool never reads" below before rewriting such a hook.)

# same hook, on a machine with no jq, no python3 and no node
audit/fire.sh --bare ~/.claude/hooks/YOUR-HOOK.sh Bash "command=<the dangerous command>"
```

The `--bare` run is the one worth doing today. **757 of the 916 example hooks here mention
`jq` and contain no `python3` or `node` fallback anywhere in the file** (counted 2026-09-20).
Without a JSON parser they print a warning to stderr and exit `0` — and Claude Code stops for
exit code `2`, not for warnings.

`audit/count-hooks.py` counts registrations across all three settings files;
`audit/find-dead-hooks.sh` lists registrations whose script is not on disk (those fail to
launch, which Claude Code treats as non-blocking, so nothing surfaces);
`audit/selftest.sh` proves that detector really detects, because a detector that has never
found anything is not yet evidence of anything. `audit/audit-checklist.md` is a 50-point
sheet covering hooks, git, secrets, cost, autonomous operation and multi-agent work.

## A refusal the tool never reads

A `PreToolUse` hook can run, compute the right decision, print it, and be ignored. Nothing
errors. The hook exits 0, there is no verdict, and the tool call proceeds — so the logs of a
guard that is silently open look exactly like the logs of one that is working.

Measured 2026-09-19 on Claude Code 2.1.278, one hook at a time on `PreToolUse` with matcher
`Write`, in a throwaway `HOME`. Each hook appended a line to its own log before printing, so
"never invoked" and "invoked and ignored" stay separable. The verdict is whether the file
exists on disk afterwards, not what the transcript says:

| What the hook printed | Hook ran | File created |
|---|---|---|
| nothing, `exit 0` *(control)* | yes | yes |
| `{"permissionDecision":"deny", …}` — **at the top level** | yes | **yes — ignored** |
| `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny", …}}` | yes | no |
| `{"decision":"block","reason":…}`, `exit 0` — the older shape | yes | no |
| `{"decision":"deny"}` | yes | **yes — ignored** |
| stderr + `exit 2` | yes | no |

The uppercase `{"decision":"DENY"}` was measured the same day, but on matcher `Bash` and with
the verdict being whether the command actually ran; it was ignored there too. It is left out
of the table above because it was not fired under these conditions.

Two things fall out of that table.

**`permissionDecision` belongs inside `hookSpecificOutput`.** At the top level it is not read
here. The minimal repro in [anthropics/claude-code#91574](https://github.com/anthropics/claude-code/issues/91574)
(open since 2026-09-02, reported against 2.1.245 on macOS) uses the top-level shape, so this
is one thing worth ruling out before anything else. It is not a diagnosis of that report: the
same report also says `PreToolUse` never registers in the debug trace at all, and nothing
about an unreadable body explains a missing registration line.

**The older `{"decision": …}` field answers to `block`.** It still refuses on 2.1.278 — if you
have a working hook using it, leave it alone. `deny` and `DENY` are dropped in silence. Other
values were not fired, so treat this as two data points rather than a vocabulary. One of the guards in this repository's
example library did exactly that, on three branches that block irreversible deletions, from
the day it was written until it was measured. Its tests were green the whole time, because
they asserted that the string `"decision":"DENY"` appeared on stdout and never looked at the
exit code. It refuses with `exit 2` as of 2026-09-19. **If you copied that example before
then, take it again** — or run `--outdated`, which compares your installed copies against
what ships today.

### Checking your own, in two runs

`exit 2` carries no JSON, so it cannot be misparsed. Replace the line that prints your JSON
with these two — do not keep both, because printing a body *and* exiting 2 was not measured:

```bash
echo "denied" >&2
exit 2
```

If the call is blocked now, your hook was always being consulted and the JSON shape was the
problem. If it still goes through, the shape is a red herring: either the hook is not
loaded at all, or it is loaded and your pattern never matches what you actually run. Go to
[Four ways your guards stop running at all](#four-ways-your-guards-stop-running-at-all) and
[A hook can be installed, current, registered — and still never see you](#a-hook-can-be-installed-current-registered--and-still-never-see-you).

Run it twice: once with a hook that only does `exit 0`, once with yours. The first run must
let the operation through. Without that control, "nothing happened" can mean the guard
worked, or that the command was broken, or that the harness never fired.

One practical difference, once you have a choice: both of the JSON shapes that do refuse —
the nested `permissionDecision` and `{"decision":"block"}` — reach the model as
`PreToolUse:Write hook error: <your reason>` (measured on `Write`), with nothing identifying
which hook produced it. `exit 2` arrives with the hook's absolute path in front of the
message. With more than a couple of hooks on the same tool, that is the difference between
opening one file and opening all of them.

## A hook can be installed, current, registered — and still never see you

```bash
npx github:yurukusa/cc-safe-setup --blindspots
```

Every other check here reads one layer. `--status` reads the scripts on disk, `--lint` the
settings file, `--stats` the block log, `--outdated` the shipped bodies. A guard can pass all
four and still never fire, because the shape of the commands you actually run never reaches
it. That gap does not live inside any one layer, so no single-layer check can report it.

`--blindspots` reads your own session transcripts next to your own guards and reports what
each start-anchored pattern really matches. On the machine it was written on: 38,066 Bash
calls, **89.1% of them compound** and **32.0% beginning with `cd`** — and `branch-guard.sh`
examining 47 of 377 `git push` calls, because the other 330 came after a `cd … &&`.

It reads only. Nothing is sent anywhere and nothing is written back. Patterns that are allow
tests rather than gates are excluded, and a verb is counted only where it starts a command
segment, so a `git add` inside a quoted string is not mistaken for one that ran.

## Four ways your guards stop running at all

`--blindspots` finds guards that are loaded but never matched. There is a harder case it cannot
see: the guard is **never loaded**, or the tool it watches **no longer exists**. Four documented
ways to start Claude Code do that, and none of them reports it.

Measured 2026-09-19 on Claude Code **2.1.278**, Linux under WSL2, with a disposable `HOME` and a
scratch working directory. Arrival was measured on `UserPromptSubmit` — deliberately not
`PreToolUse` on `Bash`, because `--restricted` removes Bash, and then "the hook was ignored" and
"nothing pulled the trigger" look identical.

| How you start it | Your hooks | Bash |
| --- | --- | --- |
| *(control)* no flags | user, project and local all fire | present |
| `--dangerously-skip-permissions` | still fire — the guard refused, exit 2 | present |
| `claude --restricted` | **none load**; `--settings` is the only way back in I measured | **removed** |
| `claude --safe-mode` | **none load**, and `--settings` does **not** bring them back | **present** |
| `CLAUDE_CODE_RESTRICTED=1` | same as `--restricted` | removed |
| `CLAUDE_CODE_SAFE_MODE=1` | same as `--safe-mode` | **present** |

The control row matters: without it, "the guard stayed quiet" and "the guard is broken" are the
same observation. It fired and refused, so the guard works — it simply was not asked in the rows
where it is silent.

`--dangerously-skip-permissions` is in the table because people expect it to be the worst row for
their hooks. It is not: what that flag removes is the human prompt, not your guards. This table is
only about whether your hooks load, so do not read the second column as "this flag is safe."

### `claude --safe-mode` is not our `--safe-mode`

These are two different things with the same name, and one of them is ours:

- **`npx github:yurukusa/cc-safe-setup --safe-mode`** — *this tool*, and it is blunter than its
  name suggests: it moves **every** `.sh` in `~/.claude/hooks` aside and empties the `hooks` block
  of your `settings.json` — not just ours, yours and anyone else's too. It backs the file up
  first, it tells you what it did, and **it stays off until you run `--safe-mode off`**, which
  restores the hooks and copies the backup back over `settings.json` (so edits you make to that
  file while safe mode is on are lost). Being honest about that: ours is the one you set once and
  can forget, which is exactly the shape this section warns about.
- **`claude --safe-mode`** — *Claude Code*. Per invocation, for troubleshooting a broken
  configuration. Its own help says auth, model selection, **built-in tools and permissions work
  normally** — so your guards are gone and everything they guard against is still there.

We tell you to reach for our `--safe-mode` when a hook locks you out. Do not let that make
`claude --safe-mode` sound like the cautious choice. Of the ways to start Claude Code listed
above, the one whose name sounds safest is the only one that removes your hooks while leaving
the dangerous tools in place.

### The environment variables are the quiet ones

A flag is retyped every time you start. A line in your shell profile is read once and never seen
again. Under `--restricted` there is at least a tell — asked to run a shell command, the model
said in substance that the shell tool was missing and that the absence looked deliberate. Under
`--safe-mode` there is nothing to notice in the reply: every tool is present, the command runs,
the answer reads normally, and only the guard is quiet.

That was measured non-interactively (`claude -p`). Interactively you would likely notice, because
`--safe-mode` also drops `CLAUDE.md`, skills, plugins and MCP servers. The dangerous case is the
automated one — a script, a cron job, an unattended loop — where nobody reads the session.

**Check this first, it takes one command:**

```bash
grep -rn "CLAUDE_CODE_RESTRICTED\|CLAUDE_CODE_SAFE_MODE" \
  ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc ~/.zshenv 2>/dev/null
```

That covers the usual shell files. It will not find a variable set anywhere else your shell,
editor, terminal profile, container image or service manager can set one — check those too if the
grep comes back empty and something still looks wrong.

### Getting the hooks back is not the same as being guarded

Under `--restricted` you can pass them in with `--settings`, and they load. They still only cover
tools that survive. **Of the 24 `PreToolUse` registrations this repository installs by default —
six in `hooks/hooks.json` plus eighteen across the four plugins — 16 are matched on `Bash`**, and
`--restricted` is exactly the mode with no Bash. (The 916 files under `examples/` are not
registered; these 24 are what actually runs after an install.) The file tools remain, confined to
the working directories; both `Write` and `Edit` were measured modifying a file with no guard
consulted.

The five that already watch the file tools are the ones still standing in that mode: the
`Write|Edit` guard in `hooks/hooks.json`, three in `credential-guard` (`Write`, `Edit`, `Write`),
and one `Write` guard in `safety-essentials`. If you run `--restricted`, those five are your
coverage — check they cover what you care about, because the other sixteen cannot fire.

To be fair to the flag: `--restricted` did not create that gap. In the control run, with Bash
available, the model went straight to `Write` anyway — a Bash-only guard never covered that path.
What `--restricted` changes is that `Write` stops being one option among several and becomes the
only one. If you run `--restricted`, your guards need to be on `Write` and `Edit`.

**Not measured:** managed (policy) settings. The help says they survive both flags. There is no
`/etc/claude-code/` on the machine this was measured on, so that one is documentation, not
measurement.

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

The hooks themselves stay free (MIT), always, and bug reports and questions are always welcome in issues and discussions.

## Written audits

Three asynchronous written audits exist ($29 and $219): no call, no meeting, and nothing is ever
run in your environment. Each publishes its full deliverable before you buy, run against my own
setup. Scope, prices and the samples are in [SERVICES.md](SERVICES.md). Corporate audits,
training, rollout consulting and monthly retainers are **not** offered.

## Windows

The hooks run under WSL2 and Git Bash. A few guards are Windows-specific (path handling, CJK-write corruption, the `ext4.vhdx` growth case). See `docs/windows.md`.

## Troubleshooting

If a hook does not fire, check that it is executable, that its path in `settings.json` is correct, and that the `matcher` names the right tool. `npx github:yurukusa/cc-safe-setup --doctor` checks these and reports what is misconfigured.

## Contributing

Contributions are welcome. Each hook should be a single shell script with a test, and should not pull anything from npm. See [CONTRIBUTING.md](CONTRIBUTING.md) for the layout, the test harness, and how to handle the JSON reader.

## Where these hooks came from

Every hook here exists because something broke first — a destroyed working tree, a credential
read that should not have happened, an overnight cost spike. The incident behind each one, what
the logs actually looked like, and what finally stopped it, are written up at length. Those
write-ups are books, and they are listed in [docs/books.md](docs/books.md).

## License

MIT. See [LICENSE](LICENSE).
