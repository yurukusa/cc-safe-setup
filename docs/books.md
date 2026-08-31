# Books, courses and the paid team pack

The hooks in this repository are MIT-licensed and work without any of this. The write-ups behind
them are long-form, so they live here rather than in the README.

Moved out of the README on 2026-08-31 to keep that file a tool document — see
[the note at the bottom](#why-this-is-not-in-the-readme).

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
- [副の作業者の沈黙の失敗](https://zenn.dev/yurukusa/books/sub-agent-observability) (¥1,500) —
  eight incidents where a sub-agent reported success and had run nothing, sorted into four
  failure shapes: fabricated dispatch, silent stop, no observability, scope drift
- [MCP プラグインの隠れたコストと信頼性](https://zenn.dev/yurukusa/books/mcp-plugin-reliability) (¥800) —
  five vulnerability classes in third-party MCP plugins and what a user (not the author) can
  do about each
- [AGENTS.md × Claude Code を両立する5つの方法](https://zenn.dev/yurukusa/books/agents-md-interop) (¥1,500) —
  the Japanese edition of the AGENTS.md Interop Handbook below
- [チーム/企業導入 安全パック](https://zenn.dev/yurukusa/books/cc-team-safety-pack) (¥3,000) —
  the approval write-up, the policy, the permission design and the monthly review, for the
  person who has to get Claude Code past their own organisation

**In English:**

- [Claude Code Safety Mastery](https://leanpub.com/claude-code-safety-mastery) (from $9.99, 57 pages) —
  the defensive hooks in this repository, grouped from the five to install first through Git
  protection and credential guards, and eight dated incidents where the guard itself failed silently
- [Claude Code Migration Playbook](https://leanpub.com/claude-code-migration-playbook) (from $11.99, 251 pages) —
  stay, switch, or build your own stack: five measurable triggers, a 30-day cost projection for
  each path, a decision tree that returns one recommendation, and a 48-hour rollback if it was wrong
- [Cut Your Claude Code Token Usage in Half](https://leanpub.com/claude-code-token-savings) (from $9.99, 89 pages) —
  where the tokens actually go, measured across 800+ hours rather than reasoned about:
  overnight cost spikes, sub-agents, thinking tokens, and context-window bloat
- [Claude Code AGENTS.md Interop Handbook](https://leanpub.com/claude-code-agents-md-interop) (from $9.99, 27 pages) —
  which file each of nine tools reads, six ways to keep them in sync, and how to check what
  your own setup actually loads rather than trusting a closed issue
- [CLAUDE.md Under Test](https://leanpub.com/claude-md-under-test) (from $9.99, 86 pages) —
  thirty-nine trials on whether a rule written in `CLAUDE.md` is actually obeyed, what a hook
  adds once it is, and the exit code that decides whether your guard fails open or closed.
  The rule was obeyed in all twenty-two trials where it was written, which is the opposite of
  what I had been telling people — the correction is posted free in
  [Discussion #59](https://github.com/yurukusa/cc-safe-setup/discussions/59). Every trial's
  data and the harness are in the appendices

The first four are also sold together as
[The Claude Code Operator's Library](https://leanpub.com/b/cc-operators-library) (from $29).
**All five have a free sample you can read before deciding.**

**More than one person.** Each of the five is also sold at a team discount — up to 3, 5, 10, 15
or 25 members in a single purchase, one order and one receipt, with no quote and no sales call.
The per-member price falls as the count rises: for a $9.99 book, three members cost $24 rather
than $29.97, and twenty-five cost $149 rather than $249.75. The $11.99 Migration Playbook is $29
for three and $179 for twenty-five. Same book, same files; only the number of people covered
differs. The bundle and the course have no multiple-copy packages, so a team that wants the whole
library buys each book's team discount separately.

The 50-point checklist in `audit/` also exists as a scored course, if you would rather work
through it as lessons with quizzes than run the checklist yourself:
[The Claude Code Safety Audit](https://leanpub.com/c/claude-code-safety-audit) (from $49) —
six sections, the one-command test that hands a hook the operation it should refuse and reads
the exit code, and the eight incidents where the guard failed silently. It uses the same four
scripts in `audit/`, which stay free and MIT-licensed here.

Two of them are on Gumroad as well, if you prefer that store:
[Migration Playbook](https://yurukusa.gumroad.com/l/claude-code-migration-playbook) ($19) and
[the token book](https://yurukusa.gumroad.com/l/azrdt) (¥2,500).

All of them are optional, and every hook in this repository works without them. The reason they are
listed at all is that the Japanese editions do not surface in search or in Zenn's own topic listings
for this account (measured across 19 topics on 2026-08-09: zero appearances), so this page is one
of the few places they can be found from.

## The paid team pack

One paid thing exists, and it needs no inquiry either: the [Team Safety Rollout Pack](https://yurukusa.booth.pm/items/8230188) (¥3,000, one-off) bundles the shared policy template, the CI gate with defaults already chosen, and a written walkthrough of real reported incidents.

## Written audits

Three asynchronous written audits exist ($29 and $219): no call, no meeting, and nothing is ever
run in your environment. Each publishes its full deliverable before you buy, run against my own
setup. Scope, prices and the samples are in [SERVICES.md](../SERVICES.md). Corporate audits,
training, rollout consulting and monthly retainers are **not** offered.

## Why this is not in the README

On 2026-07-02 this repository's README was cut from 778 lines to 74 and every paid link removed,
as part of the compliance work promised to GitHub after an account-level anti-spam flag
(the one that made every page under `yurukusa.github.io` return 404). GitHub's Acceptable Use
Policy §10 rules out repositories whose primary purpose is promotion. Between July and August the
README grew back to 302 lines and 13 paid links, one justified pull request at a time, without
anyone deciding to take that risk again. This page is where that content lives now.
