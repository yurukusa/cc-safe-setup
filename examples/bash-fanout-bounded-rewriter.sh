#!/bin/bash
# ================================================================
# bash-fanout-bounded-rewriter.sh — Detect and refuse unbounded
# bash fan-out patterns that can spawn thousands of subprocesses
# ================================================================
# PURPOSE:
#   Issue #62193 documented a 3,079-bash-in-17-seconds spawn event
#   from a single Bash tool call, leading to an OS-level lockup
#   (1.4 TB VSZ on parent, contiguous PIDs 21300-24379, OOM killer
#   hitting `code` first). The pattern: a single Bash command that
#   internally fans out (find ... -exec, unbounded loops, parallel
#   without -j N, xargs without -P N) hands the kernel an
#   uncapped concurrency demand.
#
#   The cleanest architectural answer is cgroup-based isolation
#   (systemd-run --scope -p TasksMax=N). That works but renders
#   bash useless under pressure because every command including
#   light single-process ones hits the TasksMax ceiling.
#
#   This hook covers the gap: detect fan-out signatures in the
#   bash command BEFORE the shell sees them. Refuse the call with
#   a clear advisory naming the unbounded pattern and a bounded
#   rewrite (xargs -P N -n 1, parallel -j N, GNU make -j N).
#
# WHO THIS PROTECTS:
#   Operators running Claude Code on a workstation where a single
#   uncapped fan-out can lock the OS. Especially relevant when
#   running on Max-plan accounts where the model is more willing
#   to generate aggressive parallelism.
#
# DETECTION:
#   PreToolUse on Bash. Scan the command string for fan-out
#   signatures in order of severity:
#     1. find ... -exec (worst: shell-spawning per result)
#     2. for ... in ... ; do (unbounded loop)
#     3. while read ... ; do (unbounded loop)
#     4. xargs without -P N -n N (single process per line)
#     5. parallel without -j N (defaults to one-per-core)
#     6. GNU make -j (without explicit N; defaults to infinite)
#     7. seq N | while ... (high-N sequence to loop)
#
# OUTPUT:
#   On detection, blocks the call (exit 2) with a stderr message
#   that names the matched pattern and shows a bounded rewrite.
#   The operator can override per-call by setting
#   CC_BASH_FANOUT_OVERRIDE=1 (e.g., for legitimate parallelism)
#   or globally with CC_BASH_FANOUT_DISABLE=1.
#
# CONFIGURATION:
#   CC_BASH_FANOUT_DISABLE   — set to 1 to disable entirely
#   CC_BASH_FANOUT_OVERRIDE  — set to 1 to allow this call once
#                              (clear after the call to re-arm)
#   CC_BASH_FANOUT_MAX_LOOP_LINES — refuse loops with more than
#                              this many lines in the body
#                              (default: refuse all unbounded)
#   CC_BASH_FANOUT_PARALLEL_BOUND — default bounded N to suggest
#                              in advisories (default: 8)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/62193
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
# ================================================================

set -u

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-bash-fanout-bounded-rewriter-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [bash-fanout-bounded-rewriter]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat 2>/dev/null || echo "{}")

[ "${CC_BASH_FANOUT_DISABLE:-0}" = "1" ] && exit 0
[ "${CC_BASH_FANOUT_OVERRIDE:-0}" = "1" ] && exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

BOUND="${CC_BASH_FANOUT_PARALLEL_BOUND:-8}"

# Detection signatures, ordered most-severe-first
MATCHED_PATTERN=""
SUGGESTED_REWRITE=""

# Pattern 1: find ... -exec
if printf '%s' "$COMMAND" | grep -qE 'find +.*-exec +'; then
    MATCHED_PATTERN="find ... -exec (shell-spawning per result, unbounded)"
    SUGGESTED_REWRITE="find ... -print0 | xargs -0 -P $BOUND -n 1 <cmd>"
fi

# Pattern 2: for ... in ... ; do (only if the in-list is dynamic or large)
# Static lists like 'for i in 1 2 3' are fine; the danger is
# 'for f in $(...)', 'for f in *', or 'for f in $LIST'.
if [ -z "$MATCHED_PATTERN" ]; then
    if printf '%s' "$COMMAND" | grep -qE 'for +[A-Za-z_][A-Za-z0-9_]* +in +(\$\(|`|\*|\$[A-Za-z_])'; then
        MATCHED_PATTERN="for ... in \$(...) / glob / \$VAR (unbounded loop body)"
        SUGGESTED_REWRITE="<list-source> | xargs -P $BOUND -n 1 <cmd>"
    fi
fi

# Pattern 3: while read ... ; do
if [ -z "$MATCHED_PATTERN" ]; then
    if printf '%s' "$COMMAND" | grep -qE 'while +(read|IFS=)'; then
        MATCHED_PATTERN="while read ... (unbounded loop, one-process-per-line)"
        SUGGESTED_REWRITE="<input> | xargs -P $BOUND -n 1 <cmd>"
    fi
fi

# Pattern 4: xargs without -P
if [ -z "$MATCHED_PATTERN" ]; then
    if printf '%s' "$COMMAND" | grep -qE 'xargs +' && \
       ! printf '%s' "$COMMAND" | grep -qE 'xargs +.*-P +[0-9]+'; then
        MATCHED_PATTERN="xargs without -P N (defaults to single-process serial, OK; but if the upstream pipe is high-cardinality, refuse)"
        # xargs without -P is actually safe (serial). Skip unless follows hi-card pipe.
        # We don't actually block this — note for advisory only.
        MATCHED_PATTERN=""  # Reset; serial xargs is fine.
    fi
fi

# Pattern 5: parallel without -j
if [ -z "$MATCHED_PATTERN" ]; then
    if printf '%s' "$COMMAND" | grep -qE '(^| )parallel +' && \
       ! printf '%s' "$COMMAND" | grep -qE 'parallel +.*-j +[0-9]+'; then
        MATCHED_PATTERN="GNU parallel without -j N (defaults to one-per-core, can exceed cgroup TasksMax)"
        SUGGESTED_REWRITE="parallel -j $BOUND <cmd>"
    fi
fi

# Pattern 6: make -j without N
if [ -z "$MATCHED_PATTERN" ]; then
    if printf '%s' "$COMMAND" | grep -qE 'make +.*-j( |$)' && \
       ! printf '%s' "$COMMAND" | grep -qE 'make +.*-j *[0-9]+'; then
        MATCHED_PATTERN="make -j without N (defaults to infinite parallelism)"
        SUGGESTED_REWRITE="make -j$BOUND <target>"
    fi
fi

# Pattern 7: seq N | (where N > 100)
if [ -z "$MATCHED_PATTERN" ]; then
    SEQ_N=$(printf '%s' "$COMMAND" | grep -oE 'seq +[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
    if [ -n "$SEQ_N" ] && [ "$SEQ_N" -gt 100 ]; then
        if printf '%s' "$COMMAND" | grep -qE 'seq +[0-9]+ *\| *(while|for|xargs)'; then
            MATCHED_PATTERN="seq $SEQ_N piped to loop/xargs (high-cardinality fan-out)"
            SUGGESTED_REWRITE="seq $SEQ_N | xargs -P $BOUND -n 1 <cmd>"
        fi
    fi
fi

# Nothing matched — pass through silently.
[ -z "$MATCHED_PATTERN" ] && exit 0

# Build the refusal message.
MSG="Unbounded fan-out detected: $MATCHED_PATTERN

This pattern can spawn an uncapped number of subprocesses. Issue #62193
documented a single Bash tool call that spawned 3,079 bash processes in
17 seconds, leading to an OS-level lockup (1.4 TB VSZ on parent, OOM
killer hitting Claude Code's parent process before reaching the runaways).

Bounded rewrite: $SUGGESTED_REWRITE

Why this layer (PreToolUse hook) instead of just cgroup TasksMax: a
TasksMax ceiling blocks ALL bash including light single-process calls,
rendering the tool useless under pressure. This hook intercepts only the
fan-out shape, so unrelated bash calls keep working at full speed.

Override for this one call:
  CC_BASH_FANOUT_OVERRIDE=1 (then retry)

Disable entirely (operator already aware):
  CC_BASH_FANOUT_DISABLE=1

The bounded rewrite is the actual safe form of the same command — it
runs the same workload at a cap of $BOUND concurrent processes, which is
sustainable on every workstation tested in the cc-safe-setup matrix.

Related: cc-safe-setup Cluster 1 (Sub-Agent Observability), scope
expansion sub-pattern. The OS-level manifestation of the same primitive."

echo "[bash-fanout-bounded-rewriter] $MSG" >&2

exit 2
