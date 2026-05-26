#!/bin/bash
# ================================================================
# version-bump-detector.sh — Detect Claude Code version transitions
#                            at SessionStart and surface them so the
#                            operator can correlate quota or behavior
#                            anomalies with the version change
# ================================================================
# PURPOSE:
#   Claude Code minor versions sometimes ship silent runtime changes
#   that operators cannot detect from within a session. The existing
#   version-regression-warner.sh covers a curated list of known-bad
#   versions; this hook is the dynamic complement — it tells the
#   operator every time the running CC version changes, regardless
#   of whether that version is on a known-bad list yet.
#
#   The Pro Max quota anomaly cluster on anthropics/claude-code
#   (~2,200 cumulative reactions across 10 open issues) names four
#   independent runtime/date boundaries (2026-03-23, v2.1.89,
#   v2.1.100, 2.1.1) where consumption rate changed silently for
#   subscribers. When an operator notices "my quota feels off this
#   week", the first useful question is "did the CC version change
#   recently?". This hook answers it at session start.
#
#   Pairs with the Pro Max Quota Anomaly Operator Field Guide (Gist
#   158436e88d169406593d55bd84f0d7e9) — Path 5 of the field guide is
#   "version-bump cross-reference". This hook automates that path.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# OPERATOR-SIDE COMPLEMENT TO:
#   - version-regression-warner.sh (static known-bad version table)
#   - cache-creation-drift-detector.sh (per-request token drift)
#
# BEHAVIOR:
#   - First run: records current version, no warning.
#   - Subsequent run with same version: silent.
#   - Subsequent run with different version: warns via
#     hookSpecificOutput.additionalContext with the previous version,
#     the current version, and pointers to investigate quota drift.
#   - Maintains a version-history JSONL log for retrospective review.
#
# CONFIGURATION (env vars):
#   CC_VERSION_BUMP_DISABLE   set to "1" to disable entirely
#   CC_VERSION_BUMP_STATE     state file path (default: ~/.cache/cc-safe-setup/last-cc-version)
#   CC_VERSION_BUMP_LOG       history log path (default: ~/.cache/cc-safe-setup/cc-version-history.jsonl)
#   CC_VERSION_BUMP_OVERRIDE  override detected version (testing)
#
# Inspect the history:
#   tail -20 ~/.cache/cc-safe-setup/cc-version-history.jsonl | jq .
#   jq -s 'map(.version) | unique' ~/.cache/cc-safe-setup/cc-version-history.jsonl
#
# RELATED ISSUES (the Pro Max quota anomaly cluster):
#   https://github.com/anthropics/claude-code/issues/16157
#   https://github.com/anthropics/claude-code/issues/38335
#   https://github.com/anthropics/claude-code/issues/46917
#   https://github.com/anthropics/claude-code/issues/45756
#   https://github.com/anthropics/claude-code/issues/41788
# ================================================================

set -u

[ "${CC_VERSION_BUMP_DISABLE:-0}" = "1" ] && exit 0

STATE="${CC_VERSION_BUMP_STATE:-${HOME}/.cache/cc-safe-setup/last-cc-version}"
LOG="${CC_VERSION_BUMP_LOG:-${HOME}/.cache/cc-safe-setup/cc-version-history.jsonl}"

mkdir -p "$(dirname "$STATE")" 2>/dev/null
mkdir -p "$(dirname "$LOG")" 2>/dev/null

# Detect the running Claude Code version. Allow override for tests.
if [ -n "${CC_VERSION_BUMP_OVERRIDE:-}" ]; then
    CURRENT="$CC_VERSION_BUMP_OVERRIDE"
else
    if ! command -v claude >/dev/null 2>&1; then
        exit 0
    fi
    CURRENT=$(claude --version 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n 1)
fi

# If we couldn't detect a version, exit silently.
if [ -z "$CURRENT" ]; then
    exit 0
fi

# Validate the version looks like semver-ish.
case "$CURRENT" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) exit 0 ;;
esac

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Read the previously-recorded version. If the state file doesn't
# exist yet, this is the first run — record and exit silently.
if [ ! -f "$STATE" ]; then
    echo "$CURRENT" > "$STATE"
    printf '{"ts":"%s","version":"%s","event":"first_run"}\n' "$TS" "$CURRENT" >> "$LOG"
    exit 0
fi

PREVIOUS=$(cat "$STATE" 2>/dev/null | tr -d '[:space:]')

# Same version as last session — silent.
if [ "$CURRENT" = "$PREVIOUS" ]; then
    exit 0
fi

# Different version — record the transition and warn.
echo "$CURRENT" > "$STATE"
printf '{"ts":"%s","version":"%s","previous":"%s","event":"version_bump"}\n' \
    "$TS" "$CURRENT" "$PREVIOUS" >> "$LOG"

WARNING="===== CLAUDE CODE VERSION BUMP DETECTED =====
Previous session: ${PREVIOUS}
Current session:  ${CURRENT}

Some CC versions ship silent runtime changes that operators cannot
detect from within a session. The Pro Max quota anomaly cluster on
anthropics/claude-code names four such version/date boundaries
(2026-03-23, v2.1.89, v2.1.100, 2.1.1).

If you notice unexpected quota consumption, cache_creation token
counts, or behavior changes in this session vs. recent sessions,
the version change is a candidate cause. Investigation paths:

- Snapshot a representative \`claude --print\` invocation and compare
  cache_creation_input_tokens against your trailing baseline. The
  cache-creation-drift-detector.sh hook automates this comparison.
- Run \`bunx ccusage daily\` for the last 7 days to spot per-day
  variance correlated with the bump.
- Check the Claude Code release notes for ${CURRENT} at
  https://docs.anthropic.com/en/release-notes for documented changes.

Operator field guide (Path 5 of the Pro Max Quota Anomaly guide):
https://gist.github.com/yurukusa/158436e88d169406593d55bd84f0d7e9
===== END VERSION BUMP NOTICE ====="

# Emit hookSpecificOutput so it surfaces at session start.
if command -v jq >/dev/null 2>&1; then
    jq -n \
        --arg ctx "$WARNING" \
        '{
            hookSpecificOutput: {
                hookEventName: "SessionStart",
                additionalContext: $ctx
            }
        }'
else
    # Fallback: write to stderr if jq isn't available.
    echo "$WARNING" >&2
fi

exit 0
