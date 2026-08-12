# Changelog

## [Unreleased]
- **Fix: `--outdated` could not see the core guards it installs by default.** `--install`
  writes the core guards from `scripts.json`. `--outdated` compared your hooks directory
  against `examples/` only, and the core guards are not files under `examples/` — they are
  strings inside `scripts.json`. Every one of them fell into the *"not shipped by this
  project — not checked"* bucket. **If you ran `--outdated` before this change and it did
  not name your core guards, it was not answering that question about them.**

  Measured on one real machine on 2026-08-12, before the fix:

  | hook | installed | shipped |
  |---|---|---|
  | `destructive-guard.sh` | 8,319 B (2026-05-27) | 33,895 B |
  | `branch-guard.sh` | 2,616 B (2026-05-27) | 4,447 B |
  | `secret-guard.sh` | 2,964 B (2026-05-27) | 4,795 B |

  Feeding the same input to both copies, **six dangerous shapes were blocked by the shipped
  body and passed by the installed one**: a long-spelled `rm --recursive --force`, a
  base64-obfuscated command piped to `sh`, deletion via `xargs`, `cd /tmp && git push
  --force origin main`, `npm test && git push origin main` (protected branch), and
  `cd /tmp && git add .env`. The controls — each of those commands on its own — were
  blocked by both, which is what makes it a gap in coverage rather than a mistake in how
  the probe was fed. `--outdated` now checks the core guards too and tags them
  `[core guard]`.

- **New: `--show-core <name>`** prints the shipped body of a core guard to stdout and
  nothing else, so it can be piped into `diff`. It exists because `--outdated` can now name
  a stale core guard, but `--install-example` cannot fetch one — core guards are not files
  under `examples/` — so naming the problem without a way to read the shipped body would
  report something the reader cannot act on. It never writes to the hooks directory.

- **Fix: the syntax errors `syntax-check` found were never reaching the model.** The hook
  wrote them to stdout and exited `0`. Output on stdout with exit `0` reaches the
  transcript, not the model's context — so a hook whose entire purpose is "tell me now"
  was telling nobody. It now exits `2` on a syntax error. **Exit `2` in `PostToolUse` does
  not block the edit** (the tool has already run); it puts stderr in front of the model.
  Verified on 2026-08-12 by writing a file with a deliberate shell syntax error: the hook
  fired with exit 2 and the file was still on disk (244 bytes). Also passes `--no-install`
  to `npx`, which could otherwise stop at an interactive prompt when `tsc` is absent.

  Two of the existing tests for this hook were vacuous and this change is what exposed
  them: `echo '#!/bin/bash\nif then'` writes **one** line beginning with `#`, so `bash -n`
  sees a comment and reports nothing. The "invalid shell" case was checking a valid file.
  Both cases now use `printf`.

- **Fix (data loss): a `settings.json` that exists but does not parse was treated as `{}`
  and then written over** — the installer read the file with a bare `JSON.parse` in
  **34 places**, swallowed the failure outright in **9**, and in **6 of those 9** wrote the
  resulting object straight back with `writeFileSync(SETTINGS_PATH, …)`. Every hook,
  permission and env var the user had was replaced by a fresh object containing only the
  hook just added — **and the command exited 0, printing "Registered in settings.json".**
  Measured against `origin/main` in an isolated `HOME`, with a broken settings file holding
  one existing PreToolUse hook, `permissions.allow` and `env`:

  | | exit | file intact | existing hook | env var |
  |---|---|---|---|---|
  | `origin/main` | **0 (reported success)** | overwritten | **gone** | **gone** |
  | this change | 1 | intact | kept | kept |

  New `readSettingsForWrite()` refuses to write when the file exists but does not parse,
  and names the cause plus `python3 -m json.tool` to confirm it. The two remaining
  swallow sites (`migrateFrom`, `simulate`) never write settings back and are left alone —
  the damage there is different.
  **The count was wrong once, in the direction of "less broken".** The first pass looked
  only 60 lines past each swallow and classified `shield()` as read-only; its write is
  117 lines away, at `writeFileSync(SETTINGS_PATH, configNext)`. Counting by function
  scope instead of by distance turned 5 sites into 6.
- **Fix: `--audit` hid the cause** — the same swallowed parse made a corrupt settings file
  look empty, so the audit reported CRITICAL *"No PreToolUse hooks"* and pointed the user at
  a reinstall. The user has hooks; Claude Code is ignoring the whole file. Before the fix a
  broken file and a valid-but-empty one produced **identical** reports.
- **Fix: `--protect` failed every single time** — `protect()` called `rules.some(...)` three
  times and `rules` never existed in that function (pasted from `guard()`, which parses a
  user-supplied rule list). It threw `ReferenceError` immediately after writing the hook
  file, leaving the hook on disk and never registered. `--protect` installs exactly one
  rule, so only the `Edit|Write` matcher is needed; the block/approve branches are removed.
  `origin/main` exits 1 with a stack trace; this change exits 0 and completes registration.
  The usual trigger for all three is a snippet copied from docs whose first line is
  `// path/to/file` — not legal JSON. **This repo shipped four such examples** (fixed in #951).
  **`--protect` had no test at all**, which is why it could stay broken. New
  `tests/settings-unreadable-refuses-to-write.test.sh`: 6 cases — refuse-to-write for
  `--guard` and `--protect` on a broken file, the same two on a valid file as controls
  (without them, "refuses to write" and "cannot write at all" look identical), and
  `--protect` registering under the `Edit|Write` matcher without throwing.
  **5 of the 6 fail against `origin/main`.**
- **Fix: the marketplace plugins carried the same word-order assumptions, in a second
  implementation** — the four bundles under `plugins/` keep their shell **inline in
  `plugin.json`**. They are not copies of the core hooks, so every fix landed in the core
  today did nothing for anyone who installed a plugin.
  Measured 2026-08-03 with all four installed together, over the 24 probe forms these
  bundles claim to cover: **10 of 24 walked through → 3 of 24** (`find`, `dd`, `chmod` — none
  of the four claims those). Controls: **0 false positives of 9** ordinary commands, before
  and after, including `git push --force-with-lease`.
  What walked through was the familiar shape — a rule describing how a command is usually
  typed rather than what it does: `rm -r -f`, `rm --recursive --force`, `rm target -rf`,
  `git reset HEAD~1 --hard`, `git clean -x -f -d`, `git clean --force -d`,
  `git branch --delete --force`.
  **One description promised something that was never built.** `git-protection` said it
  *"guards interactive rebase"* and **no hook in the bundle mentions rebase at all**
  (checked by plain substring, after a first regex-based check produced two false alarms).
  The claim is removed rather than newly implemented: an interactive rebase is ordinary
  work, and blocking it would trade a false promise for a false positive.
  **A regression was introduced and fixed in the same pass, and both directions are now
  asserted.** Widening the `git clean` pattern also caught `git clean -nd` and `-ndx`, which
  remove nothing. Dry runs are the half that keeps a guard installed.
  New `tests/plugins-word-order.test.sh`: 32 cases, all passing, **8 of them failing**
  against `origin/main`'s copies.
- **`destructive-guard`: block `rm -rf *`** — found by measuring all three channels this
  project ships through, against the same 27 destructive forms:

  | channel | walked through |
  |---|---|
  | the itch.io kit, as downloaded from the store | **15 / 27** |
  | npm `29.8.0` (2026-04-20) | **10 / 27** |
  | this tree | **7 / 27** |

  `rm -rf *` was on all three lists. Check 1 asks whether the target begins with `/`, `~`,
  `$HOME` and so on; a glob begins with none of them, so it never matched.
  `*` expands to everything in the current directory, which makes `rm -rf *` a rename of
  `rm -rf .` — and `rm -rf .` has been blocked for months. Blocking one and not the other
  does not hold together.
  **Narrow on purpose**: only a bare `*` or `./*` standing as the whole target.
  `rm -rf *.log`, `rm -rf build/*`, `rm -rf node_modules/*` and `rm -rf tmp*` stay allowed —
  stopping the ordinary cleanup is its own kind of broken, and a guard that cries wolf gets
  removed. Measured: 7 dangerous forms blocked (including behind `sudo` and after a
  separator), 14 named-target and non-`rm` forms untouched.
  New `tests/destructive-guard-bare-glob.test.sh`: 21 cases, all passing, **9 of them
  failing** against `origin/main`'s copy.
- **Fix: four `settings.json` examples in the docs were not valid JSON** — each began with a
  `// path/to/file` comment inside the code block. A reader copies the block, saves it, and
  ends up with a settings file that will not parse. **A settings file that will not parse
  takes every hook down with it**, which is the silent failure this whole project exists to
  prevent.
  This is not hypothetical for anyone who then runs the installer: `index.mjs` reads
  `settings.json` with a plain `JSON.parse` in **10 places**, and one of them
  (`try { … } catch(e) {}`) swallows the error entirely, so the file is treated as empty.
  Our own tool cannot read a settings file written the way our own docs show it.
  The fix is not to delete the label but to move it out of the block, where it reads better
  anyway: `matchers.html`, `blog-subagent-permissions.html`, `settings-reference.html`,
  `team-rollout-guide.html`. `matchers.html` also carried an inline
  `"matcher": "Bash",        // Only Bash commands` — a comment in the middle of the JSON,
  which survives even if the reader drops the first line. That one is gone too.
  `docs/sub-agent-failure-modes-hook-map.md` uses a `jsonc` fence deliberately and keeps it,
  with a sentence added saying `settings.json` is strict JSON and the `//` line has to go.
  **Left alone on purpose**: `common-mistakes.html` (`// DON'T:` / `// DO:` fragments that
  are not a file) and two blocks in `settings-reference.html` that are shell, not JSON.
  Safety check: the HTML tag count changes by exactly +4 per file — the one `<p><strong>`
  label added — and by nothing else.
  Found by running every code block in the repo's docs and in the sister handbook through a
  parser. That sweep also turned up 5 broken samples in the paid books, fixed separately.
- **New check: every `# TRIGGER:` header has to name an event Claude Code accepts** — an
  unknown key under `hooks` in settings.json is not an error. Claude Code does not warn
  about it and the hook simply never runs, so one mistyped event name turns a shipped guard
  into a file that sits in the config looking installed and protects nothing. That is the
  exact silent-failure shape this repo exists to catch, and nothing was checking it.
  Users register hooks by copying the `# TRIGGER:` line out of the example, so a wrong name
  in a header propagates straight into somebody's settings.
  Swept all 909 examples: **829 carry a TRIGGER header**, they use **12 of the 31 event
  names that exist**, and **two named an event that does not exist** — `hook-debug-wrapper`
  and `hook-stdout-sanitizer` both said `Any`, written as prose meaning "any event". A
  reader copying that gets a key Claude Code ignores. Those two wrap another hook rather
  than being registered on their own, so their headers now say `none` and point at the
  wrapped hook's event, with the reason spelled out. A third header
  (`commitment-carry-forward-arrest`) had an unclosed parenthesis that swallowed the second
  event name; it now reads `Stop, UserPromptSubmit`.
  `scripts/check-hook-event-names.py` carries the roster as documented on 2026-08-03 and is
  wired into CI. Verified the way a check has to be verified: introducing `PreToolUsee` in
  one header makes it exit 1, and restoring the file makes it exit 0.
- **Fix: `destructive-guard` assumed the dangerous flag would be in a fixed slot** — three
  of its checks encoded a habit of typing rather than what the command does:

  | check | pattern | what it assumed |
  |---|---|---|
  | 2 | `git\s+reset\s+--hard` | `--hard` follows `reset` |
  | 3 | `git\s+clean\s+-[a-z]*[fd]` | the flags are one bundle, and come first |
  | 4 | `chmod\s+(-R\s+)?777\s+(/\|~\|\.)` | `-R` sits before `777`, the path right after |

  A shell does not care. `git reset HEAD~1 --hard` discards exactly the same work,
  `git clean -x -f -d` deletes *more* than `git clean -fd`, and `chmod 777 -R /etc` is
  `chmod -R 777 /etc`. All of them walked past the guard that every
  `npx github:yurukusa/cc-safe-setup` user gets first.
  Measured 2026-08-03 against the shipped copy, denominator restricted to the pairs this
  guard blocks in their canonical form: **5 of 19 reorderings were not blocked**. After the
  fix, **0 of 19**, and **0 of 28** everyday commands became newly blocked.
  Every scan is bounded by `[^;&|]`, so a later command's words are never borrowed to make
  a match (`git reset HEAD~1 ; echo --hard` stays allowed, and is tested).
  **Two false positives came out of the same measurement, and they were the ones this hook
  tells people to run.** `git clean -nd` and `git clean -ndx` are dry runs — they list what
  would be deleted and remove nothing — and both were blocked. The block message says
  *"Consider: git clean -n (dry run) first"*, so following the advice hit the wall. Dry runs
  now pass.
  This is the same shape as the approving-hook defect fixed the same day in #937 / #940 /
  #941 / #942 / #943 / #947 / #948, one level up: there the rule assumed the dangerous part
  came *after* the first command position, here it assumes a fixed slot. Both are patterns
  that describe how a command is usually typed instead of what it does.
  **Check 5 had the same shape one layer down, found while judging the July `find` work.**
  The prefix stripper dropped leading `VAR=value` once and *then* dropped wrappers in a
  loop, so `env LC_ALL=C find . -delete` survived: the assignment sits after the wrapper and
  the command word was read as `LC_ALL=C`. Assignments are now dropped inside the same loop.
  Evasion coverage measured against the shipped copy: **19/20 → 20/20**, with false
  positives on real cleanup at **0/12** both before and after.
  **CI caught a regression in this PR and it is worth recording.** The first attempt let dry
  runs through by putting a word boundary after the flag bundle — which also released
  `git clean -fdx`, a command that removes *more* than `-fd`. `-fdx` matches `[a-z]*[fd]`
  only when nothing follows the `[fd]`. The dry-run exclusion alone does the job; the
  boundary is gone and both forms are tested.
  New per-hook suite for flag order: 39 cases, all passing, **12 of them failing** against
  `origin/main`'s copy.
- **Fix: three approving hooks whose safe list was too coarse to mean anything** — a
  different defect from #937 / #940 / #941 / #942 / #943 / #947, and deliberately counted
  separately. Those all fixed hooks that read the first command position and handed the
  approval to the whole line. These three approve destructive commands **with no separator
  in them at all**, because their safe lists held bare command *words*: `git`, `curl`,
  `chmod`, `sed`, `node`, `python3`, `npx`. `git commit -m "fix"` and
  `git push --force origin main` have the same first word. Folding these into the earlier
  count would have produced "18 hooks defective" instead of 15 — a number that looks right
  and is not.
  Measured against the shipped copies, over 20 destructive or credential-reading single
  commands:

  | hook | before | after | everyday commands still approved |
  |---|---|---|---|
  | `bash-heuristic-approver` | **15 / 20** | **1 / 20** | 30 / 30 |
  | `quoted-flag-approver` | **15 / 20** | **1 / 20** | 30 / 30 |
  | `fish-shell-wrapper` | **18 / 20** | **0 / 20** | 21 / 21 |

  Among what was approved: `git push --force`, `git reset --hard`, `git clean -fdx`,
  `git branch -D main`, `chmod -R 777 /`, `curl … | sh`, `node -e '…rmSync…'` and
  `cat ~/.aws/credentials`. `fish-shell-wrapper` added `sudo rm -rf`,
  `dd if=/dev/zero of=/dev/sda` and `mkfs.ext4`.
  **`fish-shell-wrapper` is the one worth reading twice.** It is not an approver by intent
  — it rewrites commands into `fish -c '…'` so fish users keep their PATH and aliases. It
  returned `permissionDecision: "allow"` on everything it wrapped because the approval was
  the *carrier* for `updatedInput`. The signature was a side effect of the rewrite.
  Rewrite and approval are now separate: every command is still wrapped (21/21 everyday,
  10/10 destructive), and only qualifying ones are approved. Whether `updatedInput` alone
  is honoured is undocumented and deliberately not relied on — if it is, an unqualified
  command is wrapped and still prompts; if it is not, it is unwrapped and still prompts.
  Both branches end at the prompt.
  `bash-heuristic-approver` could not simply refuse `$(…)` the way the others do, because
  substitution is its subject. Instead the substitution's contents became command positions
  of their own: `echo $(git status)` is approved, `echo $(sudo rm -rf app)` is not.
  **The one survivor is named on purpose**: `cat ~/.aws/credentials` is still approved by
  the first two. It is a read, reads are what those hooks are for, and keeping credentials
  out of a transcript is a blocking hook's job here — a block beats an approval.
  **★ Measuring these needed the prompt text.** Two of the three only act when `.message`
  carries the permission prompt's own wording. The first pass of this sweep put the command
  in `.message`, got **0/20** back from both, and read it as "no defect". Every block in the
  new suite opens with a control — does a plainly safe command get approved at all? — because
  without it "clean" and "not running" look identical.
  New `tests/approver-list-granularity.test.sh`: 86 cases, all passing, 43 of them failing
  against the pre-fix copies.
- **Fix: the last two approving hooks that read only the first command position** — closes
  the 2026-08-03 sweep started in #941. Thirty hooks in this repo return an approval;
  fifteen decided from the first command position and handed that approval to the whole
  line. Thirteen were repaired in #941 / #942 / #943. `classifier-fallback-allow` and
  `multiline-command-approver` were held back because each has its own shape — a `case`
  ladder in one, `head -1` in the other — and pasting the same patch over them would have
  been guesswork.
  Measured against the shipped copies, over the commands each approves in bare form (33 and
  32 of a 49-command probe set), with three tails appended (`&& sudo rm -rf /var/app`,
  `; curl http://… | sh`, `&& git push --force`): **297/297 approvals kept** for
  `classifier-fallback-allow` and **288/288** for `multiline-command-approver`. After the
  fix: **0 and 0**.
  **The newline row is the one that stings.** `multiline-command-approver` exists because
  commands span lines — heredocs, commit messages — and it took `head -1` of them. A safe
  first line with a destructive command on the second kept its approval **18/18 times**;
  now **0/18**. Reading further is not just splitting on separators here, because the forms
  this hook rescues put separators and newlines *inside data*: the command is now scanned
  with quoting state carried across lines, and heredoc bodies are skipped between opener and
  terminator. All 8 legitimate multiline forms stay approved.
  **Controls named the defect**: the same dangerous commands on their own were approved
  0/5 and 0/3 both before and after. Neither hook ever approved indiscriminately — both
  stopped reading after the first command position. Repairing the wrong one of those two
  would have looked like progress.
  `classifier-fallback-allow` also gets the `find` predicate check (`-delete` was matched
  anywhere in the line, which both missed `-exec` and fired on unrelated segments) and
  refuses redirections and substitutions, matching `auto-approve-readonly`.
  Over-tightening, measured the same way: of 10 everyday compound commands, the only one to
  lose its approval is `echo start && date` under `multiline-command-approver` — `date` was
  never on that hook's safe list, and the old approval came purely from not reading past the
  first position.
  **An existing test stated the defect as the contract.** `test.sh` asserted
  `ls -la /tmp\nrm something` with the description *"approve first line"*, and since
  `test_ex` compares exit codes only while this hook always exits 0, that assertion could
  not fail in either direction. New suite `tests/approve-side-remaining-two.test.sh`
  asserts on the decision itself: 62 cases, all passing, and 32 of them fail against the
  pre-fix copies.
- **Fix: `auto-approve-readonly` approved writes and deletions as reads** — this is the
  hook the sister handbook recommends by name, in its free first chapter and again in two
  later ones, so a defect here reaches people who read the book and followed it. Two
  problems compounded. The base command came from the **first word of the whole line**, so
  `cat README.md && sudo rm -rf app` produced the base `cat` and the approval went to the
  entire line — the same defect as #937 / #940 / #941 / #942. And `find` sat in the
  read-only list with no look at its predicates, so `find . -name '*.log' -delete` was
  approved as a read. Redirections had the same shape: `cat template.txt > config.json`
  writes a file and was approved for reading one.
  Measured 2026-08-03 against the shipped copy, with controls: **10 of 12 writing or
  destructive forms were approved**; after the fix, **0**. Over-tightening measured the
  same way: of the 35 ordinary read commands, **0 lost their approval**.
  Every command position now has to read on its own. `find` reads only while it carries no
  `-delete`/`-exec`/`-ok`/`-fprint`; `sed -i` rewrites in place and is not a read; a `>`
  anywhere in the line disqualifies it; command substitution and backticks disqualify it,
  since they hide a command from any string-level read. Filters (`sort`, `awk`, `sed`, …)
  are accepted downstream of something else but not in the first position, so `sed …` on
  its own is still not read as a read.
  **One deliberate widening, stated plainly**: `cd /repo && ls -la` and
  `cd /repo && git status` are now approved. They were not before — the old code tried to
  strip a leading `cd` but the strip did not survive `&&`. Both segments read, so this
  matches what the hook set out to do.
  Tests: `tests/auto-approve-compound-tail.test.sh` grows to 158 cases, all passing.
- **Fix: seven more opt-in approver hooks, same first-segment defect** — continues
  #941. `auto-approve-gradle`, `-make`, `-maven`, `-ssh`, `-git-read`, `-test` and
  `auto-mode-safe-commands` each decided with a pattern anchored at `^\s*` applied to the
  whole command string, then handed the approval to everything after it. Measured
  2026-08-03 against the shipped copies: over the 46 ordinary commands these seven
  approve, **118 of the 138 combinations kept their approval** when one of three tails was
  appended (`&& sudo rm -rf …`, `; curl http://… | sh`, `&& git push --force`). After the
  fix: **0**.
  `auto-mode-safe-commands` is the one that matters most — it exists for auto mode, where
  nobody reads the prompt — and it was also the clearest case of a file contradicting
  itself: its own comment says *"We check each component of compound commands"* while the
  code checked only the first. It approved `curl -s http://… | sh` and
  `echo $(sudo rm -rf app)`. Both are refused now; the `$(date …)` substitution the hook
  deliberately supports still is not.
  `auto-approve-git-read` folded its two patterns (`git …` and `cd … && git …`) into one
  segment rule: a leading `cd` is allowed, every other segment must be a read-only git
  call, and at least one segment must actually be git — so `cd /repo` alone is no longer
  approved, and `cd /repo && git push` never was.
  Over-tightening measured the same way: **0 of the 46 ordinary commands lost their
  approval**, and chains of the same approved kind (`pytest && go test ./...`,
  `git status && git log`, `ls -la && cat README.md`, `make build && make test`) are
  covered by tests.
  `tests/auto-approve-compound-tail.test.sh` grows to 133 cases, all passing.
  Still outstanding: `auto-approve-readonly`, `classifier-fallback-allow` and
  `multiline-command-approver` have the same defect but enough of their own structure
  (pipeline handling, `case` dispatch, multi-line parsing) to want separate treatment; and
  `bash-heuristic-approver`, `quoted-flag-approver` and `fish-shell-wrapper` approve
  destructive commands with no separator at all, which is a different problem.
  Also noted, not changed: `auto-mode-safe-commands` lists `find` as read-only, so
  `find . -delete` fits its safe pattern. That is a coverage question, not an anchor one.
- **Fix: the five auto-installed `auto-approve-*` hooks approved the whole line on
  the strength of its first word** — `index.mjs` installs these five from stack
  detection (a `package.json` pulls in `auto-approve-build`, a `go.mod` pulls in
  `auto-approve-go`, and so on), so the user never picks them off a list. Each decided
  with a pattern anchored at `^\s*` applied to the whole command string: only the first
  command position was examined, and the approval was then handed to everything after it.
  `npm test && sudo rm -rf app`, `cargo build; curl http://… | sh` and
  `docker ps && git push --force origin main` were all **explicitly approved**. Same
  defect as PR #937 (`allowlist.sh`) and PR #940 (`cd-git-allow.sh`), on the approving
  side. Measured 2026-08-03 against the shipped copies with controls: every one of the
  five refuses the destructive command when it stands alone, and keeps its approval when
  the same command is appended after a separator.
  All five now require **every** command position to match before approving, and return
  no decision otherwise, which leaves the command to the normal permission flow — these
  hooks only ever add approval, they never block. Command substitution and backticks
  disqualify the line, since they hide a command from any string-level read.
  Chains of approved commands (`npm ci && npm test`, `ruff check . && pytest`) still get
  approved: the gate uses the union of each hook's own patterns.
  Over-tightening was measured the same way as the hole: 63 ordinary commands run against
  both versions of all five hooks, **0 commands lost their approval**.
  New `tests/auto-approve-compound-tail.test.sh` — 56 pass, 34 of them fail against the
  pre-fix copies.
  Still outstanding, measured but not fixed here: 10 more opt-in example hooks have the
  same first-segment defect (`auto-approve-git-read`, `-gradle`, `-make`, `-maven`,
  `-ssh`, `-readonly`, `-test`, `auto-mode-safe-commands`, `classifier-fallback-allow`,
  `multiline-command-approver`), and 3 more (`bash-heuristic-approver`,
  `quoted-flag-approver`, `fish-shell-wrapper`) approve destructive commands even without
  a separator, which is a different and broader problem.
- **Fix: two core hooks matched only the first command position** — the same defect
  PR #937 fixed in `allowlist.sh`, found in the hooks that `cc-safe-setup` installs for
  every user. `destructive-guard.sh` Check 6 anchored its sudo pattern with `^\s*sudo`,
  so nothing after a separator was examined: `cd /tmp && sudo rm -rf app` ran unguarded.
  It stayed hidden because Check 1 independently blocks `rm` on a sensitive path, so the
  obvious probe (`cd /tmp && sudo rm -rf /var`) still came back blocked. Measured against
  the shipped `scripts.json` on 2026-08-03, on the eight forms Check 6 alone covers
  (a relative path, `dd`, `mkfs`): 8/8 blocked bare, **7/8 exited 0 behind `cd X &&`, `;`,
  `&&` and `||`**. `cd-git-allow.sh` had the mirror image on the approving side: it pulled
  out the first `&& git <sub>` and, if that subcommand was read-only, returned
  `permissionDecision: "allow"` for the whole line — so
  `cd /repo && git log && sudo rm -rf app` was **explicitly approved**, tail unread. Both
  now split on `&&`, `||`, `;`, `|` and `&` and judge every segment. `cd-git-allow` returns
  no decision when any segment is not a read-only git call, which drops the command into
  the normal permission flow rather than blocking it; it also no longer depends on
  `grep -oP`, which is GNU-only and silently returned nothing on macOS.
  The same anchor was over-tightening in `destructive-guard.sh` Check 7: the skip that
  keeps `echo "Remove-Item -Recurse -Force"` from reading as a deletion only applied at the
  start of the line, so `cd repo && git commit -m "... Remove-Item -Recurse -Force ..."`
  was blocked for writing a commit message. Check 7 now asks whether the deleting command
  sits at a command position (optionally behind a `powershell`/`pwsh` wrapper) instead of
  whether the words appear anywhere, which drops the skip list entirely. `del /s /q` and
  `rd /s /q` keep their own branch. Over-tightening was measured the same way as the hole:
  55 ordinary commands run against both versions, **no command newly blocked**, and the two
  that stopped being blocked are exactly the false positives above.
  New tests: 27 cases added to `tests/destructive-guard-separators.test.sh` (41 pass;
  9 of them fail against the pre-fix copy) and `tests/cd-git-allow-compound-tail.test.sh`
  (13 pass; 3 fail against the pre-fix copy). `--verify` gains a compound-sudo case.
  Not addressed: sudo's own options (`sudo -u www rm -rf app`) still slip past Check 6,
  which is a coverage question rather than an anchor one.
- **`warn-cron-cost-trap.sh`: warn on short-interval recurring CronCreate (#74547)** —
  a recurring `CronCreate` does not run cheaply in the background: each fire is a full
  turn that re-reads the accumulated conversation, so per-fire cost grows with the
  session and the total climbs roughly quadratically with the number of fires. Issue
  #74547 reports ~USD 500 burned by an ~11-minute recurring schedule that polled an
  empty directory 88 times in 16 hours. This PostToolUse hook (matcher `CronCreate`)
  parses the minute field of `.tool_input.cron` — `*` → 1 min, `*/N` → N, comma-lists →
  smallest consecutive gap with 60-wraparound, `A-B` ranges → 1 min (fires every minute
  in the range), single value → hourly — and prints a one-time cost warning when the
  derived interval is below the threshold (default 15 min), **unless `recurring` is
  explicitly `false`**. An omitted `recurring` is *not* excluded: `CronCreate` defaults to
  recurring, so an omitted short-interval registration — the most dangerous form — is
  exactly the case that must still be caught. (An earlier draft of this hook read the
  field as `recurring // false`, which silently skipped that case; jq's `//` also collapses
  an explicit `false`, so the raw value is read instead.) Advisory by design (always exit 0, never blocks);
  fail-open on missing jq / no cron / unparseable minute field. `CC_CRON_COST_TRAP_DISABLE=1`
  to disable, `CC_CRON_COST_TRAP_THRESHOLD_MIN=N` to tune. Standalone test added at
  `tests/test-warn-cron-cost-trap.sh` (21 assertions). Pairs with `cron-create-receipt.sh`.
- **`reroute-after-block-guard.sh`: stop a reroute toward a just-blocked target (#70112)** —
  PreToolUse hooks are stateless, so the trajectory in #70112 (a gate fires; the agent
  substitutes an equivalent path toward the SAME target; the next hook evaluates a fresh,
  individually-defensible action and lets it run) slips through every guardrail. This new
  example reads the transcript: if the previous tool call was stopped by a PreToolUse hook
  block or a permission denial, and the current action shares a concrete path-like target,
  it stops and surfaces. A fired gate should raise the bar for proceeding, not trigger a
  search for an unblocked route. Fail-open by design (no transcript / previous succeeded /
  no shared target → allowed); `CC_REROUTE_ALLOW=1` for a conscious one-shot retry,
  `CC_REROUTE_DISABLE=1` to disable. Tests added to `test.sh`.
- **`uncommitted-discard-guard.sh`: also block `git stash clear` (#69850)** — the guard
  already blocked `git stash drop`, but not `git stash clear`, which wipes EVERY stash at
  once. The #69850 incident is the stash-then-discard loss path: work is moved into a stash
  (the working tree goes clean), then the stash is discarded — equivalent to
  `git reset --hard`. Auto-stash-before-danger hooks miss this because the tree is clean at
  drop/clear time, so blocking the discard itself is the reliable guard. `git stash`,
  `git stash pop`, and `git stash list` remain allowed. Tests added to `test.sh`.
- **`rm-safety-net.sh`: catch `find | xargs rm` without a null delimiter (#69793)** —
  `find` prints newline-separated paths, but `xargs` without `-0` splits on ANY
  whitespace, so a single path with spaces (`./Google Photos/a.jpg`) splits into two
  arguments (`./Google` and `Photos/a.jpg`). With `rm -rf`, the first token can match
  an unrelated real directory and wipe it — the reporter lost ~28,800 files this way.
  The existing `rm` checks can't catch it because the delete targets are produced by
  `find` at runtime, so there is no literal path in the command string. The hook now
  blocks `find ... | xargs ... rm` (and `rmdir`/`unlink`/`shred`/`trash`) unless the
  null-delimited pair `find -print0 | xargs -0` is present, and points to the safe
  forms (`find -delete`, `find -exec rm {} +`, `find -print0 | xargs -0 rm`). Eight
  tests added to `tests/test-rm-safety-net.sh` (49 pass, no regression).
- **Fix: PowerShell-tool blind spot in the Windows destructive guards (#69397)** —
  Claude Code's `PowerShell` tool is a separate tool from `Bash`, and a hook matched
  only on `"Bash"` never fires on a PowerShell-tool command. That blind spot let a
  destructive `az ad group delete` run with no permission prompt. The
  `windows-destructive-command-guard.sh` previously hard-exited unless
  `tool_name == "Bash"`; it now accepts `Bash` or `PowerShell` so it inspects
  PowerShell-tool commands too. `powershell-remove-item-guard.sh` and
  `cloud-cli-guard.sh` headers now declare `MATCHER: "Bash|PowerShell"` (their logic
  already reads `tool_input.command`, which both tools populate). README "Windows
  Support" documents the separate-tool caveat and the `"Bash|PowerShell"` matcher.

## [30.0.1] - 2026-05-28 → 2026-06-05
Post-launch safety-hook expansion. The example-hook catalog grew from 707 to
824+, driven by a sustained "issue → tested hook" workflow against the highest-
reaction GitHub Issues and newly observed incident clusters.
- **CLI**: aligned the post-install banner / sister-handbook claims with the
  actual preview state (no "coming soon" wording for shipped items).
- **New incident-cluster defenses** (advisory + blocking hooks, each with tests):
  - Extended-thinking session wedging (Cluster 13): `extended-thinking-loop-guard`,
    `extended-thinking-resume-warning`, `opus48-thinking-wedge-advisor`
  - Auth drift / silent invalidation (Cluster 19): `oauth-refresh-monitor`,
    `auth-status-checker`, `auth-macos-sleep-detector`, CLI pin advisory
  - Parallel-batch cancellation corruption (Cluster 20): `parallel-cascade-detector`,
    `parallel-batch-size-limiter`, `tool-result-correlation-checker`
  - Opus 4.8 fabrication / effort-budget regressions (Clusters 22/23):
    `pre-execution-claim-detector`, `thinking-budget-effort-mismatch-detector`,
    `output-token-spike-detector`, `opus48-routine-task-warning`
  - AUP false-positive / large-output (Cluster 9): `aup-retry-loop-guard`,
    `aup-large-tool-output-warner`, `aup-block-pattern-logger`, `model-swap-suggester`
  - Permission boundary integrity (Cluster 6): `compound-bash-permission-resolver`,
    `deny-rule-integrity-verifier`
  - Misc: `nested-spawn-inflight-guard`, `stop-hook-sigterm-wrapper`,
    `plugin-hooks-json-bloat-detector`, `cache-ttl-eviction-detector`,
    `non-english-quality-warner`, `pre-bash-sed-line-ending-windows` (#63715)
- **Data-loss prevention**: hardened the destructive-command and ORM guards to
  actually block `drizzle push --force`, `tofu/terraform apply -destroy`, and
  `prisma db push --accept-data-loss` (real incidents #27063 / #14411).
- **June 15 billing change**: `cliff-countdown-advisor` (SessionStart advisory on
  days-to-2026-06-15 and credit-pool minimization), plus prep-plan docs.
- **Credential / sub-agent safety**: `dotenv-read-guard` (blocks Read of `.env`,
  inherited by sub-agents that do not inherit CLAUDE.md), sub-agent blast-radius
  guards keyed on `agent_id`.
- **2026-06-05 security hardening** (verified against live incidents):
  - `rm-safety-net`: also blocks deletion of `.env` files in nested paths
    (`backend/.env`, `src/.env`) — the start-anchored pattern previously missed
    them (#65034). +10 tests.
  - `credential-exfil-guard`: now blocks macOS keychain extraction of secret
    tokens (`security find-generic-password -s ANTHROPIC_AUTH_TOKEN -w`, the
    technique a malicious plugin used in #65350) and secret env vars piped to a
    network client, while leaving `Authorization: Bearer $TOKEN` headers and
    non-secret keychain lookups untouched. +inline + standalone tests (17/17).

## [30.0.0] - 2026-04-21
- **Milestone (Product Hunt launch)**: Incident Tracker expanded from 36 to 88
  entries, all sourced from the 65-section Survival Guide.
- **Stats**: 707 hooks, 88 incidents, 65 Survival Guide sections.

## [29.9.0] - 2026-04-21
- **UX**: improved post-install experience (clearer install summary / next steps).

## [29.8.0] - 2026-04-20
- **New hook**: `thinking-stall-detector` — detect stalled extended-thinking turns.
- This is the version currently published to npm.

## [29.6.38] - 2026-04-01
- **New hooks (8)**:
  - session-index-repair — rebuild sessions-index.json on exit ([#25032](https://github.com/anthropics/claude-code/issues/25032))
  - subagent-error-detector — detect 529/502/timeout in subagent results ([#41911](https://github.com/anthropics/claude-code/issues/41911))
  - session-backup-on-start — backup session JSONL on start ([#41874](https://github.com/anthropics/claude-code/issues/41874))
  - working-directory-fence — block file ops outside CWD ([#41850](https://github.com/anthropics/claude-code/issues/41850))
  - mcp-warmup-wait — wait for MCP servers on start ([#41778](https://github.com/anthropics/claude-code/issues/41778))
  - pre-compact-transcript-backup — backup transcript before compaction ([#40352](https://github.com/anthropics/claude-code/issues/40352))
  - replace-all-guard — warn/block Edit replace_all:true ([#41681](https://github.com/anthropics/claude-code/issues/41681))
  - subagent-scope-validator — improved: 100-char min, configurable, Issue refs ([#40339](https://github.com/anthropics/claude-code/issues/40339))
- **Docs**: COOKBOOK (token diagnosis + session protection recipes), TROUBLESHOOTING (token consumption section), README.ja (Session Protection section)
- **Tests**: +67 tests for Session Protection hooks (cch-cache-guard 0→7, image-file-validator 0→5, etc.)
- **Stats**: 653 examples, 7,468+ tests, 100% hook coverage

## [29.6.37] - 2026-03-31
- **Tests**: +1,902 batch safety tests (11,933→13,835)
  - null tool_input handling for all 634 hooks
  - Unicode input safety for all 634 hooks
  - Empty-field nested object safety for all 634 hooks
  - Every hook now has 11+ tests (previously 113 hooks had only 7)
- **Stats**: 634 examples, 13,835 tests
- **Public-facing updates**: README, SEO pages, Zenn Book, Qiita all articles patched

## [29.6.36] - 2026-03-30
- **New**: 5 hooks from session 80:
  - git-crypt-worktree-guard, temp-file-cleanup-stop, token-spike-alert
  - worktree-path-validator, settings-mutation-detector
- **Tests**: 11,933 tests (all passing)
- **--examples**: Fixed to show all 634 hooks (was showing 147)
- **cc-health-check**: v1.1.2 with 629+ hook count

## [29.6.35] - 2026-03-30
- **New**: 7 hooks addressing top GitHub Issues (454+ combined reactions):
  - clear-command-confirm-guard (#40931): blocks accidental /clear, suggests /compact
  - claudemd-violation-detector (#40930): periodic CLAUDE.md rules reminder
  - subagent-context-size-guard (#40929, 3r): warns on thin Agent prompts (<100 chars)
  - edit-old-string-validator (#22264, 38r): pre-validates Edit old_string to prevent cascade failures
  - virtual-cwd-helper (#3473, 52r): virtual CWD for mid-session directory switching
  - cwd-drift-detector (#1669, 72r): warns on destructive commands outside project root
  - permission-pattern-auto-allow (#819, 40r): regex-based command auto-approval
- **Tests**: +1,339 tests (10,506→11,845), all passing
- **Issue answers**: 13 GitHub Issues answered with tested hook workarounds
  - High-impact: #17428(85r), #7490(90r), #5512(74r), #1669(72r), #3473(52r)
- **SEO**: 23 pages updated to 629/11,845
- **Zenn Book**: All chapters updated to 629 hooks / 11,845 tests
- **Stats**: 629 examples, 11,845 tests, 23 SEO pages

## [29.6.34] - 2026-03-29
- **New**: 3 hooks addressing top GitHub Issues (132 combined reactions):
  - git-show-flag-sanitizer (#13071, 44r): strips invalid --no-stat from git show via PreToolUse rewrite
  - compact-blocker (#6689, 42r): blocks auto-compaction via PreCompact exit 2
  - webfetch-domain-allow (#9329, 46r): auto-approves WebFetch by domain allowlist
- **Tests**: +40 tests (8,730→8,770), 10 edge case tests for new hooks
- **SEO**: 27 pages updated to 588/8,761
- **Docs**: Zenn Book ch9 catalog updated with 3 new categories
- **Issue answers**: 3 GitHub Issues answered with tested hook workarounds
- **Stats**: 588 examples, 8,770 tests, 51 SEO pages

## [29.6.33] - 2026-03-29
- **New**: 23 hooks in 6 new categories:
  - CI/CD: github-actions-secret-guard, ci-workflow-guard, gitops-drift-guard, dotenv-commit-guard
  - Cloud/Infra: k8s-production-guard, schema-migration-guard, network-exfil-guard
  - MCP Security: mcp-server-allowlist, mcp-tool-audit-log
  - Role-based: role-tool-guard (#40425)
  - Session: session-resume-env-fix (#40391), pre-compact-knowledge-save, headless-empty-result-guard (#40432)
  - Process: spec-file-scope-guard (#40383), read-all-files-enforcer (#40389), permission-entry-validator (#40382), self-modify-bypass-guard (#40463), subagent-claudemd-inject (#40459), system-message-workaround (#40380)
  - Safety: cron-modification-guard (#40421), deploy-path-verify-guard (#40421), edit-counter-test-gate (#40401), session-permission-reset-guard (#40384), token-budget-per-task, cwd-project-boundary-guard, file-change-undo-tracker
- **Docs**: TRIGGER/MATCHER comments added to 308 hooks (585/585 now documented)
- **Tests**: +591 tests (8,139→8,730), all hooks 7+ test coverage
- **SEO**: 27 pages updated to 585/8,730
- **Issue answers**: 13 GitHub Issues answered with hook workarounds
- **Stats**: 585 examples, 8,730 tests, 51 SEO pages

## [29.6.31] - 2026-03-29
- **New**: 3 hooks using v2.1.83 hook events — direnv-auto-reload (CwdChanged), dotenv-watch (FileChanged), pre-compact-checkpoint (PreCompact)
- **New**: 3 hooks — plan-mode-enforcer, shell-wrapper-guard, git-checkout-safety-guard
- **Improved**: destructive-guard built-in — shell wrapper bypass detection (sh -c, python -c, pipe-to-shell)
- **Tests**: 27 new tests for new hooks
- **Stats**: 517 examples, 7,591 tests, 51 SEO pages

## [29.6.28] - 2026-03-29
- **New**: 4 hooks — credential-file-cat-guard (#34819), push-requires-test-pass (#36673), push-requires-test-pass-record, edit-retry-loop-guard (#35576)
- **New**: 3 SEO pages — auto-approve-guide, prevent-credential-leak, owasp-mcp-hooks
- **Docs**: COOKBOOK recipes for credential guard and push-requires-test
- **Docs**: examples/README overhaul (38→511), Japanese README overhaul (36→511)
- **Tests**: 36 new tests for new hooks
- **Tests**: Trigger detection tests (verify PermissionRequest/SessionStart/PreToolUse parsing)
- **Stats**: 514 examples, 7,564 tests, 51 SEO pages

## [29.6.0] - 2026-03-27
- **Improved**: worktree-unmerged-guard — python3 fallback for macOS (no jq dependency), auto-detect default branch
- **Fix**: CI workflow — add git config for tests that require commits
- **Stats**: 347 examples, 2,352 tests

## [29.5.0] - 2026-03-26
- **New**: 3 hooks invented and released — auto-mode-safe-commands, write-secret-guard, compound-command-allow
- **New**: 10 example hooks — credential-exfil-guard, rm-safety-net, worktree-unmerged-guard, permission-audit-log, session-token-counter, file-change-tracker, output-secret-mask + 3 more
- **New**: 5 hooks — git-stash-before-danger, session-summary-stop, max-edit-size-guard, auto-approve-readonly-tools, uncommitted-changes-stop
- **Tests**: 2,352 tests (up from 1,062)
- **Stats**: 348 examples

## [29.4.0] - 2026-03-26
- **Tests**: 32 new tests for 10 example hooks (scope-guard, git-config-guard, path-traversal-guard, env-var-check, auto-approve-readonly/git-read/build/python, block-database-wipe, deploy-guard, network-guard)
- **Fix**: --doctor now checks all 9 hook trigger types
- **Stats**: 1062 tests (up from 1030)

## [29.3.0] - 2026-03-26
- **Fix**: Unified trigger detection with regex (case-insensitive `Trigger:` / `TRIGGER:`)
- Previously, hooks with `# Trigger: X` (capitalized) would not be detected by --install-example

## [29.2.0] - 2026-03-26
- **New**: UserPromptSubmit hook examples (prompt-length-guard, prompt-injection-detector)
- **Fix**: --install-example now detects UserPromptSubmit trigger
- **Fix**: Case-insensitive trigger detection (Trigger: vs TRIGGER:)
- **Stats**: 338 examples, 1030 tests

## [29.1.0] - 2026-03-26
- **Tests**: Trigger detection tests (verify PermissionRequest/SessionStart/PreToolUse parsing)
- **Stats**: 1024 tests (2^10 milestone!)

## [29.0.0] - 2026-03-26
- **BREAKING**: `--install-example` now correctly detects PermissionRequest trigger and comment-style matchers
- Previously, PermissionRequest hooks were silently registered as PreToolUse (wrong trigger!)
- Comment-style `# Matcher: Edit|Write` headers now parsed (previously only JSON format)
- All 4 new PermissionRequest examples install correctly with proper trigger and matcher

## [28.9.0] - 2026-03-26
- **New**: 4 PermissionRequest hooks now discoverable via `--examples permission`
- **Docs**: hook-patterns.html — PermissionRequest pattern with copy-paste code
- **Fix**: --examples category list updated (136 discoverable, 336 total)

## [28.8.0] - 2026-03-26
- **New**: auto-approve-compound-git.sh — PermissionRequest hook for compound git commands (#30519)
- **Fix**: Example count corrected to 336 (was underreported)
- **Fix**: Draft factcheck — code examples now match actual hook files
- **Stats**: 336 examples, 1018 tests

## [28.7.0] - 2026-03-26
- **New examples**: allow-claude-settings.sh, allow-protected-dirs.sh (PermissionRequest)
- **Docs**: TROUBLESHOOTING — Stop hook `-p` empty output known issue (#38651)
- **Stats**: 333 examples, 1009 tests (1000+ milestone!)

## [28.6.0] - 2026-03-26
- **New**: PermissionRequest hook support — `allow-git-hooks-dir.sh` example (first PermissionRequest example)
- **Docs**: Hook execution order documented (PreToolUse → built-in checks → PermissionRequest)
- **Docs**: TROUBLESHOOTING.md — new section "PreToolUse allow doesn't bypass protected directory prompts"
- **Docs**: COOKBOOK.md — Recipe #27: Bypass Protected Directory Prompts
- **Stats**: 331 examples, 996 tests, 49 commands, 23 web tools

## [28.4.9] - 2026-03-26
- **Bug fix**: --rules YAML template regex escaping (\\s → \s for grep whitespace matching)
- **Bug fix**: Windows path backslash in --shield, --guard, --rules, --protect (#1)
- **Bug fix**: Add missing shebangs to 145 example hooks
- **New hooks**: hook-permission-fixer (auto-fix +x at session start), response-budget-guard (anti-loop)
- **New web tool**: Permission Checker (23rd) — diagnose broken paths, Windows issues
- **--doctor**: Now detects Windows backslash paths in hook commands
- **--audit**: New checks for Windows paths (CRITICAL) and missing permission fixer (LOW)
- **COOKBOOK.md**: 26 practical recipes for common scenarios
- **Windows Support**: README section added with diagnosis guide
- **Docs**: Ops Kit CTA on 7 pages (getting-started, hub, recipes, playground, validator, cheatsheet, faq)
- **Stats**: 330 examples, 988 tests, 49 commands, 23 web tools
- **Issue answers**: anthropics/claude-code #38901, #38923; cc-safe-setup #1
- **npm**: 10,143 downloads/day

## [28.3.5] - 2026-03-25
- **327 HOOKS** (314 bash + 5 non-bash + 8 built-in), **955 tests**
- New hooks: skill-gate, auto-approve-test, no-push-without-ci, no-commit-fixup, no-large-commit, no-sleep-in-hooks, check-git-hooks-compat
- --shield now auto-installs memory-write-guard, skill-gate, auto-approve-test, auto-approve-readonly
- 227 hooks in web registry
- Issue answers: #38040 (memory permission gap), #37988 (Windows hook timeout), #37913 (permission timeout)
- GitHub profile README created (https://github.com/yurukusa/yurukusa)
- Ops Kit LP updated (8K downloads/week, correct Gumroad slug)

## [28.1.0] - 2026-03-25
- **305 HOOKS** — 244 new hooks in session 40 (61→305)
- 210 hooks in web registry
- Session 40 stats: 68 npm releases, 9 OSS PRs, 15 issue answers, 25 articles

## [28.0.0] - 2026-03-25
- **300 HOOKS** — 239 new hooks in one session (61→300)
- 40 React/JS/performance hooks, 15 OWASP security hooks, 10 a11y hooks
- 45 CLI commands, 561 tests, 5 languages, 11 web tools
- 200 hooks in registry, 25 articles, 67 npm releases

## [26.0.0] - 2026-03-25
- **250 HOOKS** — 189 new hooks in one session (61→250)
- 15 OWASP security hooks (injection, XSS, auth, TLS, CORS, CSP)
- 200 hooks in web registry, 45 commands, 561 tests
- 24 articles (5 published), 65 npm releases

## [22.0.0] - 2026-03-25
- **200 HOOKS MILESTONE** — 139 new hooks in one session (61→200)
- 45 CLI commands, 561 tests, 5 languages, 11 web tools, 140 registry hooks
- 9 OSS PRs (3,755★), 14 issue answers, 23 articles, 11 Zenn Book chapters
- Quality hooks: no-var, prefer-const, no-any-type, no-nested-ternary, no-sync-fs
- Security hooks: sql-injection-detect, cors-star-warn, no-http-without-https
- Code review hooks: max-function-length, no-deep-nesting, no-empty-function

## [17.4.0] - 2026-03-25
- **165 hooks** (+104 from session start), **45 CLI commands**, **561 tests**
- --changelog, --init-project, --score, --test-hook, --save-profile, --guard, --suggest, --why, --replay, --from-claudemd, --team, --profile, --analyze, --health, --quickfix, --migrate-from, --diff-hooks, --shield
- 11 web tools (+ Setup Wizard), 123 registry hooks
- 9 OSS PRs (3,755★), 14 issue answers, 22 articles, 11 Zenn Book chapters
- CDP dialog polling fix, npm 40% smaller
- 104 new hooks in one session — the largest single-session expansion ever

## [14.1.0] - 2026-03-25
- **141 hooks**, **44 CLI commands**, **561 tests**, **5 languages**, **11 web tools**
- --init-project, --score, --test-hook, --save-profile
- Setup Wizard, 104 registry hooks, 9 OSS PRs (3,755★), 12 issue answers
- CDP dialog polling fix, npm 40% smaller, Zenn Book Ch9-10
- 21 new hooks: relative-path, encoding, ssh-key, terraform, k8s, subagent-scope, etc.

## [11.0.0] - 2026-03-24
- **--suggest**: Predictive risk analysis (git history, files, deps, config)
- **--why**: Show real incident behind each hook (20 documented)
- **--replay**: Visual blocked commands timeline
- **--guard**: Instant rule enforcement from plain English
- **--diff-hooks**: Compare hook configurations
- **120 hooks**, **40 CLI commands**, **544 tests**, **5 languages**
- 10 web tools + Hub, 80 registry hooks
- OSS: 4 PRs to 3 repos (3,255★ combined)
- CDP dialog polling fix (WSL2 root cause)
- typosquat-guard, test-coverage-guard, stale-env-guard, permission-cache, git-author-guard, typescript-strict-guard, ci-skip-guard, debug-leftover-guard
- 14 article drafts (10 cron, 3 CDP pending)

## [10.3.0] - 2026-03-24
- **--guard**: Instant rule enforcement — `--guard "never touch the database"`
- **--diff-hooks**: Compare global vs project hook configurations
- **531 tests** (500+ milestone), **116 hooks**, **37 CLI commands**, **5 languages**
- test-coverage-guard, stale-env-guard, ci-skip-guard, debug-leftover-guard
- Rust destructive-guard example
- 10 web tools + Hub portal + By Example + Migration Guide + Troubleshooting + Matrix + Settings Reference
- 13 article drafts (1 published, 9 cron, 3 CDP-pending)
- Medium story draft for maximum reach

## [10.0.0] - 2026-03-24
- 500+ test milestone, fixed test ordering

## [9.3.0] - 2026-03-24
- **--from-claudemd**: Convert CLAUDE.md rules to enforceable hooks (16 patterns)
- **--health**: Hook health dashboard (size, permissions, age)
- **--migrate-from**: Migrate from safety-net/hooks-mastery/manual
- **Rust** destructive-guard example (5 languages)
- **10 web tools**: Hub, Matrix, Troubleshooting, Settings Reference, By Example, Migration, Builder, FAQ, Cheat Sheet, Playground
- **114 hooks** (106 bash + 2 Python + 1 Go + 1 TypeScript + 1 Rust + 3 new)
- **35 CLI commands**, **457 tests**
- ci-skip-guard, debug-leftover-guard, env-drift-guard, package-script-guard, git-blame-context, import-cycle-warn, docker-prune-guard, node-version-guard, pip-venv-guard, no-git-amend-push, sensitive-regex-guard, lockfile-guard, git-lfs-guard, context-snapshot

## [9.1.0] - 2026-03-24
- Improved --generate-ci (npx-based, actually works)

## [9.0.0] - 2026-03-24
- 112 hooks, 34 commands, 8 web tools

## [8.4.0] - 2026-03-24
- **--team**: Project-level hook sharing (relative paths, git-committable)
- **--analyze**: Session analysis (blocked commands, git activity, costs)
- **--profile**: Safety profiles (strict/standard/minimal)
- **32 CLI commands**, **457 tests**, **100 hooks**
- 24 new tests for newest hooks batch
- 7 article drafts with cron pipelines (3/28-4/2)

## [8.3.0] - 2026-03-24
- **--profile**: Switch safety profiles (strict/standard/minimal)
- **--analyze**: See what Claude did in sessions (blocked commands, git activity, costs)
- **100 HOOKS milestone** (92 examples + 8 built-in)
- 10 new hooks: no-console-log, backup-before-refactor, rate-limit-guard, file-size-limit, no-eval, branch-naming-convention, pr-description-check, no-wildcard-import, no-todo-ship, license-check
- hardcoded-secret-detector, changelog-reminder
- **31 CLI commands**, **433 tests**

## [8.1.0] - 2026-03-24
- 100 hooks milestone

## [8.0.0] - 2026-03-24
- **--shield**: Maximum safety in one command (fix + scan + install + CLAUDE.md)
- **88 hooks** (8 built-in + 80 examples), **433 tests**, **29 commands**
- worktree-guard, commit-scope-guard, compact-reminder, auto-stash-before-pull, revert-helper
- Hook Builder web tool (generate from plain English)
- FAQ page (15 questions answered)
- 5 web tools total (Audit, Cheat Sheet, Builder, FAQ, Playground)

## [7.9.0] - 2026-03-24
- Hook Builder and FAQ web tools
- Zenn tutorial published

## [7.8.0] - 2026-03-24
- revert-helper Stop hook
- OSS: PR #40 to disler/multi-agent-observability (1,295★)

## [7.7.0] - 2026-03-24
- **420 automated tests**, **83 hooks** (8 built-in + 75 examples)
- **error-memory-guard**: Block retries of commands that already failed 3x
- **parallel-edit-guard**: Detect concurrent edits via lock files
- **large-read-guard**: Warn before catting large files into context
- **strict-allowlist**: Allowlist-only enforcement mode (#37471)
- Gumroad Ops Kit updated to v3.2 via CDP (self-service)

## [7.6.0] - 2026-03-24
- strict-allowlist hook added
- 72 examples, 409 tests

## [7.5.0] - 2026-03-24
- **405 automated tests** (400+ milestone)
- **71 example hooks** (68→71: fact-check-gate, token-budget-guard, conflict-marker-guard)
- Hooks Cheat Sheet (copy-paste patterns, 30+ recipes)
- GitHub Issue answers with hook code (#37888, #38050, #38057)

## [7.4.0] - 2026-03-24
- **uncommitted-work-guard**: Block destructive git with uncommitted changes (#37888)
- **test-deletion-guard**: Warn when removing test assertions (#38050)
- **overwrite-guard**: Warn before silently overwriting files (#37595)
- **memory-write-guard**: Log writes to ~/.claude/ directory (#38040)
- 68 example hooks, 394 tests

## [7.3.0] - 2026-03-24
- **--quickfix**: Auto-detect and fix 10 common Claude Code problems
- **367 automated tests** (+47 from v7.2.0, full example hook coverage)
- **28 CLI commands** total
- Hook Playground web tool (interactive command safety checker)
- Beginner tutorial drafts (EN + JP)

## [7.2.0] - 2026-03-24
- **71 total hooks** (8 built-in + 61 bash + 2 Python)
- **27 CLI commands** including --report, --generate-ci, --migrate, --compare, --issues
- **318 automated tests** (+145 from session start)
- Python hook examples (destructive_guard.py, secret_guard.py)
- Unified SPA web tool (audit + builder + cookbook + ecosystem + cheat sheet)
- New hooks: no-deploy-friday, work-hours-guard, protect-claudemd, reinject-claudemd,
  symlink-guard, env-source-guard, no-sudo-guard, no-install-global, git-tag-guard,
  npm-publish-guard, auto-approve-{go,cargo,make,gradle,maven}, output-length-guard
- 15 example hooks with individual functional tests

## [3.7.0] - 2026-03-24
- **--benchmark**: Hook performance measurement (10 runs, color-coded)
- dependency-audit.sh, diff-size-guard.sh, commit-quality-gate.sh
- session-handoff.sh, loop-detector.sh, hook-debug-wrapper.sh
- Japanese README (docs/README.ja.md)
- CI: example hooks syntax check (36/36)
- 21 commands, 36 examples, 173 tests

## [3.4.0] - 2026-03-24
- **--diff**: Compare settings between environments
- **--share**: Generate shareable audit URL
- **--lint**: Static analysis of hook configuration
- **--create**: Natural language hook generator (9 templates)
- TROUBLESHOOTING.md, SETTINGS_REFERENCE.md, MIGRATION.md
- Cheat Sheet, Ecosystem comparison page
- Web: setup generator + URL import

## [3.0.0] - 2026-03-24
- **--doctor**: Diagnose hook issues (jq, permissions, shebang)
- **--watch**: Live blocked command dashboard
- **--stats**: Block history analytics
- **--export/--import**: Team hook sharing
- **--audit --json**: CI output with threshold support
- case-sensitive-guard.sh (#37875), compound-command-approver.sh (#30519)
- tmp-cleanup.sh (#8856), GitHub Action outputs

## [2.0.6] - 2026-03-23
- **9 new examples**: deploy-guard, network-guard, test-before-push, large-file-guard, commit-message-check, env-var-check, timeout-guard, branch-name-check, path-traversal-guard, todo-check
- Tests: 138 → 154
- 25 examples total (was 19 in v2.0.0)
- Categories: Safety Guards (12), Auto-Approve (5), Quality (6), Recovery (2), UX (1)

## [2.0.0] - 2026-03-23
- **Categorized `--examples` output** — 5 categories: Safety Guards, Auto-Approve, Quality, Recovery, UX
- **New examples: deploy-guard, network-guard, test-before-push, large-file-guard** (4 new)
- 19 examples total (was 15)
- Tests: 130 → 138

## [1.9.4] - 2026-03-23
- **New example: deploy-guard.sh** — blocks deploy commands when uncommitted changes exist
- Detects rsync, scp, firebase, vercel, netlify, fly, heroku
- Born from [#37314](https://github.com/anthropics/claude-code/issues/37314) (deploy without commit)
- Tests: 126 → 130
- 16 examples total (was 15)

## [1.9.3] - 2026-03-23
- **New example: git-config-guard.sh** — blocks git config --global modifications without consent
- Born from [#37201](https://github.com/anthropics/claude-code/issues/37201) (unauthorized git config changes)
- CLI smoke tests added (--help, --examples, --install-example)
- Tests: 119 → 126
- 15 examples total (was 14)

## [1.9.2] - 2026-03-23
- **`--status` now detects installed example hooks** — shows which examples are active alongside the 8 built-in hooks
- CLI incidents list: added PowerShell Remove-Item and Prisma migrate reset

## [1.9.1] - 2026-03-23
- **New example: auto-checkpoint.sh** — auto-commit after every edit for rollback protection
- Born from [#34674](https://github.com/anthropics/claude-code/issues/34674) (context compaction reverting uncommitted edits)
- Tests: 116 → 119
- 14 examples total (was 13)

## [1.9.0] - 2026-03-23
- **New `--install-example` flag** — install any example hook with one command
  - `npx cc-safe-setup --install-example block-database-wipe`
  - Copies hook to `~/.claude/hooks/`, adds to `settings.json`, makes executable
  - Auto-detects trigger (PreToolUse/PostToolUse/etc.) and matcher from hook header

## [1.8.4] - 2026-03-23
- **New example: scope-guard.sh** — blocks file operations outside project directory (absolute paths, home dir, parent escapes)
- Born from [#36233](https://github.com/anthropics/claude-code/issues/36233) (entire Mac filesystem deleted)
- Tests: 99 → 106
- 13 examples total (was 12)

## [1.8.3] - 2026-03-23
- **New example: protect-dotfiles.sh** — blocks modifications to ~/.bashrc, ~/.aws/, ~/.ssh/ and chezmoi without diff
- **New example: allowlist.sh** added to --examples index
- Born from [#37478](https://github.com/anthropics/claude-code/issues/37478) (environment file destruction)
- Tests: 90 → 99
- 12 examples total (was 10)

## [1.8.2] - 2026-03-22
- **New example: auto-snapshot.sh** — automatic file snapshots before edits for rollback protection
- **New example: auto-approve-python.sh** — auto-approve pytest, mypy, ruff, black, isort
- 10 examples total (was 8)

## [1.8.0] - 2026-03-22
- **New `--examples` flag** — lists all 8 example hooks with descriptions from the CLI
- **New example: block-database-wipe.sh** — blocks destructive database commands (Laravel, Django, Rails, raw SQL)
- Born from [#37405](https://github.com/anthropics/claude-code/issues/37405) and [#37439](https://github.com/anthropics/claude-code/issues/37439)

## [1.7.2] - 2026-03-22
- **Fix: echo/printf/cat false positives** — string output commands mentioning PowerShell patterns no longer blocked
- Tests: 89 → 90

## [1.7.1] - 2026-03-22
- **Fix: git commit message false positive** — commit messages containing PowerShell command text no longer blocked
- Restored git checkout/switch --force check
- Tests: 88 → 89

## [1.7.0] - 2026-03-22
- **PowerShell destructive command protection** — blocks `Remove-Item -Recurse -Force`, `rd /s /q`, `del /s /q`
- Born from [#37331](https://github.com/anthropics/claude-code/issues/37331): Claude ran `Remove-Item -Recurse -Force *` destroying all unpushed source code
- Tests: 82 → 88

## [1.6.5] - 2026-03-22
- Security fix: `sudo mkfs` now blocked
- WSL2: `/mnt` paths now blocked for rm
- `--no-preserve-root` detection requires `rm` context (prevents false positive on echo)
- Tests: 79 → 82

## [1.6.0] - 2026-03-22
- **Security fix: `rm -rf .` now blocked** — current directory deletion was previously allowed
- Also blocks `rm -rf ./` (trailing slash variant)
- `rm -rf ./subdirectory` still allowed (safe subdirectory deletion)
- Tests: 76 → 79
## [1.5.4] - 2026-03-22
- Secret-guard edge case tests: .env.production, id_rsa, .env.local
- Branch-guard edge case tests: force-with-lease, HEAD:main push
- Tests: 72 → 76
- Headless mode limitation note in README (#36071)

## [1.5.3] - 2026-03-22
- Branch-guard edge case tests: force-with-lease, HEAD:main push
- Tests: 69 → 72

## [1.5.2] - 2026-03-22
- **Expanded `--verify` tests**: 8 → 12 (compound commands, force-push, git reset --hard, sudo)
- **New example: auto-approve-build.sh** — auto-approve npm/cargo/go/python build/test/lint commands
- **New example: edit-guard.sh** — defense-in-depth for Edit/Write deny bypass (#37210)
- **FAQ section** in README (skills vs hooks confusion, health-check interpretation, performance)
- Hook count fix in README: 7 → 8
- COOKBOOK recipe count: 8 → 9
- Tests: 66 → 69 (api-error-alert coverage)

## [1.5.1] - 2026-03-21
- npm packaging fix

## [1.5.0] - 2026-03-21
- **New hook: API Error Alert** — notifies when sessions die from rate limits, auth failures, or server errors
- Desktop notification (macOS/Linux/WSL2) + error log
- 7 → 8 hooks total
- --verify now tests all 8 hooks (8/8)

## [1.4.1] - 2026-03-21
- **Fix: compound command detection** — `cd /tmp && git checkout --force` now correctly blocked
- Tests: 61 → 63

## [1.4.0] - 2026-03-21
- **New: git checkout/switch --force protection** — blocks `--force`, `-f`, `--discard-changes`
- **Fix: sudo check was unreachable** — early `exit 0` before Check 6 made sudo protection dead code
- Tests: 56 → 61

## [1.3.0] - 2026-03-21
- **New: `--verify` option** — sends test inputs to each installed hook, confirms block/allow behavior (6 tests)
- `--status` now returns exit code 1 when hooks are missing (CI-friendly)
- Tests: 44 → 56 (+12 edge cases for destructive-guard and secret-guard)
- New edge case tests: `rm -rf /var`, `git add .` with .env, `git add -A`, `.env.production`, `.pem`

## [1.2.1] - 2026-03-21
- README: updated COOKBOOK recipe count (6 → 8)
- npm publish with latest README

## [1.2.0] - 2026-03-21
- **New: `--status` option** — check which hooks are installed and settings.json configuration
- Tests: 41 → 44

## [1.1.3] - 2026-03-21
- Added `.npmignore` to reduce package size (82KB → 42KB)
- Tests: 39 → 41 (added CLI smoke tests for --help and --dry-run)
- All 7 hooks now have test coverage

## [1.1.2] - 2026-03-21
- Improved npm search discoverability (16 keywords)
- Added `npm test` script

## [1.1.1] - 2026-03-21
- Added `sudo` protection to destructive-guard (blocks `sudo rm -rf`, `sudo chmod 777`)
- Tests: 33 → 35

## [1.1.0] - 2026-03-21
- **New hook: secret-guard** — blocks `git add .env`, credential files, `git add .` with .env present
- **Enhanced branch-guard** — now blocks `--force` push on ALL branches (configurable via `CC_ALLOW_FORCE_PUSH=1`)
- 6 → 7 hooks total
- Added 33 automated tests (`bash test.sh`)
- Added GitHub Actions CI
- Added animated terminal demo SVG to README
- README now references related GitHub Issues (#6527, #16561, #36339, #36640)

## [1.0.10] - 2026-03-20
- Fixed false positives in destructive-guard (git reset --hard in echo/string arguments)
- Moved hook scripts to external `scripts.json` (fixes template literal crash)
- Added NFS mount detection to destructive-guard (#36640)
- Added block logging to `~/.claude/blocked-commands.log`

## [1.0.0] - 2026-03-20
- Initial release with 6 hooks:
  - destructive-guard (rm -rf, git reset --hard, git clean)
  - branch-guard (main/master push protection)
  - syntax-check (Python, Shell, JSON, YAML, JS)
  - context-monitor (graduated warnings at 40/25/20/15%)
  - comment-strip (bash comments breaking permissions, #29582)
  - cd-git-allow (auto-approve read-only cd+git compounds, #32985)

- **New: git checkout/switch --force protection** — blocks `git checkout --force`, `git switch --force`, `git switch --discard-changes`
- **Fix: sudo check was unreachable** — early `exit 0` before Check 6 made sudo protection dead code
- Tests: 56 → 61 (+5 git checkout/switch tests)
- Inspired by competitor safety-net v0.8.0 git rules
