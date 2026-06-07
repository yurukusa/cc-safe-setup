#!/bin/bash
# cost-incident-self-audit.sh — Tell me which real Claude Code cost accidents
#   my current setup is still exposed to
#
# This is NOT a hook — it is a one-shot diagnostic you run by hand:
#
#     bash examples/cost-incident-self-audit.sh
#
# Why this exists: the cost/billing cluster is the single largest pain cluster
# in the Claude Code tracker (200+ open issues), and the danger is not "my bill
# is a bit high" — it is sudden, irreversible loss: a fan-out of pushes burning
# a month of GitHub Actions minutes in 3 hours (#65944), a research loop running
# ~98 WebFetch calls before anyone notices (#65684), an oversized image retried
# until cost is ~35x (#65636), 1M-context credits draining without opt-in (#64445).
# Generic cost trackers and the official spend page tell you what you ALREADY
# spent. None of them tell you which of these specific accidents your setup has
# no guard against *before* one happens. That is the gap this fills.
#
# It only reports what it can actually verify in your settings + environment.
# It never edits anything, never phones home, and fails open: if it cannot read
# something it stays quiet rather than guessing. Every finding cites the real
# issue it comes from so you can read the incident yourself.
#
# Always exits 0 (it is a report, not a gate). The exposure count is in the
# output and, with --json, in the "exposures" field. CC_COST_AUDIT_SETTINGS
# overrides the settings glob (mainly for testing).

set -u

JSON=0
for a in "$@"; do
    case "$a" in
        --json) JSON=1 ;;
        -h|--help)
            echo "Usage: bash cost-incident-self-audit.sh [--json]"
            echo "Reports which documented Claude Code cost accidents your setup is exposed to."
            exit 0 ;;
    esac
done

# --- Gather settings content (best effort, fail open) ---------------------
# Hooks are configured in settings.json / settings.local.json at user or
# project scope. We just need the raw text to see which guard commands are
# wired in; we do not parse the schema so a slightly unusual layout still works.
SETTINGS_GLOB="${CC_COST_AUDIT_SETTINGS:-}"
SETTINGS_TEXT=""
if [ -n "$SETTINGS_GLOB" ]; then
    for f in $SETTINGS_GLOB; do
        [ -f "$f" ] && SETTINGS_TEXT="$SETTINGS_TEXT
$(cat "$f" 2>/dev/null)"
    done
else
    for f in \
        "$HOME/.claude/settings.json" \
        "$HOME/.claude/settings.local.json" \
        "./.claude/settings.json" \
        "./.claude/settings.local.json"; do
        [ -f "$f" ] && SETTINGS_TEXT="$SETTINGS_TEXT
$(cat "$f" 2>/dev/null)"
    done
fi

# A guard is considered "wired in" if its script name appears anywhere in the
# settings text (the hook command references the file by name).
has_guard() { printf '%s' "$SETTINGS_TEXT" | grep -q "$1"; }

# Does this project have CI workflows that an agentic push could fan out onto?
HAS_WORKFLOWS=0
if [ -d "./.github/workflows" ] && ls ./.github/workflows/*.y*ml >/dev/null 2>&1; then
    HAS_WORKFLOWS=1
fi

# --- Define the checks ----------------------------------------------------
# Each check appends "issue|title|fix" to FINDINGS when the setup is exposed.
FINDINGS=()

# 1. CI minutes blast from multi-branch pushes — only relevant if CI exists.
if [ "$HAS_WORKFLOWS" -eq 1 ] && ! has_guard "git-push-blast-radius-guard"; then
    FINDINGS+=("65944|Pushing one fix across many branches fans out CI runs and can burn a month of GitHub Actions minutes in hours|add examples/git-push-blast-radius-guard.sh as a PreToolUse(Bash) hook")
fi

# 2. WebFetch / research runaway cost.
if ! has_guard "webfetch-runaway-guard"; then
    FINDINGS+=("65684|A research loop can run dozens of WebFetch calls without pausing, spending real money before you notice|add examples/webfetch-runaway-guard.sh as a PreToolUse(WebFetch) hook")
fi

# 3. Oversized image retried into a cost loop.
if ! has_guard "image-dimension-guard"; then
    FINDINGS+=("65636|An oversized image can be retried until prompt caching breaks and cost climbs ~35x|add examples/image-dimension-guard.sh as a PreToolUse(Read) hook")
fi

# 4. Unbounded command output exhausting the session (and re-processing cost).
if ! has_guard "unbounded-output-guard"; then
    FINDINGS+=("65789|An unbounded-output command (yes, cat /dev/zero, ...) floods the session and inflates re-processing cost|add examples/unbounded-output-guard.sh as a PreToolUse(Bash) hook")
fi

# 5. No spend visibility at all — none of the cost/budget signals are wired in.
if ! has_guard "daily-cost-guard" && ! has_guard "session-cost-alert" \
   && ! has_guard "token-budget-guard" && ! has_guard "cost-tracker"; then
    FINDINGS+=("0|No session/daily cost signal is configured, so a runaway has nothing watching the running total|add one of examples/daily-cost-guard.sh, session-cost-alert.sh, or token-budget-guard.sh")
fi

# 6. 1M context left on — silently drains the weekly quota faster.
# Exposure only when the user has not explicitly turned it off.
if [ "${CLAUDE_CODE_DISABLE_1M_CONTEXT:-}" != "1" ]; then
    FINDINGS+=("64445|1M context can consume credits/quota without you explicitly selecting 1M mode, draining the weekly limit faster via larger re-processed context|set CLAUDE_CODE_DISABLE_1M_CONTEXT=1 (and prefer opusplan) if you do not need the 1M window")
fi

COUNT=${#FINDINGS[@]}

# --- Output ---------------------------------------------------------------
if [ "$JSON" -eq 1 ]; then
    printf '{"exposures":%d,"findings":[' "$COUNT"
    first=1
    for f in "${FINDINGS[@]}"; do
        IFS='|' read -r issue title fix <<EOF
$f
EOF
        [ "$first" -eq 0 ] && printf ','
        first=0
        # JSON-escape the two free-text fields minimally (quotes/backslashes).
        et=$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')
        ef=$(printf '%s' "$fix" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '{"issue":"%s","title":"%s","fix":"%s"}' "$issue" "$et" "$ef"
    done
    printf ']}\n'
    exit 0
fi

echo ""
echo "  Claude Code cost-accident self-audit"
echo "  ===================================="
if [ "$COUNT" -eq 0 ]; then
    echo ""
    echo "  No exposures found against the documented cost accidents checked here."
    echo "  (This only covers the patterns above — it is not a guarantee.)"
    echo ""
    exit 0
fi

echo ""
echo "  Exposed to $COUNT of the documented cost accidents below:"
echo ""
for f in "${FINDINGS[@]}"; do
    IFS='|' read -r issue title fix <<EOF
$f
EOF
    if [ "$issue" = "0" ]; then
        echo "  [!] $title"
    else
        echo "  [!] $title (#$issue)"
    fi
    echo "      fix: $fix"
    echo ""
done
echo "  These guards ship in this repo; wire the ones you want into your"
echo "  .claude/settings.json hooks, or run 'npx cc-safe-setup' to set them up."
echo "  Worked examples of these exact incidents (free chapter):"
echo "    https://yurukusa.github.io/cc-safe-setup/token-book.html"
echo ""

exit 0
