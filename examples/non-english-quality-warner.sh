#!/bin/bash
# non-english-quality-warner.sh — Surface the Cluster 15 non-English output quality regression
# at session start for operators working in non-English languages with Opus 4.7
#
# Background:
#   Starting with Claude Code 2.1.126 (early May 2026), Opus 4.7's non-English outputs
#   began exhibiting register-inappropriate vocabulary at significantly elevated rates.
#   The strongest quantitative evidence comes from issue #62961 (2026-05-28): a Kiwi
#   morpheme-level analysis of 114.9M Korean output tokens across 4,666 sessions over
#   ~2 months (Mar 21 – May 25, 2026) shows:
#
#     Period (Korean verb 박다 frequency per 10K tokens)
#       Baseline (Mar 21 – May 2, Opus 4.6 → 4.7)     : 0.0174  (1.0×)
#       After 2.1.126 (May 3–7,  Opus 4.7)            : 0.1147  (6.6×)
#       After 2.1.132 (May 8–17, Opus 4.7)            : 0.3138  (18.0×)
#       After 2.1.143 (May 18–25, Opus 4.7)           : 0.3106  (17.9×)
#
#   The verb "박다" (bakda) is colloquial/slang ("to hammer/nail in") — register-
#   inappropriate for professional documents. It is being used where formal verbs
#   like "명시하다" (to specify), "기록하다" (to record), or "삽입하다" (to insert)
#   would be expected. The 6.6× → 18.0× jump at 2.1.132 strongly correlates with
#   Claude Code CLI updates, not the model transition (Opus 4.6 → 4.7 happened
#   April 16, well before the spike).
#
#   The pattern is not limited to Korean. Independent operator reports surface:
#     - Japanese register collapse (2-4× signal)
#     - Mixed Chinese-English code-switching at unexpected rates
#     - Polish/Spanish formality drift (smaller signal, harder to quantify)
#
#   This is a server-side quality regression. There is no client-side fix that
#   restores baseline register quality. The hook exists to surface the situation
#   to operators who would otherwise notice the degradation only after shipping
#   documents that used slang verbs in formal contexts.
#
#   References:
#     - https://github.com/anthropics/claude-code/issues/62961  (Korean evidence)
#     - https://gist.github.com/yurukusa/9b882f7009d36ad5477c46f890272acc  (field guide)
#
# What this hook does:
#   On SessionStart, when CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 is set, emits a
#   stderr advisory naming the three operator-side workarounds for non-English
#   register-quality work during the Cluster 15 window. The hook is fully opt-in —
#   silent by default. The advisory does not assume the operator's language; it
#   describes the situation and lets the operator decide if it applies.
#
# When this hook does NOT emit anything:
#   - CC_NON_ENGLISH_QUALITY_WARNER_REMIND is unset or empty
#   - CC_NON_ENGLISH_QUALITY_WARNER_DISABLE=1
#   - CC_NON_ENGLISH_QUALITY_WARNER_QUIET=1
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/non-english-quality-warner.sh" }]
#     }]
#   }
# }
# And in your shell rc, opt in:
#   export CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1
#
# Env vars:
#   CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1   — opt-in trigger (required to emit)
#   CC_NON_ENGLISH_QUALITY_WARNER_DISABLE=1  — never emit (overrides REMIND)
#   CC_NON_ENGLISH_QUALITY_WARNER_QUIET=1    — silent (overrides REMIND)
#
# Design notes:
#   - Opt-in by default. The advisory is only useful to operators producing non-
#     English output. Defaulting silent avoids noise for the English-language
#     operator majority.
#   - Language-agnostic advisory. The hook does not try to auto-detect the
#     operator's language. Auto-detection from CLAUDE.md or env vars would be
#     unreliable (a Japanese operator may have an English CLAUDE.md), and a wrong
#     guess is worse than no guess.
#   - Never blocks. Exit always 0.
#   - No version gating. The Cluster 15 window started at 2.1.126 and is ongoing
#     as of 2026-05-30. Gating on version would risk silencing the advisory after
#     Anthropic patches the regression (the operator would no longer hear the
#     advisory, but the patch's effectiveness is something they need to verify).
#     The advisory text describes the situation and the verification path; the
#     operator can disable it once they have verified that their workflow is
#     unaffected.

set -u

# Hard disable path
if [ "${CC_NON_ENGLISH_QUALITY_WARNER_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Quiet path
if [ "${CC_NON_ENGLISH_QUALITY_WARNER_QUIET:-0}" = "1" ]; then
  exit 0
fi

# Opt-in gate
if [ "${CC_NON_ENGLISH_QUALITY_WARNER_REMIND:-0}" != "1" ]; then
  exit 0
fi

cat >&2 <<'EOF'
[non-english-quality-warner] Cluster 15 advisory: non-English output register
quality has regressed in Opus 4.7 since Claude Code 2.1.126 (early May 2026).

Strongest quantitative signal (issue #62961, Korean morpheme analysis):
  Baseline (pre-2.1.126)  : 1.0×  baseline slang verb frequency
  After 2.1.126            : 6.6×  slang verb frequency
  After 2.1.132 and later  : 18.0× slang verb frequency

The pattern: formal/professional-register verbs are being replaced by colloquial
or slang alternatives in contexts where the colloquial form would not appear in
a professional document. The defect is server-side and Opus-4.7-specific; there
is no client-side patch that restores the baseline register.

If you produce non-English output for any document that requires professional
register (reports, customer-facing content, technical docs in your language),
three operator-side workarounds reduce the exposure:

  1) Pin formal register in your system prompt or CLAUDE.md.
     Add an explicit rule naming the registers you want and the registers you do
     not. Example (Japanese):
       "出力は formal register に固定。 colloquial / slang の語彙の混入を避ける。
        書き言葉の規律で、 報告書に出せる調子で書く。"
     For Korean, name the slang verbs you have already observed and exclude them:
       "박다, 박히다 등의 비격식체 동사 사용 금지。 명시하다, 기록하다,
        삽입하다 등의 격식체 동사를 사용。"

  2) Switch to Sonnet for register-sensitive output.
     Sonnet 4.6 and 4.7 are not affected by the Cluster 15 regression in the
     same way (independent reports — please verify on your own workload before
     trusting this for production output). For the specific turns that produce
     register-sensitive text, swap with:
       export ANTHROPIC_MODEL=claude-sonnet-4-7
     Switch back to Opus for non-register-sensitive work (planning, reasoning).

  3) Post-process the output for known slang substitutions.
     For high-volume non-English production, maintain a sed/awk substitution
     list of the slang verbs your style guide rejects, applied to the model's
     output before shipping. This is a stop-gap, not a fix, and it does not
     catch register problems your list does not anticipate — but for known
     repeat offenders it works.

This advisory will continue to surface until you disable it. To turn it off
once you have either chosen a workaround or verified Anthropic has patched the
regression for your workflow:
  unset CC_NON_ENGLISH_QUALITY_WARNER_REMIND
  # or
  export CC_NON_ENGLISH_QUALITY_WARNER_QUIET=1

References:
  https://github.com/anthropics/claude-code/issues/62961  (Korean evidence)
  https://gist.github.com/yurukusa/9b882f7009d36ad5477c46f890272acc  (field guide)
EOF

exit 0
