#!/bin/bash
# aup-false-positive-helper.sh — Surface the AUP false-positive cluster awareness when Opus models are pinned
#
# Background:
#   Starting mid-May 2026 (acceleration peak 2026-05-21 through 2026-05-27), the Anthropic
#   server-side Usage Policy classifier began over-triggering on benign Claude Code prompts.
#   GitHub issue tracker accumulated 25+ open reports in 10 days from independent users:
#     - #60366 (16r): single-word "hi" greeting blocked
#     - #62190 (10r): non-deterministic blocks on greetings, coding, "ok"/"yes"
#     - #61056 (4r), #61638 (3r), #61185 (2r), and 20+ low-reaction reports
#   github-actions[bot] auto-flagged at least three duplicate chains, confirming the
#   shape of the cluster at Anthropic's own intake.
#
#   Independent reports converge on a clear signature:
#     - Affected: Opus 4.7, Opus 4.6, Opus 1M context variants
#     - Unaffected: Sonnet 4.6, Sonnet 4.7
#     - Languages: false positives observed on English, Russian, Polish, and Spanish
#     - Domains: kernel security audits, biomedical research, FPGA waveform analysis,
#       compression algorithm work, and plain greetings — context-independent
#     - Behavior: non-deterministic on identical input (same prompt blocks one minute,
#       passes the next), strongly indicating an unstable classifier rather than the
#       prompt being the cause
#
#   The block surfaces as one of two stock error strings:
#     "API Error: Claude Code is unable to respond to this request, which appears to
#      violate our Usage Policy (...). This request triggered cyber-related safeguards."
#   or:
#     "This request triggered safety guardrails. Rephrase your prompt or rewind to continue."
#
#   This is a server-side defect; there is no client-side fix. The hook exists to surface
#   the four operator-side workarounds when a user is most likely to hit the block (Opus
#   pinned, false-positive flood window still active).
#
#   Reference: https://gist.github.com/yurukusa/<TBD>  (4 operator-side paths through the
#   false-positive flood — model swap, prompt warmup, CVP application, retry harness)
#
# What this hook does:
#   On SessionStart, inspect ANTHROPIC_MODEL and emit a one-line advisory matching one
#   of four states:
#     - ANTHROPIC_MODEL unset                                  → silent (default routing)
#     - ANTHROPIC_MODEL pinned to a Sonnet variant             → silent (unaffected model)
#     - ANTHROPIC_MODEL pinned to an Opus variant + CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1
#                                                              → emit one-time advisory
#     - ANTHROPIC_MODEL pinned to an Opus variant + REMIND unset
#                                                              → silent (opt-in only)
#
#   Silent by default. CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 opts in to the awareness
#   note. CC_AUP_FALSE_POSITIVE_HELPER_QUIET=1 suppresses permanently after acknowledgement.
#
# When this hook does NOT fire a warning:
#   - CC_AUP_FALSE_POSITIVE_HELPER_QUIET=1
#   - ANTHROPIC_MODEL is unset or pinned to a non-Opus model
#   - CC_AUP_FALSE_POSITIVE_HELPER_REMIND is unset (opt-in only)
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/aup-false-positive-helper.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_AUP_FALSE_POSITIVE_HELPER_QUIET=1    — never emit anything
#   CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1   — emit advisory when Opus is pinned (opt-in)

# Silence path
if [ "${CC_AUP_FALSE_POSITIVE_HELPER_QUIET:-0}" = "1" ]; then
  exit 0
fi

# Model unset → use default routing, no specific advisory needed
if [ -z "${ANTHROPIC_MODEL:-}" ]; then
  exit 0
fi

# Pinned to a model that is NOT an Opus variant → unaffected by the cluster
case "$ANTHROPIC_MODEL" in
  *opus*|*Opus*|*OPUS*) : ;;  # Opus variant — continue to advisory
  *) exit 0 ;;                # Sonnet, Haiku, or other — silent
esac

# Opt-in gate: only emit when the user explicitly requested awareness
if [ "${CC_AUP_FALSE_POSITIVE_HELPER_REMIND:-0}" != "1" ]; then
  exit 0
fi

# Opt-in advisory path: ANTHROPIC_MODEL pinned to Opus, user wants the awareness note
cat >&2 <<EOF
[aup-false-positive-helper] ANTHROPIC_MODEL is pinned to "$ANTHROPIC_MODEL".

Between 2026-05-18 and the current session window, the Anthropic Usage Policy classifier
has over-triggered on benign prompts when Opus models (4.7, 4.6, 1M variants) are pinned.
Sonnet variants are reportedly unaffected. The block surfaces as:

  "API Error: ... This request triggered cyber-related safeguards."

Four operator-side mitigations while the server-side classifier remains unstable:

  1. Swap to Sonnet for sensitive sessions
       export ANTHROPIC_MODEL=claude-sonnet-4-7
     (or any Sonnet variant; the cluster signature points to an Opus-specific path)

  2. Warm up the session with project context before security/kernel/research prompts
     A short context-establishing turn often passes where a cold sensitive prompt blocks

  3. Apply for the Cyber Verification Program (CVP) if your work routinely involves
     legitimate cyber/kernel/biomedical/FPGA terminology
       https://www.anthropic.com/legal/cyber-verification-program

  4. The classifier is non-deterministic — a single retry on identical input frequently
     succeeds. If a benign prompt blocks once, retry before rewording

To suppress this advisory:
  export CC_AUP_FALSE_POSITIVE_HELPER_QUIET=1

GitHub tracker (25+ independent reports, 2026-05-18 through 2026-05-27):
  https://github.com/anthropics/claude-code/issues/60366
  https://github.com/anthropics/claude-code/issues/62190
EOF

exit 0
