# Sample: Token Burn Audit

This is a real report. It is the deliverable of the
[$29 Token Burn Audit](https://github.com/yurukusa/cc-safe-setup/blob/main/SERVICES.md#2-token-burn-audit--29-3980).

The subject is my own usage: **156 session logs, 21,770 API round-trips**, from an autonomous
Claude Code operation. Same checks a customer's logs get. Nothing here is invented for the sample.

Measured 2026-08-09, 08:00 JST. The session doing the measuring keeps writing to the same directory, so it is excluded
(Ch.33 explains why that matters).

---

## 0. Headline

**The first thing this audit found was my own counting error — a 2.36× overcount.**
Claude Code writes one API response across several JSONL lines (thinking / text / tool_use)
and copies the same `usage` onto each. Summing per line bills one request many times.
Collapsing on `requestId`: 51,484 lines → **21,770 requests**.

After the correction: cache reads are **70.1%** of the estimated bill, and for every
1 token of output, **231** are read back in. Over two thirds of the spend is re-reading.

**The largest waste pattern in these logs is not in the 56-symptom catalog** the Token Book
ships, and **the hooks that were supposed to catch it did not fire**. Both findings came out
of this audit, not out of a checklist.

And the honest counterweight: **the single biggest "fix" people reach for — trimming
`CLAUDE.md` — is capped at about 18% of read cost here.** I would rather tell you the ceiling
than sell you the effort.

---

## 1. Where the tokens actually went

| | Tokens | Est. cost | Share |
|---|---|---|---|
| Input (uncached) | 1,527,528 | $23 | 0.1% |
| Cache **write** | 76,599,034 | $2,298 | 14.6% |
| **Cache read** | **7,384,839,143** | **$11,077** | **70.1%** |
| Output | 31,920,888 | $2,394 | 15.2% |

Unit prices assumed: input $15, cache write $30, cache read $1.50, output $75 per Mtok.
**Your real figures are in `/cost` — I always reconcile against those before quoting money.**

One number worth checking in your own data first: **cache write TTL.** In these logs
`ephemeral_1h_input_tokens` was 76,555,566 and `ephemeral_5m` was **0** — so the 1-hour
(2×) rate applies. If yours is 5-minute-dominant, the shares move to roughly
read 75% / write 8% / output 16%, and the advice below shifts with it.

---

## 2. Top 3 waste patterns, ranked by cost

### Pattern 1 — Cost per turn climbs 2.2× within a session (read volume 4.5×)

Sessions with 50+ round-trips (101 of them), split into deciles by turn order:

| Progress | Input tokens/turn | Cost/turn (all-in) |
|---|---|---|
| 10% | 122,849 | $0.482 |
| **20%** | 182,142 | **$0.452** ← cheapest |
| **100%** | **550,604** | **$1.057** |

**Read volume rises 4.5×. Cost rises 2.19×** — the cheap cache-read rate compresses the
difference. Both numbers matter: the first tells you the context is ballooning, the second
tells you what it costs. The full 10-decile curve and the counting method are in Ch.33 of the
Token Book; what the audit adds is the mapping to symptoms and to your own hooks.

**Ch.8 symptom: none.** I checked all 56. Symptom 3 (`--resume` restores prior context) is
about the *starting point*; symptom 18 (UI under-reports usage) is about *display*. Neither
describes cost that rises simply because every turn re-reads everything.

That absence is the point of this product. A catalog lists what breaks. This is not a break —
it happens on every long session I measured, which is why no symptom captures it.

### Pattern 2 — 231 tokens read for every 1 token written

7.38B read against 31.9M output. **I have not measured how stable this is across sessions**,
so treat 231 as an order of magnitude, not a threshold.

**Ch.8 symptom 1 (prompt cache destruction)** is adjacent but not the same — that is about
the cache being *invalidated*. Here the cache is working fine (99.0% of input side is reads);
there is simply a great deal to re-read.

### Pattern 3 — Read/write ratio spans 14 to 459 across all 101 sessions

Min 14.1, max 458.7. (An earlier draft of this report quoted "9×" from five hand-picked
sessions that were not, in fact, the five write-heaviest. Corrected.)

**Caveat I am obliged to give you:** across all 101 sessions, this ratio correlates strongly
with turn count (Pearson r = 0.903). So most of the spread is explained by *session length*,
not by cache efficiency. I can show you the spread; I cannot yet separate the two causes.
Anyone who sells you this spread as "your cache is that much worse in some sessions" is over-reading it.

**Ch.8 symptom 1** lists what invalidates a cache (`CLAUDE.md` edits, `settings.json` edits,
MCP connect/disconnect, `git status` changes). Which of those drove it here is not separable
from this aggregate.

---

## 3. Per-pattern fix

### For Pattern 1 — and the finding that makes this audit worth running

`cc-safe-setup` ships hooks meant to warn before context balloons. I ran them against the
pattern. **They did not fire.**

| Hook | Measured behaviour before the fix |
|---|---|
| `context-usage-drift-alert` | Counter shared across *all sessions that day*; after crossing 150 it never fired again that day. Second session of a day: **0 warnings in 160 calls** |
| `context-compact-advisor` | 200 calls → **200 counter files, each containing "1"**. Never accumulated |
| `session-duration-guard` | 100 calls → **100 "session start" files**. Never measured any duration |
| `test-coverage-reminder` | 60 calls → 0 output |

Cause: the state filename used `$$`, the *hook script's own PID* — different on every
invocation, so state never persisted. (For the first row the PID key never existed, so a
date-keyed fallback always won — which is why it was shared across sessions rather than absent,
and why `-eq 150` meant it fell silent for the rest of each day.) Fixed in
[PR #972](https://github.com/yurukusa/cc-safe-setup/pull/972) by scoping to `session_id`.
After the fix, the same experiments give 1 counter file and correct warnings.

**If you are running these hooks from a version before 2026-08-09, they are not protecting
you.** Update.

Concrete workflow fix, independent of hooks: **start a fresh session for each logical task,
and put heavy exploration just after the first few turns** — the cheapest decile is the
second, not the first (the first pays to build the cache).

### For Pattern 2

Reduce what each turn carries, not what sits in the preamble. In these logs the preamble
floor is a median of **62,337 tokens per turn** (the first response of each session). Times
21,770 turns, that is 1.36B tokens — **18.4% of all cache reads**. The derivation is in Ch.33.

So trimming `CLAUDE.md`, tool definitions and skill descriptions is *not* pointless — it is
**capped at about a fifth**. The other four fifths are accumulated conversation: files read,
tool results, prior turns. Cut those first if the bill is the problem.

### For Pattern 3

Until length and efficiency can be separated, the defensible action is the same as Pattern 1:
shorter sessions. Avoid mid-session changes that invalidate the cache (Ch.8 symptom 1) when
you can batch them instead.

---

## 4. Estimated savings range

Against the $11,077 of cache-read cost in this dataset (~27 days). Note that removing every
duplicated instruction line is *not* on this list: measured separately, that is worth
$0.24–$1.19/month. It is not where the money is.

| Action | Ceiling |
|---|---|
| Trim the preamble floor by half | ~$1,020 (9%) |
| Hold context growth 30% lower | ~$3,320 (30%) |

**These are ceilings, not forecasts.** Halving session length halves the reading *and* the
work. I quote a range and its upper bound because a single number here would be dishonest.

---

## 5. `cc-token-diet` walkthrough

[cc-token-diet](https://github.com/yurukusa/cc-token-diet) is free and runs locally — nothing
is uploaded. Run it before you buy this audit; if it answers your question, you do not need me.

```sh
npx github:yurukusa/cc-token-diet --days 30
```

On this machine it reported 550 sessions / 87,943 turns / 98.0% cache hit ratio, and flagged
`runaway session(s) (>100 assistant turns)` as the top cost. **Note: that tool had the same
per-line counting bug until 2026-08-09** — I found it while writing this report and fixed it
(its estimate dropped from $62,900 to $27,036 on this machine). Update before trusting it.

Two things to notice, because they are the difference between the tool and the audit:

1. **Its numbers will not match mine, and both are right.** The tool scans
   `~/.claude/projects/*/**.jsonl` — every project, subagent logs included (550 sessions).
   My figures above are one project, parent sessions only (156), collapsed on `requestId`. **Neither is "the" number.
   There is only "measured what, when."**
2. **The tool detects Pattern 1 but does not quantify it** — it says long sessions "bloat
   context exponentially." It does not tell you 4.5× in volume, 2.2× in cost, or that the
   cheapest decile is the second. The audit is the measurement; the tool is the smoke alarm.

**Also worth knowing:** subagent logs live under `<session-id>/subagents/` and a plain
`*.jsonl` glob misses them. Here that was **164 files, 2,008 round-trips once collapsed — 8.4% of turns**.
I got this wrong in my own first pass and had to correct it.

---

## What this audit does not do

- **It does not implement anything.** Fixes are proposals; you apply them.
- **It does not promise a dollar reduction.** Ceilings only, with the method shown.
- **It does not present assumptions as measurements.** Where prices are assumed (§1) I say so
  and reconcile against your `/cost`.
- **It does not claim a cause it cannot separate** — see Pattern 3.

---

## How this report was produced

Three of my own numbers were wrong before this was finished, and all three erred toward
making the finding look bigger:

1. **I summed usage per JSONL line, overcounting every token by 2.36×.** Collapsing on
   `requestId` cut the round-trip count from 51,484 to 21,770. Notably the correction did not
   run one way: the *total* fell, but the read share (64.9→70.1%), the read-per-output ratio
   (183→231) and the in-session cost growth (1.83→2.19×) all rose. None of the five
   qualitative conclusions changed.
2. I wrote "cost rises 4.6×" by applying one unit price to a mix of three that differ 20×.
   Correctly split: **2.19×**.
3. I wrote "all records" while silently dropping 164 subagent logs.
4. I wrote "the first 10% is cheapest" — it is the second decile; the first pays cache
   creation.

Each was caught by re-deriving the number from the raw logs rather than from my own summary.
That re-derivation is what you are buying. The aggregation is the cheap half.

---

*These audits are AI-assisted; see SERVICES.md for what that means.*

*Questions:* [General Discussion](https://github.com/yurukusa/cc-safe-setup/discussions/categories/general).
*The hooks in this repository are free (MIT) and always will be.*
