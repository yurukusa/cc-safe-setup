# Sample: CLAUDE.md Audit

This is a real report. Only sensitive lines were withheld — everything shown is unedited.
It is the deliverable of the
[$29 CLAUDE.md Audit](https://github.com/yurukusa/cc-safe-setup/blob/main/SERVICES.md#1-claudemd-audit--29-3980).

The subject is my own instruction set: three layers (global, home, project), 608 lines,
written in Japanese, driving an autonomous Claude Code session. It got the same checks a
customer's files get.

Counts and ratios below cover every line. Quotations are limited to non-sensitive lines, so
some findings are reported as numbers with no example attached.

---

## 0. Headline

**One rule in this setup cannot be followed, and nothing reports it.** A directive says
"see memory `cdp-ports.md` for port and profile assignment." That file exists — in a
*different project's* memory scope. From the project where the rule applies, it is
unreachable by name and absent from the index. It is unfollowable today; I did not try to
establish when it broke.

A second reference fails the same way, and my own automated pass missed it. See §3a — that
miss is itself a finding.

Secondary: 83% of directives here are not mechanically checkable, and 24 rules are duplicated
across layers.

**What this audit did *not* find: meaningful token cost.** See §1.

---

## 1. Token weight

| File | Bytes | Chars | Lines | Est. tokens |
|---|---|---|---|---|
| Global (`~/.claude/CLAUDE.md`) | 6,241 | 2,467 | 80 | 2,032 |
| Home (`~/CLAUDE.md`) | 9,143 | 3,871 | 144 | 2,935 |
| Project | 30,125 | 12,701 | 384 | 9,677 |
| **Total** | **45,509** | **19,039** | **608** | **14,644** |

Estimation rule, stated so you can reproduce it: one token per character in
U+3000–30FF, U+3400–4DBF, U+4E00–9FFF, U+F900–FAFF and U+FF00–FFEF; every remaining
character counted as `ceil(n / 4)`. This is an approximation, not a measurement. **Your
exact figure is one command away — run `/context` in your own session.**

### What the redundancy actually costs you

The 24 cross-layer duplicates (§3b) come to 794 tokens per turn, 5.4% of the total:

| Assumption | 200 turns/mo | 1,000 turns/mo |
|---|---|---|
| Uncached input @ $15/Mtok | $2.38 | $11.91 |
| Cache read @ $1.50/Mtok | $0.24 | $1.19 |

`CLAUDE.md` sits in the cached prefix, so the bottom row is the one that reaches your bill.

**Deleting every duplicated rule in this setup saves roughly $0.24–$1.19 a month.**

If your setup is larger the arithmetic scales, but the shape does not change while the block
stays cached. Fix duplication because it creates ambiguity about which layer owns a rule —
not because it costs money. If your bill is the problem, it is in your session logs, not
your instruction files.

---

## 2. Vague-rule detection

Of 128 directive lines, 106 lack a checkable anchor (§4). **These 8 are the subset where no
anchor could attach at all** — the rule names a state that is never observable from inside
the session.

| Line | Directive (translated) | Why it drops out |
|---|---|---|
| global:40 | "Throw compute at hard problems without holding back" | "hard" and "without holding back" have no threshold. Under pressure this reads as permission, not obligation. |
| global:56 | "Within that constraint, if it feels ad hoc, choose the beautiful solution given what you now know. Do not apply this to simple, obvious fixes." | The limiting clause is real and helps. The trigger does not: "feels ad hoc" is a self-report, and a model under pressure never files one. |
| global:78 | "Prefer simplicity: as simple as possible, minimum code." | No comparison target. Every implementation satisfies this against itself. |
| home:87 | "You may consult, but do not halt while waiting for a reply. You make the final call." | The prohibited state ("halted") is exactly the state in which nothing is running to notice it. |

These are not bad instincts. They are correct intentions with nothing to attach to.
§5 attaches them.

---

## 3. Redundancy and stale references

### 3a. Stale references

Extraction rule: every backtick-quoted string containing no spaces and either containing a
slash or ending in a known extension (`.md .sh .json .yaml .yml .jsonl .py .txt`). Each was
resolved against ten plausible base paths.

**56 checked. 50 resolve. 6 do not.** Of those 6:

| Unresolved | Verdict |
|---|---|
| `/sol` (×2), `/post-article` | Slash commands, not paths. Not defects. |
| `~/ops/proof-log/YYYY-MM-DD.md` | A filename template. Not a defect. |
| `project/docs/` | A generic noun inside a directory-convention section. Not a defect. |
| `cdp-ports.md` | **Real defect.** Resolves only under `~/.claude/projects/-home-namakusa/memory/`. The project this rule governs uses a different memory scope, where the file is absent and the index returns zero hits. |

This is the failure worth studying, because of *how* it hides:

- It is not a missing file, so any "does this path exist?" check passes.
- It is not a typo, so reading the line carefully does not reveal it.
- It surfaces only if you resolve references **against the scope the rule runs in**, and then
  notice the hit came from somewhere else.

### The one my own scanner missed

`~/CLAUDE.md:69` says "games follow `GAME_QUALITY_FRAMEWORK`." That file lives at
`~/projects/spell-cascade/GAME_QUALITY_FRAMEWORK.md` and **no layer gives the path** — the
same failure as `cdp-ports.md`.

My extraction rule above did not catch it: no slash, no extension, so it never entered the
56. The contrast that proves the point is `WRITING_STYLE.md`, also written bare at
`~/CLAUDE.md:64` — but the project layer spells out `~/projects/dung-azure-flame/WRITING_STYLE.md`,
so that one is recoverable and is *not* a defect.

**Bare names are the risk, and no extraction rule catches all of them.** A human pass over
every backtick is the only thing that closes this class. That pass is what you are buying.

### 3b. Cross-layer duplication

24 rules appear in more than one layer. Checking all 24 by exact string, then again after
normalizing bullet markers, spaces and trailing punctuation: **2 are byte-identical, 1 more
is identical after normalization, and the remaining 21 overlap only partially.**

| Match | Layer A | Layer B |
|---|---|---|
| byte-identical | global:8 | project:60 |
| byte-identical | global:11 | project:64 |
| identical after normalization | global:16 — "Only technical proper nouns, filenames, command names, product names and API names may stay in English." | project:143 — same sentence as a bullet: no trailing period, no space in "API名" |
| **partial only** | global:17 — "Otherwise explain it in Japanese, and do not compress meaning just to be shorter." | project:145 — the second clause only, as a bullet |

The last row is the interesting one, and it is why "how many are duplicated" is the wrong
question to stop at. The project layer carries *half* the global rule. Read alone it means
something narrower than the original — the "explain it in Japanese" half is simply gone. That
is what layer drift looks like before it becomes a contradiction, and a similarity score
alone will not tell you which of the 21 partial overlaps are harmless restatements and which
are silent narrowings. That separation is done by reading.

Duplication is not a cost problem (§1). It is an **ownership** problem: with the same rule in
two layers, editing one leaves the other in force, and neither file says the other exists.

---

## 4. Testable-assertion ratio

| Layer | Directive lines | With a checkable anchor | Ratio |
|---|---|---|---|
| Global | 23 | 4 | 17% |
| Home | 35 | 6 | 17% |
| Project | 70 | 12 | 17% |
| **Total** | **128** | **22** | **17%** |

"Checkable anchor" = a command, path, numeric threshold, hook name, exit code, or protocol
reference — something a hook or a reviewer could evaluate.

**106 of 128 directives cannot be mechanically checked.**

Each layer landing on 17% is chance; I would not read anything into it.

**What this does not prove:** this is a proxy. "No anchor" correlates with "quietly dropped
under pressure" in my own logs. This audit does not establish causation for your setup, and
I will not claim it does.

---

## 5. Top 3 fixes, ranked, with diffs ready to paste

### Fix 1 — Make the unfollowable rules followable (highest impact)

These rules cannot be obeyed today. Everything else in this report is degradation; this is a
hard failure.

```diff
  # home CLAUDE.md (~/CLAUDE.md:134)
- ・ポートとプロファイルの割り当てはメモリ `cdp-ports.md` を参照する
+ ・ポートとプロファイルの割り当ては
+   `~/.claude/projects/-home-namakusa/memory/cdp-ports.md` を参照する
+   （★このプロジェクトのmemoryスコープには無いので、名前だけでは辿れない）
```

```diff
  # home CLAUDE.md (~/CLAUDE.md:69)
- ・ゲームは `GAME_QUALITY_FRAMEWORK` に従う
+ ・ゲームは `~/projects/spell-cascade/GAME_QUALITY_FRAMEWORK.md` に従う
```

Generalized: **any reference a rule depends on must be written so it resolves from the scope
the rule runs in.** A bare filename is safe only when the file is in the current scope, and
you cannot tell by looking.

### Fix 2 — Give one layer ownership of each duplicated rule

```diff
  # project CLAUDE.md
- - 技術固有名詞、ファイル名、コマンド名、製品名、API名だけは英語のままでよい
- - 短くするために意味を圧縮しない
+ （文体の規則はグローバル指示書が正本。ここでは繰り返さない）
```

Delete the copy in the *more specific* layer when the rule is genuinely global. Keep a local
copy only to **override**, and when you do, say so ("this replaces the global rule") so the
next edit knows a second copy exists.

This applies to all 24 pairs. The two byte-identical ones need no case-by-case judgment; the
other 22 do, and the pair at global:17 / project:145 shows why — the local copy had already
drifted to a narrower meaning.

### Fix 3 — Attach one anchor to each vague directive

Do not rewrite the intent. Add the condition that makes it observable.

```diff
  # global CLAUDE.md (~/.claude/CLAUDE.md:40)
- - 複雑な問題には、計算リソースを惜しまず投入しろ
+ - 3ファイル以上にまたがる調査、または同じ失敗を2回踏んだ時は、
+   自分で続けずサブエージェントか別の観測手段へ切り替えろ
```

```diff
  # home CLAUDE.md (~/CLAUDE.md:87)
- ・相談はしてよいが、返答待ちで停止しない。最終判断は自分で行う
+ ・相談はしてよい。ただし相談を投げた同じ応答の中で、
+   返答に依存しない作業を1つ着手すること。最終判断は自分で行う
```

The rewrites are longer. That is the trade: a checkable rule costs tokens and survives
pressure; an aspirational rule is cheap and evaporates. §1 shows the token side is nearly
free, so the trade is one-sided.

---

## What this audit deliberately does not do

- **It does not apply the fixes.** The diffs are proposals. Implementation is not included —
  see [SERVICES.md](https://github.com/yurukusa/cc-safe-setup/blob/main/SERVICES.md).
- **It does not claim your model ignored a specific rule.** That needs your session logs,
  which is a different product.
- **It does not present estimates as measurements.** Where I estimated (§1) I said so and
  gave the rule.

---

## How this report was produced

The first automated pass reported **17 broken references**. The second reported **5**. After
checking each one against the filesystem, **1** survived — and a **second** real one turned
out to be sitting outside what the scanner looked at (§3a).

- Pass 1 counted slash commands, shell command lines and date placeholders as paths.
- Pass 2 had a base-path bug: for references written `memory/foo.md` it searched
  `memory/memory/foo.md`, and was about to report **three files that exist** as missing.
- Listing the directories directly settled it.

In this run, the unverified pass would have shipped sixteen false positives for one real
finding, and still missed one. Every finding above was confirmed by hand before it was
written down. The scanning is the cheap half.

---

## If you want this run against your own setup

Price, turnaround, refund terms and what you send me are all in
[SERVICES.md §1](https://github.com/yurukusa/cc-safe-setup/blob/main/SERVICES.md#1-claudemd-audit--29-3980):
**$29 (¥3,980), written report within 48 hours, full refund if I cannot produce a useful audit.**
Order at [Ko-fi](https://ko-fi.com/yurukusa/commissions) — listing *CLAUDE.md Audit — written report
within 48h*. Japanese is welcome; the report comes back in Japanese if you write in Japanese, and
there is a [Japanese version of this sample](https://github.com/yurukusa/cc-safe-setup/blob/main/docs/claude-md-audit-sample-jp.md).

**Do not paste `CLAUDE.md` or settings into a public place if they should stay private.** Issues on
this repository are public, and attaching a file does not make it private — attachment URLs can be
opened by anyone with the link. Say so in the Ko-fi order message and I reply with a private route.

The honest limit: this audit saves roughly $0.24–$1.19 a month in tokens (`CLAUDE.md` is cached).
What it is worth is not the tokens. It is the rules that were never followed.

---

*Questions:* [General Discussion](https://github.com/yurukusa/cc-safe-setup/discussions/categories/general).
*The hooks in this repository are free (MIT) and always will be.*
