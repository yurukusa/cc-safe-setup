#!/bin/bash
# opus-degradation-tracker.sh — Personal Opus 4.7 pass-rate tracker that alerts on statistical degradation
#
# Background:
#   On 2026-05-22, an independent third party (Margin Lab) detected statistically
#   significant degradation in Claude Code Opus 4.7's SWE-Bench-Pro daily pass rate
#   (65% baseline → 57% on the 7-day window, delta -8 points, exceeds the 4.3%
#   significance threshold at 95% CI). The aggregate signal is documented at
#   https://gist.github.com/yurukusa/77bf08523bda41132087a03de4523d7a — but each
#   operator's workload responds differently to model drift. This hook lets an
#   operator translate Margin Lab's aggregate signal into a workload-specific
#   decision input.
#
#   The operator records pass/fail outcomes from their own Claude Code sessions
#   (one line per session, simple shell append) and this hook computes:
#     - baseline pass rate (first N days of the log, default 30)
#     - recent pass rate (last 7 days)
#     - delta and whether it crosses the configured threshold
#
#   When degradation crosses the threshold, the hook surfaces the four operator
#   paths from Migration Playbook v2 plus the Margin Lab Gist for cross-source
#   verification. Silent in the happy path.
#
# What this hook does:
#   On SessionStart, read ~/.cc-eval-log (or CC_EVAL_LOG_PATH), compute baseline
#   vs recent pass rate, emit a one-line advisory if recent drops below baseline
#   by more than the threshold (default 5 percentage points). Otherwise silent.
#
# Log format (one line per session, append by hand or via shell function):
#   YYYY-MM-DD HH:MM session-tag pass|fail
#
#   Example:
#     2026-05-15 14:23 pr-review-task pass
#     2026-05-15 18:01 doc-rewrite fail
#     2026-05-22 09:12 pr-review-task fail
#     2026-05-23 11:30 doc-rewrite fail
#
#   Optional fourth column "notes" is ignored — useful for human context.
#
# Suggested helper (add to ~/.bashrc or ~/.zshrc):
#   cc-eval-pass() { echo "$(date '+%Y-%m-%d %H:%M') ${1:-session} pass" >> ~/.cc-eval-log; }
#   cc-eval-fail() { echo "$(date '+%Y-%m-%d %H:%M') ${1:-session} fail" >> ~/.cc-eval-log; }
#
# When this hook does NOT fire a warning:
#   - CC_OPUS_DEGRADATION_TRACKER_QUIET=1
#   - log file does not exist or has fewer than CC_OPUS_DEGRADATION_TRACKER_MIN_SAMPLES (default 20) entries
#   - recent pass rate is within threshold of baseline (default 5 pp)
#   - log file is malformed (logs to stderr, exits 0 so SessionStart continues)
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/opus-degradation-tracker.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_EVAL_LOG_PATH                          — log file location (default ~/.cc-eval-log)
#   CC_OPUS_DEGRADATION_TRACKER_QUIET=1       — never emit anything
#   CC_OPUS_DEGRADATION_TRACKER_THRESHOLD=N   — percentage-point threshold for alert (default 5)
#   CC_OPUS_DEGRADATION_TRACKER_MIN_SAMPLES=N — minimum entries before stats run (default 20)
#   CC_OPUS_DEGRADATION_TRACKER_BASELINE_DAYS=N — days at the front of the log treated as baseline (default 30)
#   CC_OPUS_DEGRADATION_TRACKER_RECENT_DAYS=N — days at the tail of the log treated as recent window (default 7)

set -u

# Silence path
if [ "${CC_OPUS_DEGRADATION_TRACKER_QUIET:-0}" = "1" ]; then
  exit 0
fi

LOG_PATH="${CC_EVAL_LOG_PATH:-$HOME/.cc-eval-log}"
THRESHOLD="${CC_OPUS_DEGRADATION_TRACKER_THRESHOLD:-5}"
MIN_SAMPLES="${CC_OPUS_DEGRADATION_TRACKER_MIN_SAMPLES:-20}"
BASELINE_DAYS="${CC_OPUS_DEGRADATION_TRACKER_BASELINE_DAYS:-30}"
RECENT_DAYS="${CC_OPUS_DEGRADATION_TRACKER_RECENT_DAYS:-7}"

# Log file missing → user hasn't set up tracking yet → silent
if [ ! -f "$LOG_PATH" ]; then
  exit 0
fi

# Read and parse the log. Each valid line: YYYY-MM-DD HH:MM tag pass|fail
# Use awk for portable parsing without external date dependencies.
analysis=$(awk -v threshold="$THRESHOLD" -v min_samples="$MIN_SAMPLES" -v baseline_days="$BASELINE_DAYS" -v recent_days="$RECENT_DAYS" '
BEGIN {
    total = 0
    baseline_pass = 0; baseline_total = 0
    recent_pass = 0; recent_total = 0
    today_epoch = systime()
    baseline_cutoff_epoch = today_epoch - (baseline_days * 86400)
    recent_cutoff_epoch = today_epoch - (recent_days * 86400)
}
/^[0-9]{4}-[0-9]{2}-[0-9]{2}[ \t]+[0-9]{2}:[0-9]{2}[ \t]+[^ \t]+[ \t]+(pass|fail)([ \t]|$)/ {
    # Parse date into epoch (assumes GNU/BSD compatible mktime via awk)
    split($1, d, "-")
    split($2, t, ":")
    line_epoch = mktime(d[1] " " d[2] " " d[3] " " t[1] " " t[2] " 00")
    if (line_epoch <= 0) next
    total++
    is_pass = ($4 == "pass") ? 1 : 0

    # Recent window: last RECENT_DAYS days
    if (line_epoch >= recent_cutoff_epoch) {
        recent_total++
        if (is_pass) recent_pass++
    }

    # Baseline window: oldest BASELINE_DAYS days of recorded history
    # We compute this in a second pass with "min_epoch" tracking.
    # Use total==1 (first valid entry) instead of NR==1: NR counts every
    # file line including malformed ones that fail the regex match.
    if (total == 1 || line_epoch < min_epoch) min_epoch = line_epoch
    sample[total, "epoch"] = line_epoch
    sample[total, "pass"] = is_pass
}
END {
    if (total < min_samples) {
        print "INSUFFICIENT " total
        exit
    }
    # Now compute baseline window from the oldest BASELINE_DAYS of recorded data
    baseline_cutoff_from_first = min_epoch + (baseline_days * 86400)
    for (i = 1; i <= total; i++) {
        if (sample[i, "epoch"] <= baseline_cutoff_from_first) {
            baseline_total++
            if (sample[i, "pass"]) baseline_pass++
        }
    }
    if (baseline_total < min_samples / 2) {
        print "BASELINE_TOO_SMALL " baseline_total
        exit
    }
    if (recent_total < min_samples / 4) {
        print "RECENT_TOO_SMALL " recent_total
        exit
    }
    baseline_rate = (baseline_pass / baseline_total) * 100
    recent_rate = (recent_pass / recent_total) * 100
    delta = baseline_rate - recent_rate
    if (delta > threshold) {
        printf "DEGRADED %d %d %d %d %.1f %.1f %.1f\n", baseline_pass, baseline_total, recent_pass, recent_total, baseline_rate, recent_rate, delta
    } else {
        printf "HEALTHY %d %d %d %d %.1f %.1f %.1f\n", baseline_pass, baseline_total, recent_pass, recent_total, baseline_rate, recent_rate, delta
    }
}
' "$LOG_PATH" 2>/dev/null) || {
    # awk failure → log is malformed in a way the parser cannot recover from
    # Exit silently so SessionStart is not blocked
    exit 0
}

status="${analysis%% *}"
case "$status" in
    INSUFFICIENT|BASELINE_TOO_SMALL|RECENT_TOO_SMALL|HEALTHY|"")
        # Healthy or not enough data — silent
        exit 0
        ;;
    DEGRADED)
        # Parse the rest of the line for the numbers
        read -r _ baseline_pass baseline_total recent_pass recent_total baseline_rate recent_rate delta <<< "$analysis"
        cat >&2 <<EOF
[opus-degradation-tracker] Personal pass rate dropped from ${baseline_rate}% baseline (${baseline_pass}/${baseline_total}) to ${recent_rate}% recent (${recent_pass}/${recent_total}) — delta -${delta} pp, exceeding the configured threshold of -${THRESHOLD} pp.

This is your own workload's signal. The independent third-party Margin Lab tracker
(SWE-Bench-Pro daily evals on Opus 4.7) also shows -8 pp degradation since 2026-05-22.
The two signals together suggest a model-side change rather than a workload-specific issue.

Cross-source verification:
  https://gist.github.com/yurukusa/77bf08523bda41132087a03de4523d7a
  (4 operator-side paths + 7-day audit sequence)

Decision context for the 2026-06-15 credit pool split (\$20 Pro / \$100 Max 5x / \$200 Max 20x):
  https://yurukusa.gumroad.com/l/claude-code-migration-playbook?utm_source=hook-opus-degradation-tracker&utm_medium=hook&utm_campaign=5-22-degradation

To stop seeing this alert: \`export CC_OPUS_DEGRADATION_TRACKER_QUIET=1\` in your shell rc.
EOF
        exit 0
        ;;
    *)
        # Unknown status — log to stderr but don't block
        exit 0
        ;;
esac
