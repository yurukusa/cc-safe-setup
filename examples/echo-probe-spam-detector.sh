#!/bin/bash
# echo-probe-spam-detector.sh — Block Opus 4.8 echo-probe spam bursts
# (Cluster 25 candidate, axis 25B — tool-result delivery compensation)
#
# Background:
#   When the Bash tool's result delivery is slow or buffered, Opus 4.8 emits
#   bursts of no-op echo probe commands ("echo s1", "echo s2", ...,
#   sometimes "sleep N; echo x") between real commands, apparently to coax
#   buffered output to flush. Dozens per turn bury the actual work, clutter
#   the screen, and burn tokens. The behaviour started after the Opus 4.8
#   upgrade and was not present on prior model versions.
#
#   Anchor case:
#     #63887 — Agent spams no-op echo probe commands to flush shell output
#              (14 reactions, Opus 4.8 + v2.1.156+ regression)
#
#   Cost-side sibling:
#     #64343 — Excessive token consumption from repeated echo tool calls
#              ("burned my tokens on hundreds of echo calls")
#
#   Cluster 25 axes (4 sub-clusters + 1 overlap):
#     25A — late/empty tool-result delivery (substrate)
#     25B — echo-probe spam compensation (this hook)
#     25C — 2>&1 permission-engine fragmentation hang
#     25D — compounding cost (downstream of 25B/25C)
#     25E — empty-result triggered fabrication (Cluster 22 overlap)
#
#   This hook is a PreToolUse hook on Bash that:
#     - Matches the echo-probe spam shapes (echo s\d+, echo with one-char
#       trivial arg, sleep N; echo *)
#     - Tracks consecutive probe-shaped commands per session
#     - Warns on first probe-shaped command
#     - Blocks (exit 2) on the third consecutive probe-shaped command
#
#   The threshold-and-escalate shape is what works against compensation-
#   routine bursts that are not stopped by warnings alone — the model needs
#   to be forced to re-evaluate, not just nudged.
#
# When this hook does NOT block:
#   - CC_ECHO_PROBE_DISABLE=1                  — never warn or block
#   - CC_ECHO_PROBE_QUIET=1                    — silent (no stderr output)
#   - CC_ECHO_PROBE_THRESHOLD=N                — block after N consecutive (default 3)
#   - the Bash command is not probe-shaped     — exit 0
#   - the operator has reset the counter via `# RESET ECHO PROBE` echo comment
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/echo-probe-spam-detector.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_ECHO_PROBE_DISABLE=1   — never warn or block
#   CC_ECHO_PROBE_QUIET=1     — silent (process but never write to stderr)
#   CC_ECHO_PROBE_THRESHOLD=N — block at N consecutive probes (default 3)

set -u

if [ "${CC_ECHO_PROBE_DISABLE:-}" = "1" ]; then
    exit 0
fi

THRESHOLD="${CC_ECHO_PROBE_THRESHOLD:-3}"
STATE_DIR="${TMPDIR:-/tmp}/cc-echo-probe-spam-detector"
mkdir -p "$STATE_DIR"
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
COUNTER_FILE="$STATE_DIR/${SESSION_ID}.counter"

INPUT=$(cat 2>/dev/null || true)
CMD=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
fi

if [ -z "$CMD" ]; then
    exit 0
fi

# Strip leading/trailing whitespace
CMD_TRIM=$(printf '%s' "$CMD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Detect probe shapes:
#  1. "echo s\d+"        — the canonical #63887 burst pattern
#  2. "echo <1-3 chars>"  — generic short throwaway
#  3. "sleep <N>; echo *" — wrapped flush attempt
is_probe_shape() {
    local c="$1"
    # echo s\d+ pattern (s followed by digits, no other args)
    if printf '%s\n' "$c" | grep -Eq '^echo[[:space:]]+s[0-9]+[[:space:]]*$'; then
        return 0
    fi
    # echo <very short single arg> pattern (1-3 chars, no special meaning)
    if printf '%s\n' "$c" | grep -Eq '^echo[[:space:]]+[a-zA-Z0-9._-]{1,3}[[:space:]]*$'; then
        return 0
    fi
    # sleep N; echo ... pattern
    if printf '%s\n' "$c" | grep -Eq '^sleep[[:space:]]+[0-9.]+[[:space:]]*;[[:space:]]*echo[[:space:]]'; then
        return 0
    fi
    return 1
}

# Check for reset signal embedded in the command (operator override)
if printf '%s\n' "$CMD_TRIM" | grep -Eq '#[[:space:]]*RESET ECHO PROBE'; then
    rm -f "$COUNTER_FILE"
    exit 0
fi

if ! is_probe_shape "$CMD_TRIM"; then
    # Non-probe command resets the streak
    rm -f "$COUNTER_FILE"
    exit 0
fi

# Probe-shaped: increment counter
CURRENT=0
if [ -f "$COUNTER_FILE" ]; then
    CURRENT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    # Validate it's a number
    case "$CURRENT" in
        ''|*[!0-9]*) CURRENT=0 ;;
    esac
fi
CURRENT=$((CURRENT + 1))
printf '%d' "$CURRENT" > "$COUNTER_FILE"

if [ "${CC_ECHO_PROBE_QUIET:-}" = "1" ]; then
    if [ "$CURRENT" -ge "$THRESHOLD" ]; then
        exit 2
    fi
    exit 0
fi

if [ "$CURRENT" -ge "$THRESHOLD" ]; then
    cat >&2 <<EOF

BLOCKED: This is the ${CURRENT}th consecutive echo-probe-shaped Bash command.

Pattern detected: Opus 4.8 emits bursts of "echo s1, echo s2, ..." or
"sleep N; echo x" to flush suspected buffered output. This is Cluster 25
axis 25B — a compensation routine for tool-result delivery delay that
burns tokens without doing user-visible work.

What to do instead:
  - If you genuinely need to flush output: run the real command once and
    wait for its result; tolerate shell latency.
  - If you are waiting on async work: use a single backgrounded command
    with a real completion signal — never a burst of no-op echoes.
  - If the tool-result really did come back empty: verify via side effect
    (git log, ls, etc.) rather than retrying or probing.

Background: gist.github.com/yurukusa/5881286479969d5bac0323511dc33ab2
Anchor issue: github.com/anthropics/claude-code/issues/63887

To override this block once: include "# RESET ECHO PROBE" in the next command.
To disable: export CC_ECHO_PROBE_DISABLE=1
To adjust threshold: export CC_ECHO_PROBE_THRESHOLD=N (default 3)

EOF
    exit 2
fi

cat >&2 <<EOF

NOTICE: Detected echo-probe-shaped Bash command (${CURRENT}/${THRESHOLD}).
This shape (echo s\d+ / short single-arg echo / sleep; echo) is the
Cluster 25 axis 25B compensation routine. Will block at ${THRESHOLD}
consecutive occurrences. See gist 5881286479969d5bac0323511dc33ab2.

EOF

exit 0
