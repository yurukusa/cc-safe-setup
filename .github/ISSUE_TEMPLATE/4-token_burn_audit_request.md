---
name: Token Burn Audit Request (paid)
about: Request a written audit of your Claude Code token consumption patterns — see SERVICES.md for pricing
title: "[Token Burn Audit] <short description>"
labels: token-burn-audit
assignees: yurukusa
---

<!-- This template is for people who have booked the paid Token Burn Audit.
     See SERVICES.md for how to pay first. The audit itself is produced
     here in the issue thread. -->

> **この issue は公開です。セッションの記録そのものをここに貼らないでください。**
> ここに書いていただくのは `/cost` の出力と、お使いの構成についての2〜3行だけです。
> 「ログは別便で送ります」と1行添えていただければ、こちらから非公開の受け渡し先をお返しします。
>
> **日本語で書いていただいて大丈夫です。報告書も日本語でお返しします。**
> 見出しは英語ですが、中身は日本語で構いません。日本語の説明は
> [こちら](https://yurukusa.github.io/cc-safe-setup/token-burn-audit-jp.html)。
>
> *This issue is public and stays public. **Do not paste raw session transcripts here** —
> post only the `/cost` summary and a couple of lines about your setup, and say that the
> logs are coming separately. I will reply with a private route.
> Japanese is welcome — headings are in English, but you can write the contents
> in Japanese and the report will come back in Japanese.*

## Ko-fi payment reference

<!-- Paste the Ko-fi transaction ID or date/time of your order.
     Order here: https://ko-fi.com/yurukusa/commissions
     ("Token Burn Audit — written report within 48h", ¥3,980 / ≈$29)
     If that listing is ever missing, a ¥3,980 tip with the note
     "Token Burn audit" is honored at the same price.
     Not sure yet? The full sample report is public — read it first:
     https://github.com/yurukusa/cc-safe-setup/blob/main/docs/token-burn-audit-sample.md -->



## What I will analyze

**Two places, not one. This issue is public and stays public.**

Post here:

- [ ] 7 days of your `/cost` output (the summary it prints — not raw logs)
- [ ] Two or three lines about your setup (plan, main use, when the burn hurt)

Send through the private route (I reply here with it once you say the logs are coming):

- [ ] 2–3 session transcripts (redacted as you wish) — this is what SERVICES.md asks for; more is welcome but not required
- [ ] Your current `CLAUDE.md` (for cross-reference — not a separate audit)
- [ ] Output of `npx github:yurukusa/cc-token-diet` run on your logs (I can walk you through this if needed)

**Do not paste raw session transcripts into this issue.** They routinely carry API keys, customer
names, internal paths and source code, and a public issue cannot be un-published.

The deliverable: top 3 waste patterns in your actual usage, with concrete fixes per pattern. Patterns drawn from the Token Book Ch.8 symptom catalog (56 symptoms as of 2026-04-24).

## Your /cost output

<!-- Run `/cost` at the end of 5-10 sessions over a week and paste the output below.
     Strip anything sensitive. -->

```
<paste here>
```

## Session transcripts — do NOT paste them here

<!-- Leave this section as-is. Just tick the line below and I will reply with a private route.
     Where to find the files: Claude Code writes one JSONL file per session under
     ~/.claude/projects/<encoded-project-path>/ — one JSON object per line.
       ls -lt ~/.claude/projects/*/*.jsonl | head
     Redact them before you send them. -->

- [ ] My session transcripts are coming separately — please reply with a private route.

## Your CLAUDE.md (for context, not audit)

<!-- Send this through the same private route as the transcripts. It often names internal
     paths, hostnames and customers. Helps me rule in/out CLAUDE.md-driven waste.
     Not audited against the CLAUDE.md Audit rubric here. -->

## cc-token-diet output (optional but speeds things up)

<!-- Run: `npx github:yurukusa/cc-token-diet --json > diet-output.json`
     Send the JSON through the private route too — it embeds file paths from your logs.
     If you hit errors, paste the error message here; error text alone is usually safe. -->

```
<paste the error message here, if any>
```

## Specific burn events you want investigated

<!-- e.g. "my Max quota died in 90 min on Tue" / "subagent loop at 3pm burned $40" / "cache hit rate dropped after /clear" -->



## Turnaround

You'll receive the audit as a reply here within 48 hours. If it takes longer I'll post a delay note with a reason.
