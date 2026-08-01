#!/bin/bash
# extended-thinking-loop-guard.sh — Hard-block a Cluster 13A resume when the
#   session is running under an autonomous-loop / headless-resume harness.
#
# Solves: the LMS927369 amplification reported in #63147 on 2026-05-29. The
#   well-known 13A wedge (transcript persists thinking blocks with
#   `thinking: ""` + retained `signature`, then resume re-sends them and the
#   API returns 400) is normally a one-time failure under interactive use.
#   Under `/loop`-style autonomous resume, the failure is instead an
#   *unrecoverable infinite loop*: the loop queues another continuation,
#   the latest assistant message is unchanged on disk, the next request
#   hits the same 400, and the loop never bails because the wedged turn
#   never gets past the API.
#
# Why a second hook (in addition to PR #445's advisory): the existing
#   extended-thinking-resume-warning.sh always exits 0 — it surfaces the
#   precursor to the operator's terminal but does not block the session
#   start. Under `/loop`, nobody is watching stderr in the moment, so a
#   non-blocking advisory does not break the loop. This hook is the
#   opt-in BLOCKING complement: when the operator declares "I am running
#   under an autonomous resume harness" via CC_LOOP_GUARD_ENABLED=1, the
#   hook scans the transcript on the disk and exits 2 with a decision
#   block if the 13A precursor is present. The blocking exit propagates
#   into the loop layer and breaks the retry cycle.
#
# Issue addressed: #63147 (central case), amplification reported by
#   LMS927369 (https://github.com/anthropics/claude-code/issues/63147#issuecomment-4571317923).
#   Field guide: https://gist.github.com/yurukusa/8c6be069f602399238356a9c9b719a45
#
# Default behavior: SILENT NO-OP. The hook exits 0 immediately unless
#   CC_LOOP_GUARD_ENABLED=1 is explicitly set. This makes it safe to drop
#   into a settings.json template that gets applied broadly — interactive
#   operators who do not set the env var see no change in behavior. Only
#   harnesses that opt in get the blocking semantics.
#
# Environment variables:
#   CC_LOOP_GUARD_ENABLED=1                — REQUIRED to arm the guard
#   CC_LOOP_GUARD_DISABLE=1                — kill switch (wins over enable)
#   CC_LOOP_GUARD_TRANSCRIPT=<path>        — override transcript path (test)
#   CC_LOOP_GUARD_FORCE=1                  — fire regardless of source (test)
#   CC_LOOP_GUARD_THRESHOLD=<N>            — minimum precursor blocks to
#                                            trigger (default 1)
#
# TRIGGER: SessionStart
# MATCHER: "" (filters event internally)
#
# Exit codes:
#   0 — safe to proceed (env disabled, no precursor, or non-resume source)
#   2 — BLOCK (precursor detected under armed guard); decision JSON on stderr

set -uo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-extended-thinking-loop-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [extended-thinking-loop-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)

# Kill switch wins.
[ "${CC_LOOP_GUARD_DISABLE:-0}" = "1" ] && exit 0

# Default behavior: not armed → silent no-op. This is the key safety
# property: dropping the hook into settings.json without setting the env
# var must not change behavior for interactive operators.
[ "${CC_LOOP_GUARD_ENABLED:-0}" = "1" ] || exit 0

EVENT=$(printf '%s' "$INPUT" | jq -r '.event // .hook_event_name // empty' 2>/dev/null)
case "$EVENT" in
    session_start|SessionStart|sessionstart) ;;
    *) exit 0 ;;
esac

# Only fire on resume/continue. A fresh `startup` cannot carry a stale
# precursor (no transcript yet). Unknown source defaults to scanning so
# new client versions that introduce new source labels stay covered.
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)
if [ "${CC_LOOP_GUARD_FORCE:-0}" != "1" ]; then
    case "$SOURCE" in
        resume|continue|"") ;;
        startup|fresh|new) exit 0 ;;
        *) ;;
    esac
fi

# Locate the transcript file. Same heuristic as PR #445 — recompute the
# Claude Code project slug from CC_PROJECT_DIR or PWD; if it doesn't
# resolve, fail open rather than blocking blindly.
LATEST="${CC_LOOP_GUARD_TRANSCRIPT:-}"
if [ -z "$LATEST" ]; then
    PROJ_DIR="${CC_PROJECT_DIR:-$PWD}"
    SLUG=$(printf '%s' "$PROJ_DIR" | sed 's|^/||; s|/|-|g')
    TRANSCRIPT_DIR="${HOME}/.claude/projects/${SLUG}"
    [ -d "$TRANSCRIPT_DIR" ] || exit 0
    LATEST=$(ls -t "$TRANSCRIPT_DIR"/*.jsonl 2>/dev/null | head -1)
fi
[ -n "$LATEST" ] || exit 0
[ -r "$LATEST" ] || exit 0

# Scan for empty-thinking + non-empty-signature blocks. Same shape as the
# PR #445 detector; the difference is what we do with the result.
SCAN=$(jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "thinking" and ((.thinking // "") | length) == 0 and ((.signature // "") | length) > 0) | (.signature | length)' "$LATEST" 2>/dev/null || true)

if [ -z "$SCAN" ]; then
    exit 0
fi

COUNT=$(printf '%s\n' "$SCAN" | grep -c .)
THRESHOLD="${CC_LOOP_GUARD_THRESHOLD:-1}"

if [ "$COUNT" -lt "$THRESHOLD" ]; then
    exit 0
fi

# Block. Emit decision JSON on stderr and exit 2. The decision payload is
# what Claude Code surfaces to the operator (and what an enclosing harness
# can grep for to identify the bail reason).
REASON="Cluster 13A precursor detected on disk (${COUNT} empty-text-signed thinking block(s) in ${LATEST}). Under autonomous loop, resuming this transcript would re-send the corrupted blocks, hit API 400 (\`thinking\` blocks cannot be modified), and the loop would replay indefinitely. Stopping the resume to break the loop. Recover by: (1) backing up the .jsonl, (2) stripping thinking/redacted_thinking blocks from assistant content arrays in-place (leave uuid/parentUuid chains intact), (3) clearing CC_LOOP_GUARD_ENABLED or setting CC_LOOP_GUARD_DISABLE=1 for the recovery session, then resuming. Reference: https://github.com/anthropics/claude-code/issues/63147 — Field guide: https://gist.github.com/yurukusa/8c6be069f602399238356a9c9b719a45"

# JSON-escape the reason field for the decision payload. Use jq for the
# escape so embedded backticks, quotes, slashes, etc. don't break the JSON.
DECISION=$(jq -nc --arg r "$REASON" '{decision:"block", reason:$r}' 2>/dev/null)

if [ -n "$DECISION" ]; then
    printf '%s\n' "$DECISION" >&2
else
    # jq unavailable for the escape — fall back to a plain-text reason.
    # Operators get the message; harness grep on "decision" may miss it.
    printf '[extended-thinking-loop-guard] BLOCK: %s\n' "$REASON" >&2
fi

exit 2
