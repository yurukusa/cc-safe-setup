# Services

If you want more than what the free tools give you, there are four paid options. All are fulfilled using the same methodology I use to run Claude Code autonomously, applied to your specific setup.

This page is in English, but Japanese orders are welcome for all four: order and write your request in Japanese and the report comes back in Japanese. 日本語でも受け付けます（注文と依頼を日本語で書いていただければ、報告書は日本語でお返しします）。

---

## 1. CLAUDE.md Audit — $29 (¥3,980)

**What you get:**

A written audit of your `CLAUDE.md` (and optionally `settings.json` + your 5 most-invoked hooks), delivered as a Markdown report within 48 hours.

**See exactly what you get: [a full sample report](./docs/claude-md-audit-sample.md).** It is this audit run against my own 608-line, three-layer setup — real findings, including two rules that could not be followed at all. Also available in Japanese: **[見本の報告書（日本語）](./docs/claude-md-audit-sample-jp.md)** — same content, same figures. 日本語の説明ページは **[CLAUDE.md の監査（¥3,980・48時間）](https://yurukusa.github.io/cc-safe-setup/claude-md-audit-jp.html)** にあります。

The report covers:

1. **Reference resolution** — every path your rules depend on, checked against the scope the rule actually runs in. The failure this catches is not a missing file: it is a file that *exists somewhere else*, so it passes existence checks while the rule stays silently unfollowable.
2. **Testable-assertion ratio** — how much of your CLAUDE.md is aspirational (and therefore silently drops out under pressure) vs. checkable, as a measured ratio per layer.
3. **Cross-layer redundancy** — rules duplicated between your global, home and project files. This is an ownership problem, not a cost problem: editing one copy leaves the other in force and neither file says so.
4. **Vague-rule detection** — the specific lines the model is most likely to ignore, with concrete rewrites that attach a checkable condition without changing your intent.
5. **Top-3 fixes**, ranked by expected impact, with before/after diffs ready to paste.

**On token weight:** earlier versions of this page led with "how much your instructions cost per turn." Having measured it, I think that was the wrong headline. `CLAUDE.md` sits in the cached prefix, so on my own setup, deleting *every* duplicated rule works out to roughly $0.24–$1.19/month. The report still includes the token arithmetic for your files — as a bound, and usually as a reason **not** to spend your time there. If your bill is the problem, the Token Burn Audit below reads session logs, which is where the money actually goes.

**Not included:** a live 1:1 call, hook implementation, or code review beyond the files you submit. This is an audit, not consulting. The diffs are proposals; you apply them.

**How to book:**

1. Order at https://ko-fi.com/yurukusa/commissions — listing: *CLAUDE.md Audit — written report within 48h*, ¥3,980 (≈$29). _If that listing is ever missing, a ¥3,980 tip at https://ko-fi.com/yurukusa with the note "CLAUDE.md audit" is honored at the same price._
2. Open an Audit Request issue on this repo using [the template](./.github/ISSUE_TEMPLATE/3-audit_request.md). Paste your CLAUDE.md there, or — if you would rather not publish it — say so in the issue and I reply with a private route. Mention your Ko-fi order so the two can be matched.
3. You receive the report as an issue reply, and the issue is closed when you confirm it.

If you cannot post anything publicly at all, say so in the Ko-fi order message instead and I'll arrange another route without an issue.

**Attaching a file to an issue does not make it private.** This repository is public, and attachment URLs on a public repository can be opened by anyone who has the link. If your `CLAUDE.md` should not be public, do not attach it — ask for the private route instead. (This page said the opposite until 2026-08-12; it was wrong.)

**A `CLAUDE.md` is not always harmless.** Mine names internal paths; other people's name customers, hostnames and occasionally a key. Strip anything you would not put on a public page before you post it — the issue is public. And as above: your file is deleted within 30 days of delivery, is not published, and is not used to train anything.

**Refund:** if I cannot produce a useful audit (for example because the file is effectively empty, or is entirely in a language I cannot parse), full refund via Ko-fi.

---

## 2. Token Burn Audit — $29 (¥3,980)

**What it is:** a diagnosis of where your Claude Code tokens are actually going, based on *your* `/cost` output and session transcripts. Not a generic "7 tips" article — a specific read of your real usage.

**Why this still matters — counted 2026-08-13, not in April:**

> *"I used up Max 5 in 1 hour of working, before I could work 8 hours"* — user report via [DevOps.com, April 2026](https://devops.com/claude-code-quota-limits-usage-problems/)

The reports did not stop when that quote was written. Both of these are still open:

| Issue | Reactions | Comments | State |
|---|---|---|---|
| [#16157](https://github.com/anthropics/claude-code/issues/16157) — hitting usage limits immediately on Max | 724 | 1,486 | open |
| [#38335](https://github.com/anthropics/claude-code/issues/38335) — Max session limits draining in as little as 19 minutes | 543 | 831 | open |

I counted the same way across the issues about hooks and settings silently not applying — which is the subject of the more expensive audit in §3. That cluster comes to **371** reactions and comments in total. This one comes to **9,643**.

That is not a claim that this audit fixes the platform's limits. It is why the cheaper audit sits on this subject: it is where people are actually stuck.

Context from April 2026, kept because the causes have not changed:

- March 23, 2026 is where this cluster starts ([#38335](https://github.com/anthropics/claude-code/issues/38335), [#41788](https://github.com/anthropics/claude-code/issues/41788))
- Anthropic confirmed investigation: "top priority for the team"
- Root cause partially identified: `cache_read` tokens may count at full rate against rate limits (negating caching benefits)
- April 21 pricing whiplash: Claude Code removed from $20 Pro plan, reverted hours later

This audit tells you which of the 56 cataloged token-waste symptoms (Token Book Ch.8) are actually firing in *your* logs — not "in general."

**See exactly what you get: [a full sample report](./docs/token-burn-audit-sample.md).** It is this audit run against my own 156 session logs (21,770 API round-trips), including the part where the largest waste pattern turned out to match *none* of the 56 symptoms, and the part where my own hooks were failing to catch it.

**What you get (delivered in 48 hours as a Markdown report in your issue thread):**

1. **Top 3 waste patterns** found in your logs, ranked by estimated cost. Each mapped to a Ch.8 symptom where one applies — and flagged explicitly when none does. In the sample, the single largest pattern matched *none* of the 56.
2. **Per-pattern fix**: the exact hook, CLAUDE.md change, or workflow adjustment that addresses it. Example hooks from `cc-safe-setup/examples/` that you can install in one command.
3. **Estimated savings range** (stated as a range, not a single number — the actual savings depend on your next month's usage pattern).
4. **`cc-token-diet` walkthrough**: if you haven't run [cc-token-diet](https://github.com/yurukusa/cc-token-diet) yet, I include the command line and help interpret the output.

**Not included:** real-time monitoring, implementation (you apply the fixes yourself), or a guarantee that your $ spend will drop by a specific amount. If the report does not identify at least one addressable waste pattern, full refund via Ko-fi.

**How to book:**

1. Order at https://ko-fi.com/yurukusa/commissions — listing: *Token Burn Audit — written report within 48h*, ¥3,980 (≈$29). _If that listing is ever missing, a ¥3,980 tip at https://ko-fi.com/yurukusa with the note "Token Burn audit" is honored at the same price._
2. Open a Token Burn Audit Request issue on this repo using [the template](./.github/ISSUE_TEMPLATE/4-token_burn_audit_request.md) — and post **only** the `/cost` summary and a couple of lines about your setup there. **Do not paste raw session transcripts into the issue.** Issues on this repository are public and stay public. Say in the issue that the logs are coming separately; I reply with a private route (the Ko-fi order message thread, or an address you name) and you send them there.
3. You receive the report as an issue reply, and the issue is closed when you confirm it.

**Strip your logs before you send them.** Session transcripts routinely carry API keys, customer names, internal paths and source code. Remove those first. I cannot un-see what arrives, and a public issue cannot be un-published — if a secret does reach me, tell me and rotate it, because deleting the message does not undo the exposure.

**What happens to the files you send:** they stay on my machine for the audit, are not published anywhere, are not used to train anything, and are deleted within 30 days of delivery — sooner if you ask. I keep the report I wrote; I do not keep your logs.

**What the free tools already give you — run them first:** `/cost` (or `/usage`) inside Claude Code shows the current session. [`ccusage`](https://github.com/ccusage/ccusage) gives you daily and monthly totals from the same local logs, and it folds duplicate `usage` rows correctly (keyed on `message.id` + `requestId`) — a detail my own `cc-token-diet` got wrong until 2026-08-09. If your question is *"how much?"*, those answer it for free and you do not need me.

What none of them answer is *"which of my habits is producing that number, and what do I change on Monday."* Counting is solved; attribution is not. That gap is what this audit is for.

**Good fit:** Max plan users watching their quota vanish faster than it used to. Teams where one session burned an unexpected $50–$500. Anyone who read a "7 tips" article and tried them but nothing changed.

**Not a good fit:** if you have not yet run Claude Code for at least one week on your actual project. There has to be real usage to audit.

**Japanese is welcome / 日本語でも受け付けます:** there is a full Japanese description of this audit — price, turnaround, refund terms, what is not included, and what you send me — at **[トークンが何に消えたかを、あなたのログから読む監査（¥3,980・48時間）](https://yurukusa.github.io/cc-safe-setup/token-burn-audit-jp.html)**. The sample report is also available in Japanese: **[見本の報告書（日本語）](./docs/token-burn-audit-sample-jp.md)** — same content, same figures, same measurement date as the English one. You can place the Ko-fi order and file the request issue in Japanese, and the report comes back in Japanese. この監査の日本語の説明（価格・納期・返金の条件・含まないもの・送っていただくもの）は上のページにあります。見本の報告書も日本語版を用意しました（中身・数字・測定日は英語版と同じ）。注文と issue を日本語で書いていただければ、報告書は日本語でお返しします。

---

## 3. Full-Surface Audit — $219 (¥29,800)

**What it is:** the two audits above each read one kind of file. This one crosses five layers of your setup — `CLAUDE.md`, `settings.json`, your hooks, your session logs, and your CI config — and reports only the contradictions that fall *between* them.

**Why a separate offering rather than a bigger version of the ones above:** because the failures it finds are not larger versions of single-file failures. They are a different kind. A rule that names a safety net which exists but is never registered passes every check you can run on the rule, and every check you can run on the config. It only shows up when the two are read against each other.

**See exactly what you get: [a full sample report](./docs/full-surface-audit-sample-jp.md).** It is this audit run against my own setup — three layers of `CLAUDE.md`, 27 registered hooks, 649 session log files holding 34,026 shell calls, and three CI workflows. On the day I wrote it, it found five things I did not know, and the largest was about this project:

> The guards protecting my machine were a different program from the ones I ship under the same names. Six dangerous command shapes that the shipped version blocks were passing on my own machine. And `--outdated`, the command in this repo whose only job is to notice exactly that drift, was structurally unable to see those files — the core guards live in `scripts.json`, and it compared against `examples/`. I fixed that the same day; the fix is in this repo.

The report also measured how much it mattered, against my own logs rather than in principle. Of 515 recorded calls containing `git push`, **502 (97.5%)** sat outside the position the installed guard was reading — and reading those 502 line by line turned up **two real force-pushes that ran and were never stopped**, on a guard whose own header says it blocks force-push on *all* branches.

It also records the two times my own scan was wrong about that number, in both directions, and how I found out.

**What you get, as a Markdown report within 72 hours:**

1. **Cross-layer contradictions.** Each one names the layers it spans and why a single-file audit cannot surface it.
2. **A control for every finding** — the same probe on a case that should *not* trigger. Without that, "everything passed" and "my probe was wrong" look identical. The sample includes the three cases where my own scan was wrong and I threw the finding out.
3. **Coverage measured against your own logs.** Not "this rule looks weak" but "this rule sits outside N% of the commands you actually ran."
4. **Diffs you can paste**, and the 30-second command that shows each one working.
5. **What the audit did not find**, and what it could not measure.

**Not included:** a call, implementation, or running anything in your environment. I read what you send and write the report. The diffs are proposals; you apply them. If you want a senior human engineer manually reviewing your repo, this is not that.

**How to book:**

1. Order at https://ko-fi.com/yurukusa/commissions — listing: *Full-Surface Audit — all 5 layers, written report within 72h*, ¥29,800 (≈$219).
2. Reply to the order with a message saying which of the five layers you can send. **You do not need all five; three is enough to start.** I reply within 24 hours with a private route for the files.
3. **Do not post logs or settings publicly.** Session transcripts routinely carry API keys, customer names, internal paths and source code. Strip what you can before you send them. I cannot un-see what arrives.

**What happens to the files you send:** they stay on my machine for the audit, are not published anywhere, are not used to train anything, and are deleted within 30 days of delivery — sooner if you ask. I keep the report I wrote; I do not keep your files.

**Refund:** if the audit surfaces no cross-layer contradiction at all, full refund via Ko-fi.

**Japanese is welcome / 日本語でも受け付けます:** there is a full Japanese description of this audit — price, turnaround, refund terms, what is not included, and what you send me — at **[層と層のあいだにしか現れない矛盾を読む監査（¥29,800・72時間）](https://yurukusa.github.io/cc-safe-setup/full-surface-audit-jp.html)**. The sample report linked above is already the Japanese one. 注文と依頼を日本語で書いていただければ、報告書は日本語でお返しします。この監査の日本語の説明（価格・納期・返金の条件・含まないもの・送っていただくもの）は上のページにあります。

---

## 4. CC Safety Lab — Founder Membership, ¥500/month

Monthly recurring. Each issue covers:

- 3–5 new incident reports from the prior month, each with a concrete workaround.
- 1 new safety hook, released to Founder members one month before it ships to `cc-safe-setup` main.
- 1 measured token-saving technique, with the data behind it.
- 1 week of early access to Token Book updates.

**The delivery record, since I would rather you saw it than found it.** This page used to say
"delivered on the 1st of each month." It has never worked out that way, so the claim is gone.
Issues went out on 2026-04-23, 04-24, 05-08, 05-15, 05-22 — and then **nothing until 08-08**.
June and July have no issue at all; I found the August one sitting unpublished as a draft and
shipped it late. No issue has ever gone out on the 1st.

What I will commit to instead: **one issue per calendar month, no fixed date.** If a month is
missed, the next issue says so at the top rather than quietly skipping it. If that is not good
enough for ¥500/month — and it may well not be — do not join yet.

Founder rate is grandfathered — you keep the ¥500 price even if the tier is later raised.

**Join:** https://ko-fi.com/yurukusa → *Membership* tab.

---

## Why these prices

Comparable AI-audit consulting, in the listings I have seen, runs $150–$300/hour and $999+ per productized report. These are deliberately priced below that because they are AI-assisted: I apply the same 7-check framework documented in the [free self-audit Gist](https://gist.github.com/yurukusa/df29f506af33368b03b1c5aeae85f04c), plus judgment from having read hundreds of public Claude Code incident reports. If you want a senior human engineer manually reviewing your repo, this is not that. Read the sample and decide.

**On the gap between $29 and $219:** it is not a bigger version of the same work. The $29 audits read one kind of file each, and a single-file audit cannot produce a contradiction that lives *between* files — the gap is in what the work can find, not in how much of it there is. The sample report for each tier shows the difference; read both before deciding which one you want. If the $29 audits answer your question, buy those.

---

## Questions before booking

Open a [General Discussion](https://github.com/yurukusa/cc-safe-setup/discussions/categories/general) or message on Ko-fi.
