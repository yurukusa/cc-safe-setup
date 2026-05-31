#!/bin/bash
# opus48-routine-task-warning.sh — Surface the Cluster 23 candidate (Opus 4.8
# effort-budget regression) at session start for operators running Opus 4.8 on
# routine coding workflows.
#
# Background:
#   Cluster 23 candidate documents that Opus 4.8 under effort=medium can spend
#   40-50k output tokens on hidden thinking for a routine coding turn — Issue
#   #64153 anchor (46,433 output tokens / 22m 43s of thinking on a small
#   rename-impact scan; transcript stop_reason=end_turn so this completed
#   normally, not a retry / not an API 400). The reporter explicitly compares:
#   Opus 4.6 / Opus 4.7 do NOT show this magnitude for comparable routine work.
#
#   Five independent filings 2026-05-31:
#     #64153 (anchor, 46k output / 22m43s thinking, macOS 2.1.158)
#     #64152 (Opus over-engineers simple tasks in agentic/CLI mode)
#     #64143 (Session limits maxing out without user interaction)
#     #64102 (excessive token consumption + API disconnects)
#     #63455 (simple tasks consuming 40-50k tokens)
#
#   Four sub-cluster axes:
#     23A single-turn thinking-budget magnitude (40-50k output on routine work)
#     23B effort-tier perception mismatch (medium behaves like high/xhigh)
#     23C operator-attribution gap (operator sees quota burn that was not theirs)
#     23D over-engineering on simple tasks
#
#   Cluster 23 is still a candidate; tracked at cluster-tracker.html pending
#   full promotion criteria (15+ aggregate reactions or sixth independent
#   filing surfacing).
#
#   Reference:
#     https://github.com/anthropics/claude-code/issues/64153  (anchor)
#     Internal research: customer-pain-research-cluster-23-opus48-thinking-cost-2026-05-31.md
#
# What this hook does:
#   On SessionStart, when CC_OPUS48_ROUTINE_WARN=1 is set, emits a stderr
#   advisory naming the three operator-side mitigations from the Cluster 23
#   candidate articulation. The hook is fully opt-in — silent by default.
#   The advisory does not try to detect whether Opus 4.8 is actually the
#   active model; the SessionStart payload often does not include model
#   information, and a wrong guess about model identity is worse than a
#   neutral advisory.
#
# Pairs with: output-token-spike-detector.sh (PostToolUse, observes the
#   per-turn output_tokens magnitude after the fact). The SessionStart
#   advisory frames the cluster up front; the PostToolUse detector
#   surfaces specific events.
#
# When this hook does NOT emit anything:
#   - CC_OPUS48_ROUTINE_WARN is unset or empty
#   - CC_OPUS48_ROUTINE_DISABLE=1
#   - CC_OPUS48_ROUTINE_QUIET=1
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/opus48-routine-task-warning.sh" }]
#     }]
#   }
# }
# And in your shell rc, opt in:
#   export CC_OPUS48_ROUTINE_WARN=1
#
# Env vars:
#   CC_OPUS48_ROUTINE_WARN=1     — opt-in trigger (required to emit)
#   CC_OPUS48_ROUTINE_DISABLE=1  — never emit (overrides WARN)
#   CC_OPUS48_ROUTINE_QUIET=1    — silent (overrides WARN)
#
# Design notes:
#   - Opt-in by default. Operators not on Opus 4.8, or operators who do not
#     run routine coding turns, do not benefit from the advisory.
#   - No model auto-detection. The SessionStart payload is not guaranteed
#     to include model identity, and assuming Opus 4.8 when the operator
#     is on a different model would be a noise event.
#   - Candidate-cluster framing. The advisory clearly states Cluster 23 is
#     a candidate (not yet promoted) and links the anchor issue for
#     verification.
#   - Never blocks. Exit always 0.

set -u

# Hard disable path
if [ "${CC_OPUS48_ROUTINE_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Quiet path
if [ "${CC_OPUS48_ROUTINE_QUIET:-0}" = "1" ]; then
  exit 0
fi

# Opt-in gate
if [ "${CC_OPUS48_ROUTINE_WARN:-0}" != "1" ]; then
  exit 0
fi

cat >&2 <<'EOF'
[opus48-routine-task-warning] Cluster 23 candidate advisory: Opus 4.8 under
effort=medium can spend 40-50k output tokens on hidden thinking for a routine
coding turn — a magnitude the anchor reporter explicitly states does NOT occur
on Opus 4.6 / Opus 4.7 for comparable work.

Five independent filings within the last week document the pattern:

  #64153  (anchor) — medium effort burned 46,433 output tokens / 22m 43s of
          thinking on a routine rename-impact scan. Transcript:
          input_tokens 131, cache_read 91,877, cache_creation 4,054,
          output 46,433, stop_reason end_turn (completed normally,
          not a retry, not an API 400). macOS 2.1.158.

  #64152  Opus over-engineers simple tasks in agentic/CLI mode, wasting
          tokens (area:tools + area:model, Linux).

  #64143  Session limits maxing out on their own, without any interaction
          from user — the operator-visible signal of the underlying budget
          drain (area:cost + area:mcp).

  #64102  Excessive token consumption mixed with API disconnects.

  #63455  Simple tasks consuming 40-50k tokens.

Four sub-cluster axes:

  23A  Single-turn thinking-budget magnitude (40-50k output tokens on
       routine work where 1-5k would be the expected baseline).
  23B  Effort-tier perception mismatch: "medium effort behaved much
       closer to a high/xhigh thinking budget" per the anchor reporter.
  23C  Operator-attribution gap: the operator sees quota burn that was
       not their action, intersection with Cluster 4 (Pro Max quota
       anomaly).
  23D  Over-engineering on simple tasks: the model elaborates approaches
       that the visible work does not require.

This is independent from Cluster 22 (Opus 4.8 pre-execution fabrication).
Cluster 22 is the correctness hazard (model asserts tool-output values
before tools return); Cluster 23 candidate is the cost hazard (model
burns 10× the expected hidden-thinking budget for the same routine
work). Same version window (v2.1.156-v2.1.158, Opus 4.8 default),
possibly the same root cause manifesting in two distinct surface
failures.

It is also independent from Cluster 4 (Pro Max quota anomaly), which
is server-side cache_creation_input_tokens inflation. Cluster 23
candidate is output_tokens growth — #64153's transcript shows
cache_creation 4,054 vs output 46,433, the opposite ratio of Cluster
4's signature. So Cluster 4's defense hooks (cache-creation-drift-
detector.sh etc.) do not catch Cluster 23 candidate directly; they
catch it indirectly only as it accumulates into session-rate anomalies.

Three operator-side mitigations:

  1) Switch to Opus 4.7 (/model claude-opus-4-7)
     The reporter's own comparison: Opus 4.6 and 4.7 do not show this
     magnitude on comparable routine work. This is full cluster
     elimination — no per-turn measurement or threshold tuning needed.

  2) Set effort=low for routine coding turns
     The anchor signal is that medium effort behaves like high/xhigh.
     Explicit effort=low constrains the thinking budget regardless of
     whether the underlying calibration regression has been fixed.

  3) Periodic audit of output_tokens magnitude
     Run on your transcript directory:
       jq -s 'map(.message.usage.output_tokens // 0) | sort | .[length/2]' \
         ~/.claude/projects/**/recent.jsonl
     Routine coding turns should produce 1-5k output tokens. A median
     above 10k is the Cluster 23 candidate signal — pair with the
     companion hook output-token-spike-detector.sh (PostToolUse,
     surfaces per-turn spikes in real time).

Companion hook (recommended pairing):
  examples/output-token-spike-detector.sh
  PostToolUse, rolling-window comparison of output_tokens against
  trailing baseline, fires above 3× the recent mean and above a
  configurable absolute floor (default 10000) to suppress noise on
  small turns.

This is a candidate cluster — full Cluster 23 promotion happens when
cumulative reactions cross 15 or a sixth independent filing surfaces.
The cc-safe-setup tracker (cluster-tracker.html) records the current
state.

To silence this advisory once you have applied the relevant mitigations:
  unset CC_OPUS48_ROUTINE_WARN
  # or
  export CC_OPUS48_ROUTINE_QUIET=1

References:
  https://github.com/anthropics/claude-code/issues/64153  (anchor)
  https://github.com/anthropics/claude-code/issues/64152  (over-engineering)
  https://github.com/anthropics/claude-code/issues/64143  (silent quota drain)
EOF

exit 0
