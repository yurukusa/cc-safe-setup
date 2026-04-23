# Services

If you want more than what the free tools give you, there are two paid options. Both are fulfilled using the same methodology I use to run Claude Code autonomously (800+ hours logged), applied to your specific setup.

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

## 2. CC Safety Lab — Founder Membership, ¥500/month

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
