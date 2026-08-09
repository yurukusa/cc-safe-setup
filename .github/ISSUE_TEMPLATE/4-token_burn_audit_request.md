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

## Ko-fi payment reference

<!-- Paste the Ko-fi transaction ID or date/time of your order.
     Order here: https://ko-fi.com/yurukusa/commissions
     ("Token Burn Audit — written report within 48h", ¥3,980 / ≈$29)
     If that listing is ever missing, a ¥3,980 tip with the note
     "Token Burn audit" is honored at the same price.
     Not sure yet? The full sample report is public — read it first:
     https://github.com/yurukusa/cc-safe-setup/blob/main/docs/token-burn-audit-sample.md -->



## What I will analyze

- [ ] 7 days of your `/cost` output
- [ ] 2–3 session transcripts (redacted as you wish) — this is what SERVICES.md asks for; more is welcome but not required
- [ ] Your current `CLAUDE.md` (for cross-reference — not a separate audit)
- [ ] Output of `npx github:yurukusa/cc-token-diet` run on your logs (I can walk you through this if needed)

The deliverable: top 3 waste patterns in your actual usage, with concrete fixes per pattern. Patterns drawn from the Token Book Ch.8 symptom catalog (56 symptoms as of 2026-04-24).

## Your /cost output

<!-- Run `/cost` at the end of 5-10 sessions over a week and paste the output below.
     Strip anything sensitive. -->

```
<paste here>
```

## Sample session transcripts (optional)

<!-- Paste or attach 2-3 session transcripts where you noticed unexpected token burn.
     ~/.claude/transcripts/ contains these (JSONL). Redact content as you prefer. -->

## Your CLAUDE.md (for context, not audit)

<!-- Helps me rule in/out CLAUDE.md-driven waste. Not audited against CLAUDE.md Audit rubric here. -->

```markdown
<paste here>
```

## cc-token-diet output (optional but speeds things up)

<!-- Run: `npx github:yurukusa/cc-token-diet --json > diet-output.json`
     Paste the JSON below. If you hit errors, paste the error and I'll work around it. -->

```json
<paste here, or leave empty>
```

## Specific burn events you want investigated

<!-- e.g. "my Max quota died in 90 min on Tue" / "subagent loop at 3pm burned $40" / "cache hit rate dropped after /clear" -->



## Turnaround

You'll receive the audit as a reply here within 48 hours. If it takes longer I'll post a delay note with a reason.
