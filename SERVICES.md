# Services

If you want more than what the free tools give you, there are three paid options. All are fulfilled using the same methodology I use to run Claude Code autonomously (800+ hours logged), applied to your specific setup.

---

## 1. CLAUDE.md Audit — $29 (¥3,980)

**What you get:**

A written audit of your `CLAUDE.md` (and optionally `settings.json` + your 5 most-invoked hooks), delivered as a Markdown report within 48 hours.

The report covers:

1. Token weight analysis — how much your instructions cost per turn, vs. a tuned baseline.
2. Vague-rule detection — the specific lines the model is most likely to ignore, with concrete rewrites.
3. Redundancy and stale-reference scan — rules that contradict, duplicate, or point at paths that no longer exist.
4. Testable-assertion ratio — how much of your CLAUDE.md is aspirational (and therefore silently drops out under pressure) vs. checkable.
5. Top-3 fixes, ranked by expected impact, with before/after diffs ready to paste.

**Not included:** a live 1:1 call, hook implementation, or code review beyond the files you submit. This is an audit, not consulting.

**How to book:**

1. Pay $29 via Ko-fi Shop → https://ko-fi.com/yurukusa/shop (item: *CLAUDE.md Audit*). _If the item is not yet listed, use a $29 tip with the note "CLAUDE.md audit" and it will be honored._
2. Open an Audit Request issue on this repo using [the template](./.github/ISSUE_TEMPLATE/audit_request.md). Paste your CLAUDE.md there (or attach, if you prefer not to make it public).
3. You receive the report as an issue reply, and the issue is closed when you confirm it.

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

This audit tells you which of the 48 cataloged token-waste symptoms (Token Book Ch.8) are actually firing in *your* logs — not "in general."

**What you get (delivered in 48 hours as a Markdown report in your issue thread):**

1. **Top 3 waste patterns** found in your logs, ranked by estimated cost. Each tied to a specific Ch.8 symptom number.
2. **Per-pattern fix**: the exact hook, CLAUDE.md change, or workflow adjustment that addresses it. Example hooks from `cc-safe-setup/examples/` that you can install in one command.
3. **Estimated savings range** (stated as a range, not a single number — the actual savings depend on your next month's usage pattern).
4. **`cc-token-diet` walkthrough**: if you haven't run [cc-token-diet](https://github.com/yurukusa/cc-token-diet) yet, I include the command line and help interpret the output.

**Not included:** real-time monitoring, implementation (you apply the fixes yourself), or a guarantee that your $ spend will drop by a specific amount. If the report does not identify at least one addressable waste pattern, full refund via Ko-fi.

**How to book:**

1. Pay $29 via Ko-fi Shop → https://ko-fi.com/yurukusa/shop (item: *Token Burn Audit*). _If the item is not yet listed, use a $29 tip with the note "Token Burn audit" and it will be honored._
2. Open a Token Burn Audit Request issue on this repo using [the template](./.github/ISSUE_TEMPLATE/token_burn_audit_request.md). Paste 7 days of `/cost` output, 2–3 session transcripts (redact as you wish), and your current `CLAUDE.md`.
3. You receive the report as an issue reply, and the issue is closed when you confirm it.

**Good fit:** Max plan users watching their quota vanish faster than it used to. Teams where one session burned an unexpected $50–$500. Anyone who read a "7 tips" article and tried them but nothing changed.

**Not a good fit:** if you have not yet run Claude Code for at least one week on your actual project. There has to be real usage to audit.

---

## 3. CC Safety Lab — Founder Membership, ¥500/month

Monthly recurring, delivered on the 1st of each month. Covers:

- 3–5 new incident reports from the prior month, each with a concrete workaround.
- 1 new safety hook, released to Founder members one month before it ships to `cc-safe-setup` main.
- 1 measured token-saving technique, with the data behind it.
- 1 week of early access to Token Book updates.

Founder rate is grandfathered — you keep the ¥500 price even if the tier is later raised.

**Join:** https://ko-fi.com/yurukusa → *Membership* tab.

---

## Why these prices

Comparable AI-audit consulting runs $150–$300/hour and $999+ per productized report, based on Q1 2026 market data. This offering is deliberately priced at the bottom of that range because it is AI-assisted: I apply the same 7-check framework documented in the [free self-audit Gist](https://gist.github.com/yurukusa/df29f506af33368b03b1c5aeae85f04c), plus judgment from having read hundreds of public Claude Code incident reports. If you want a senior human engineer manually reviewing your repo, this is not that — but it is an honest $29 of value.

---

## Questions before booking

Open a [General Discussion](https://github.com/yurukusa/cc-safe-setup/discussions/categories/general) or message on Ko-fi.
