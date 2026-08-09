# Services

If you want more than what the free tools give you, there are three paid options. All are fulfilled using the same methodology I use to run Claude Code autonomously, applied to your specific setup.

This page is in English, but Japanese orders are welcome for all three: order and write your request in Japanese and the report comes back in Japanese. 日本語でも受け付けます（注文と依頼を日本語で書いていただければ、報告書は日本語でお返しします）。

---

## 1. CLAUDE.md Audit — $29 (¥3,980)

**What you get:**

A written audit of your `CLAUDE.md` (and optionally `settings.json` + your 5 most-invoked hooks), delivered as a Markdown report within 48 hours.

**See exactly what you get: [a full sample report](./docs/claude-md-audit-sample.md).** It is this audit run against my own 608-line, three-layer setup — real findings, including two rules that could not be followed at all.

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
2. Open an Audit Request issue on this repo using [the template](./.github/ISSUE_TEMPLATE/3-audit_request.md). Paste your CLAUDE.md there (or attach, if you prefer not to make it public). Mention your Ko-fi order so the two can be matched.
3. You receive the report as an issue reply, and the issue is closed when you confirm it.

If you cannot post anything publicly, say so in the Ko-fi order message and I'll arrange another route.

**Refund:** if I cannot produce a useful audit (for example because the file is effectively empty, or is entirely in a language I cannot parse), full refund via Ko-fi.

---

## 2. Token Burn Audit — $29 (¥3,980)

**What it is:** a diagnosis of where your Claude Code tokens are actually going, based on *your* `/cost` output and session transcripts. Not a generic "7 tips" article — a specific read of your real usage.

**Why this exists now (April 2026 context):**

> *"I used up Max 5 in 1 hour of working, before I could work 8 hours"* — user report via [DevOps.com, April 2026](https://devops.com/claude-code-quota-limits-usage-problems/)

- Since March 23, 2026: Max plan users reporting 5-hour windows draining in as little as 19 minutes ([#38335](https://github.com/anthropics/claude-code/issues/38335), [#41788](https://github.com/anthropics/claude-code/issues/41788))
- Anthropic confirmed investigation: "top priority for the team" — but the fix window is unclear
- Root cause partially identified: `cache_read` tokens may count at full rate against rate limits (negating caching benefits)
- April 21 pricing whiplash: Claude Code removed from $20 Pro plan, reverted hours later — every hour on $100 Max matters more now

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
2. Open a Token Burn Audit Request issue on this repo using [the template](./.github/ISSUE_TEMPLATE/4-token_burn_audit_request.md). Paste 7 days of `/cost` output, 2–3 session transcripts (redact as you wish), and your current `CLAUDE.md`.
3. You receive the report as an issue reply, and the issue is closed when you confirm it.

**What the free tools already give you — run them first:** `/cost` (or `/usage`) inside Claude Code shows the current session. [`ccusage`](https://github.com/ccusage/ccusage) gives you daily and monthly totals from the same local logs, and it folds duplicate `usage` rows correctly (keyed on `message.id` + `requestId`) — a detail my own `cc-token-diet` got wrong until 2026-08-09. If your question is *"how much?"*, those answer it for free and you do not need me.

What none of them answer is *"which of my habits is producing that number, and what do I change on Monday."* Counting is solved; attribution is not. That gap is what this audit is for.

**Good fit:** Max plan users watching their quota vanish faster than it used to. Teams where one session burned an unexpected $50–$500. Anyone who read a "7 tips" article and tried them but nothing changed.

**Not a good fit:** if you have not yet run Claude Code for at least one week on your actual project. There has to be real usage to audit.

**Japanese is welcome / 日本語でも受け付けます:** this page and the sample report are in English, but you can place the Ko-fi order and file the request issue in Japanese, and the report comes back in Japanese. 説明のページも見本も英語ですが、注文と issue を日本語で書いていただければ、報告書は日本語でお返しします。

---

## 3. CC Safety Lab — Founder Membership, ¥500/month

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

Comparable AI-audit consulting, in the listings I have seen, runs $150–$300/hour and $999+ per productized report. This offering is deliberately priced far below that because it is AI-assisted: I apply the same 7-check framework documented in the [free self-audit Gist](https://gist.github.com/yurukusa/df29f506af33368b03b1c5aeae85f04c), plus judgment from having read hundreds of public Claude Code incident reports. If you want a senior human engineer manually reviewing your repo, this is not that. Read the sample and decide.

---

## Questions before booking

Open a [General Discussion](https://github.com/yurukusa/cc-safe-setup/discussions/categories/general) or message on Ko-fi.
