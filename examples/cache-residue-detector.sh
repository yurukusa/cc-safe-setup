#!/bin/bash
# ================================================================
# cache-residue-detector.sh — Detect leftover server-side injection
# caches that persist after opt-out env vars are set
# ================================================================
# PURPOSE:
#   Cluster 8 (server-side prompt injection, v2.1.150+).
#
#   Setting CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 and
#   DISABLE_GROWTHBOOK=1 closes the channel for FUTURE sync, but
#   does NOT delete cache files written before the opt-out. The
#   runtime still reads cached values on startup unless the cache
#   keys are physically removed. This produces a silent gap: the
#   operator believes injection is disabled, but the most recent
#   cached value continues to register as a peer system prompt
#   section until cache eviction or next sync.
#
#   This hook detects the gap: if opt-out env vars are set AND
#   cache residue exists, it prints a one-screen advisory with
#   exact cleanup commands (jq-based, idempotent).
#
# DETECTION:
#   At SessionStart, check:
#     1. Both opt-out env vars are set to 1.
#     2. ~/.claude.json contains cachedGrowthBookFeatures,
#        cachedExperimentFeatures, or cachedStatsigGates keys.
#     3. macOS-only: ~/Library/Application Support/Claude/
#        cachedGrowthBookFeatures file exists.
#   When residue is found in step 2 or 3, print advisory naming
#   the specific files/keys and the cleanup commands.
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# OUTPUT:
#   Advisory only, never blocks. Prints to stderr.
#
# CONFIGURATION:
#   CC_CACHE_RESIDUE_DETECTOR_DISABLE=1  — disable entirely
#   CC_CACHE_RESIDUE_DETECTOR_QUIET=1    — silence after acknowledgment
#   CC_CACHE_RESIDUE_DETECTOR_STRICT=1   — also warn even when
#                                          opt-out env vars are NOT
#                                          set (operators who plan
#                                          to opt out and want a
#                                          forward-looking signal)
#   CC_CACHE_RESIDUE_CLAUDE_JSON         — override default location
#                                          for ~/.claude.json
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/62061 — central
#     report of v2.1.150 server-side injection (46+ reactions).
#   https://github.com/anthropics/claude-code/issues/25141 — earlier
#     transparency request for experimental features.
#   https://github.com/anthropics/claude-code/issues/28941 — earlier
#     report of unauthorized server-side feature flag push.
#
# RELATED HOOKS:
#   server-side-prompt-injection-detector.sh — warns when opt-out
#     env vars are MISSING. Pair with this hook for full coverage:
#     the other hook tells operators to opt out; this one tells
#     them the cache cleanup that the env vars alone do not perform.
#
# DESIGN NOTES:
#   - The hook does NOT touch the cache files. Cleanup is the
#     operator's call; the hook only surfaces the state.
#   - jq is required for reliable JSON inspection. When jq is
#     missing, the hook prints a one-line advisory pointing at the
#     installer and exits clean (fail-open).
#   - The macOS path is reported as informational on non-macOS
#     systems but never causes a failure.

set -u

if [ "${CC_CACHE_RESIDUE_DETECTOR_DISABLE:-0}" = "1" ]; then
    exit 0
fi
if [ "${CC_CACHE_RESIDUE_DETECTOR_QUIET:-0}" = "1" ]; then
    exit 0
fi

# Consume stdin if provided (SessionStart hooks receive JSON input)
if [ ! -t 0 ]; then
    cat >/dev/null 2>&1 || true
fi

OPT_OUT_NON_ESSENTIAL="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-0}"
OPT_OUT_GROWTHBOOK="${DISABLE_GROWTHBOOK:-0}"

STRICT="${CC_CACHE_RESIDUE_DETECTOR_STRICT:-0}"

# When strict mode is off, only warn if the operator has already opted out.
# This matches the hook's primary purpose: catching the silent gap between
# opt-out and cache cleanup. Strict mode flips it to forward-looking advisory.
if [ "$STRICT" != "1" ]; then
    if [ "$OPT_OUT_NON_ESSENTIAL" != "1" ] && [ "$OPT_OUT_GROWTHBOOK" != "1" ]; then
        exit 0
    fi
fi

CLAUDE_JSON="${CC_CACHE_RESIDUE_CLAUDE_JSON:-$HOME/.claude.json}"

RESIDUE_KEYS=()
RESIDUE_FILES=()
NEEDS_JQ_ADVISORY=0

if [ -f "$CLAUDE_JSON" ] && [ -r "$CLAUDE_JSON" ]; then
    if command -v jq >/dev/null 2>&1; then
        # Inspect known cache keys. Any one of these being present and non-empty
        # is residue worth surfacing.
        for key in cachedGrowthBookFeatures cachedExperimentFeatures cachedStatsigGates; do
            count=$(jq --arg k "$key" '
                if has($k) then
                    (.[$k] | if type=="object" then (keys|length)
                             elif type=="array" then length
                             else 0 end)
                else 0 end
            ' "$CLAUDE_JSON" 2>/dev/null || echo 0)
            if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
                RESIDUE_KEYS+=("$key ($count entries)")
            fi
        done
    else
        # Fall back to a coarse grep when jq is missing. This avoids false
        # positives in the cleanup advisory by labeling the result as coarse.
        if grep -q '"cachedGrowthBookFeatures"' "$CLAUDE_JSON" 2>/dev/null; then
            RESIDUE_KEYS+=("cachedGrowthBookFeatures (count unknown — jq missing)")
        fi
        if grep -q '"cachedExperimentFeatures"' "$CLAUDE_JSON" 2>/dev/null; then
            RESIDUE_KEYS+=("cachedExperimentFeatures (count unknown — jq missing)")
        fi
        if grep -q '"cachedStatsigGates"' "$CLAUDE_JSON" 2>/dev/null; then
            RESIDUE_KEYS+=("cachedStatsigGates (count unknown — jq missing)")
        fi
        if [ "${#RESIDUE_KEYS[@]}" -gt 0 ]; then
            NEEDS_JQ_ADVISORY=1
        fi
    fi
fi

# macOS Desktop cache — informational on Linux/CLI installs.
MAC_CACHE="$HOME/Library/Application Support/Claude/cachedGrowthBookFeatures"
if [ -f "$MAC_CACHE" ]; then
    RESIDUE_FILES+=("$MAC_CACHE")
fi

if [ "${#RESIDUE_KEYS[@]}" -eq 0 ] && [ "${#RESIDUE_FILES[@]}" -eq 0 ]; then
    exit 0
fi

# Compose advisory. Keep it under one screen so operators can read it
# without scrolling. The cleanup commands are idempotent and reversible
# (the runtime repopulates the keys on next sync if opt-out env vars are
# unset).
{
    echo "ADVISORY: server-side injection cache residue detected (Cluster 8)."
    if [ "$STRICT" = "1" ]; then
        if [ "$OPT_OUT_NON_ESSENTIAL" != "1" ] || [ "$OPT_OUT_GROWTHBOOK" != "1" ]; then
            echo "  Strict mode is on; opt-out env vars are not fully set. Residue"
            echo "  will continue to be written on the ~60s refresh cadence."
        fi
    fi
    if [ "${#RESIDUE_KEYS[@]}" -gt 0 ]; then
        echo "  ${CLAUDE_JSON}:"
        for k in "${RESIDUE_KEYS[@]}"; do
            echo "    - $k"
        done
    fi
    if [ "${#RESIDUE_FILES[@]}" -gt 0 ]; then
        echo "  Cache files present:"
        for f in "${RESIDUE_FILES[@]}"; do
            echo "    - $f"
        done
    fi
    if [ "$NEEDS_JQ_ADVISORY" = "1" ]; then
        echo "  jq was not found on PATH. Install jq for the exact entry counts and"
        echo "  for the idempotent cleanup command below."
    fi
    echo "  Cleanup (idempotent; safe to run repeatedly):"
    if command -v jq >/dev/null 2>&1; then
        echo "    jq 'del(.cachedGrowthBookFeatures, .cachedExperimentFeatures, .cachedStatsigGates)' \\"
        echo "      \"$CLAUDE_JSON\" > \"$CLAUDE_JSON.tmp\" && mv \"$CLAUDE_JSON.tmp\" \"$CLAUDE_JSON\""
    fi
    if [ "${#RESIDUE_FILES[@]}" -gt 0 ]; then
        for f in "${RESIDUE_FILES[@]}"; do
            echo "    rm -- \"$f\""
        done
    fi
    echo "  Background: Setting CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 and"
    echo "  DISABLE_GROWTHBOOK=1 closes the channel for future sync but does not"
    echo "  delete already-cached values. The runtime continues to read them on"
    echo "  startup. Reference: https://github.com/anthropics/claude-code/issues/62061"
    echo "  Silence after acknowledgment: export CC_CACHE_RESIDUE_DETECTOR_QUIET=1"
} >&2

exit 0
