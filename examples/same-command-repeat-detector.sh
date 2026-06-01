#!/bin/bash
# same-command-repeat-detector.sh — Block Opus 4.8 same-command repeat-execution
# (Cluster 25 candidate, axis 25F — non-no-op compensation repeat)
#
# Background:
#   Sibling of axis 25B (echo-probe spam) with one operationally critical
#   difference: this axis fires on REAL, non-no-op commands. Where 25B emits
#   "echo s1, echo s2, ..." (cluttering screen but burning minimal CPU), 25F
#   re-emits the same real build/test/lint/deploy command 5–10 times in a
#   row — burning actual CPU, wall-clock, build artefact churn, and tokens.
#
#   The root mechanic is the same as 25B: the model perceives non-receipt of
#   the previous result and emits another invocation hoping it will land.
#   The model cannot distinguish:
#     - result-delivery-failed (call ran, output didn't reach model)
#     - result-was-empty       (call ran, output really was empty)
#     - result-arrived-but-missed (call ran, output present, attention drift)
#   All three produce the same retry burst, but the cost shape on 25F is
#   1–2 orders of magnitude worse than 25B because the repeated command
#   is real work.
#
#   Anchor case:
#     #63887 (comment by @KamilDev, 2026-05-31 23:37 UTC) —
#       "it decided to fire off a build command ten times in a row.
#        This isn't just annoying to look at; it's wasting CPU and time."
#       (Screenshots in the thread show 10 consecutive identical build calls.)
#
#   Sibling axes (Cluster 25, all observed 2026-05-30 to 2026-06-01):
#     25A — late/empty tool-result delivery (substrate, no operator-side fix)
#     25B — echo-probe spam compensation (echo-probe-spam-detector.sh)
#     25C — 2>&1 fragmentation hang (redirect-fragment-warner.sh)
#     25D — compounding cost (downstream of 25B/25F/25C)
#     25E — empty-result triggered fabrication (Cluster 22 overlap)
#     25F — non-no-op repeat-execution (this hook)
#
#   This hook is a PreToolUse hook on Bash that:
#     - Captures the canonicalised form of each Bash command per session
#     - Tracks consecutive identical commands
#     - Warns on the 2nd consecutive identical command
#     - Blocks (exit 2) on the N-th consecutive identical command (default 3)
#
#   Canonicalisation rules (so trivial variations don't escape detection):
#     - Strip leading/trailing whitespace
#     - Collapse internal whitespace runs to single space
#     - Lowercase nothing (case may carry meaning — `Make` vs `make`)
#
#   What this hook does NOT cover:
#     - Echo-probe shape (echo-probe-spam-detector.sh covers that)
#     - Commands separated by long gaps (the streak counter resets when any
#       different command runs in between, intentionally)
#
# When this hook does NOT block:
#   - CC_SAME_CMD_REPEAT_DISABLE=1               — never warn or block
#   - CC_SAME_CMD_REPEAT_QUIET=1                 — silent (no stderr output)
#   - CC_SAME_CMD_REPEAT_THRESHOLD=N             — block at N consecutive (default 3)
#   - the Bash command is shorter than 4 chars  — exit 0 (avoid false-positive
#                                                  on `ls`, `pwd`, `cd`, etc.)
#   - the operator includes "# RESET REPEAT"    — exit 0 (manual reset)
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/same-command-repeat-detector.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_SAME_CMD_REPEAT_DISABLE=1   — never warn or block
#   CC_SAME_CMD_REPEAT_QUIET=1     — silent (process but never write to stderr)
#   CC_SAME_CMD_REPEAT_THRESHOLD=N — block at N consecutive same command (default 3)

set -u

if [ "${CC_SAME_CMD_REPEAT_DISABLE:-}" = "1" ]; then
    exit 0
fi

THRESHOLD="${CC_SAME_CMD_REPEAT_THRESHOLD:-3}"
STATE_DIR="${TMPDIR:-/tmp}/cc-same-command-repeat-detector"
mkdir -p "$STATE_DIR"
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
COUNTER_FILE="$STATE_DIR/${SESSION_ID}.counter"
LAST_CMD_FILE="$STATE_DIR/${SESSION_ID}.last"

INPUT=$(cat 2>/dev/null || true)
CMD=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
fi

if [ -z "$CMD" ]; then
    exit 0
fi

# Canonicalise: strip leading/trailing whitespace, collapse internal runs
CMD_CANON=$(printf '%s' "$CMD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -s '[:space:]' ' ')

# Skip very short commands (ls, pwd, cd, etc. — legitimate to repeat)
CMD_LEN=${#CMD_CANON}
if [ "$CMD_LEN" -lt 4 ]; then
    rm -f "$COUNTER_FILE" "$LAST_CMD_FILE"
    exit 0
fi

# Manual reset signal
if printf '%s\n' "$CMD_CANON" | grep -Eq '#[[:space:]]*RESET REPEAT'; then
    rm -f "$COUNTER_FILE" "$LAST_CMD_FILE"
    exit 0
fi

# Compare against last command in this session
LAST_CMD=""
if [ -f "$LAST_CMD_FILE" ]; then
    LAST_CMD=$(cat "$LAST_CMD_FILE" 2>/dev/null || true)
fi

if [ "$CMD_CANON" != "$LAST_CMD" ]; then
    # Different command — reset streak, record this one
    printf '%s' "$CMD_CANON" > "$LAST_CMD_FILE"
    printf '%d' 1 > "$COUNTER_FILE"
    exit 0
fi

# Same as previous: increment streak counter
CURRENT=0
if [ -f "$COUNTER_FILE" ]; then
    CURRENT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    case "$CURRENT" in
        ''|*[!0-9]*) CURRENT=0 ;;
    esac
fi
CURRENT=$((CURRENT + 1))
printf '%d' "$CURRENT" > "$COUNTER_FILE"

if [ "${CC_SAME_CMD_REPEAT_QUIET:-}" = "1" ]; then
    if [ "$CURRENT" -ge "$THRESHOLD" ]; then
        exit 2
    fi
    exit 0
fi

if [ "$CURRENT" -ge "$THRESHOLD" ]; then
    # Truncate command for display (avoid floods on long commands)
    DISPLAY_CMD="$CMD_CANON"
    if [ "${#DISPLAY_CMD}" -gt 80 ]; then
        DISPLAY_CMD="${CMD_CANON:0:77}..."
    fi
    cat >&2 <<EOF

BLOCKED: This is the ${CURRENT}th consecutive identical Bash command.

Repeated command: ${DISPLAY_CMD}

Pattern detected: Opus 4.8 re-emits the same real (non-no-op) command
5–10 times in a row, apparently to compensate for perceived non-receipt
of the previous result. This is Cluster 25 axis 25F — same-command
repeat-execution. Unlike axis 25B (echo-probe spam) which burns mostly
display clutter, 25F burns actual CPU + wall-clock + build artefact
churn each iteration.

What to do instead:
  - If the previous result delivery failed: check the transcript for the
    earlier tool_result block before re-running. Re-running won't unstick
    the delivery layer.
  - If the previous result was genuinely empty: verify via a side effect
    that does not re-run the same command (git log, ls, status check).
  - If the previous result simply hasn't been processed yet: wait, do not
    re-emit.

Universal mitigation across Cluster 25 today: switch to Opus 4.7.
  export ANTHROPIC_MODEL=claude-opus-4-7

Anchor case: github.com/anthropics/claude-code/issues/63887 (@KamilDev,
"it decided to fire off a build command ten times in a row")

To override this block once: include "# RESET REPEAT" in the next command.
To disable: export CC_SAME_CMD_REPEAT_DISABLE=1
To adjust threshold: export CC_SAME_CMD_REPEAT_THRESHOLD=N (default 3)

EOF
    exit 2
fi

cat >&2 <<EOF

NOTICE: Detected ${CURRENT}/${THRESHOLD} consecutive identical Bash commands.
This shape is the Cluster 25 axis 25F same-command repeat-execution
compensation routine. Will block at ${THRESHOLD} consecutive occurrences.
Anchor: github.com/anthropics/claude-code/issues/63887

EOF

exit 0
