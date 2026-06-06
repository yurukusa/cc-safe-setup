#!/bin/bash
# git-push-blast-radius-guard.sh — Cap a runaway fan-out of git pushes that burns CI minutes
#
# Solves: When a bug touches many open PRs, the agent can "fix each branch
# individually" — cherry-pick the same change onto branch after branch and push
# each one. Every push to a distinct branch triggers the full CI suite, so the
# cost scales with the number of branches, not the size of the fix. In #65944 a
# 1-line lint fix was pushed to 13 PR branches across 3 rounds (~150+ workflow
# runs), exhausting the entire 2,000-minute monthly GitHub Actions allotment in
# under 3 hours and tripping an account-level Actions block. The operator's own
# root-cause note: the correct shape was "fix once on main, let PRs inherit it
# via rebase — 1 CI run instead of 150+."
#
# Existing hooks miss this exact shape:
#   - git-operations-require-approval.sh blocks *every* git push (all-or-nothing,
#     off by default); it never counts how many distinct branches a session has
#     pushed, so it can't tell a normal 1-branch push from a 13-branch fan-out.
#   - same-command-repeat-detector.sh keys on the *same* command repeating; a
#     fan-out pushes a *different* branch each time, so it never matches (the
#     same blind spot loop-detector.sh had before webfetch-runaway-guard.sh).
#   - tool-call-rate-limiter.sh counts *all* tool calls in a short window; pushes
#     spread across hours slip under it and it cannot see "distinct branches."
#   - parallel-batch-size-limiter.sh measures *concurrent* batches, not sequential
#     pushes to many branches across rounds.
#
# This counts the SET of distinct branches pushed in a rolling per-session window
# and, once that set crosses a threshold, surfaces the fix-on-main-then-rebase
# pattern and (by default) blocks the next branch push — the confirmation the
# operator wished for ("shouldn't push to more than 2-3 branches without
# confirmation"). The block is recoverable: raise the threshold, switch to warn,
# or set off. Re-pushing the *same* branch never inflates the count, so an
# ordinary edit-push-edit-push loop on one feature branch is untouched; only a
# genuine multi-branch fan-out trips it. `git push --all` / `--mirror` pushes
# every local branch at once (maximum blast radius) and is treated as a trip
# immediately.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Config (all optional):
#   CC_PUSH_BLAST_GUARD=block     block | warn | off
#   CC_PUSH_BLAST_BLOCK=6         block once this many distinct branches fall in the window
#   CC_PUSH_BLAST_WARN=3          warn (stderr, non-blocking) at this many
#   CC_PUSH_BLAST_WINDOW=3600     rolling window in seconds (default 1 hour)
#   CC_PUSH_BLAST_DIR             state dir (default: /tmp/cc-push-blast)
# Related: https://github.com/anthropics/claude-code/issues/65944

INPUT=$(cat)

MODE="${CC_PUSH_BLAST_GUARD:-block}"
[ "$MODE" = "off" ] && exit 0

# Only act on Bash. Fail open on anything unexpected.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Bash" ] && exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Quick reject: nothing to do unless the command runs `git push` somewhere.
printf '%s' "$COMMAND" | grep -qE '\bgit\s+push\b' || exit 0

BLOCK_AT="${CC_PUSH_BLAST_BLOCK:-6}"
WARN_AT="${CC_PUSH_BLAST_WARN:-3}"
WINDOW="${CC_PUSH_BLAST_WINDOW:-3600}"
case "$BLOCK_AT" in ''|*[!0-9]*) exit 0;; esac
case "$WARN_AT" in ''|*[!0-9]*) exit 0;; esac
case "$WINDOW" in ''|*[!0-9]*) exit 0;; esac

# Key state per session so one session's work never trips another's guard.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
case "$SID" in ''|*[!A-Za-z0-9_-]*) SID="default";; esac

# ---- Work out which branch(es) this command pushes to --------------------
# A command may chain several segments (&&, ;, newline, |). Inspect each git
# push segment and collect the branch name(s) it targets. Unknown/odd shapes
# fail open (they simply contribute nothing rather than guessing wrong).
FANOUT=0          # set when --all/--mirror pushes every branch at once
declare -a BRANCHES=()

# Split into segments on shell separators so each `git push ...` is seen alone.
SEGMENTS=$(printf '%s' "$COMMAND" | tr '\n;|' '\n\n\n' | sed 's/&&/\n/g')

while IFS= read -r seg; do
    printf '%s' "$seg" | grep -qE '\bgit\s+push\b' || continue

    # Whole-repo fan-out: one command, every branch, maximum CI blast radius.
    if printf '%s' "$seg" | grep -qE '\bgit\s+push\b.*(--all|--mirror)\b'; then
        FANOUT=1
        continue
    fi

    # Tokens after the word `push`. Drop flags and flag values we don't need.
    after=$(printf '%s' "$seg" | sed -E 's/.*\bgit[[:space:]]+push[[:space:]]*//')
    # shellcheck disable=SC2206
    toks=( $after )

    refspecs=()
    seen_remote=0
    i=0
    while [ "$i" -lt "${#toks[@]}" ]; do
        t="${toks[$i]}"
        i=$((i + 1))
        case "$t" in
            # Flags that take a separate value -> skip the value too.
            --repo|-o|--push-option|--receive-pack|--exec)
                i=$((i + 1)); continue ;;
            -*) continue ;;          # any other flag
        esac
        # First bare token is the remote (origin / upstream / a URL). After that,
        # bare tokens are refspecs (branches).
        if [ "$seen_remote" -eq 0 ]; then
            seen_remote=1
            continue
        fi
        refspecs+=("$t")
    done

    if [ "${#refspecs[@]}" -eq 0 ]; then
        # `git push` / `git push origin` with no refspec -> current branch.
        cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        [ -n "$cur" ] && [ "$cur" != "HEAD" ] && BRANCHES+=("$cur")
        continue
    fi

    for r in "${refspecs[@]}"; do
        # Strip a leading '+' (force) and take the destination side of any colon.
        r="${r#+}"
        dst="${r##*:}"
        # Ignore tag/ref deletions and empty sources.
        [ -z "$dst" ] && continue
        case "$dst" in
            HEAD) cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
                  [ -n "$cur" ] && [ "$cur" != "HEAD" ] && BRANCHES+=("$cur"); continue ;;
        esac
        BRANCHES+=("$dst")
    done
done <<EOF
$SEGMENTS
EOF

# Nothing identifiable and not a fan-out: fail open.
if [ "$FANOUT" -eq 0 ] && [ "${#BRANCHES[@]}" -eq 0 ]; then
    exit 0
fi

# ---- Record into the rolling per-session window --------------------------
STATE_DIR="${CC_PUSH_BLAST_DIR:-/tmp/cc-push-blast}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE="$STATE_DIR/$SID"

NOW=$(date +%s)
CUTOFF=$((NOW - WINDOW))

# Append "<ts>\t<branch>" for every branch this command pushes.
for b in "${BRANCHES[@]}"; do
    # Sanitise tab/newline out of the branch name for the state file.
    safe=$(printf '%s' "$b" | tr -d '\t\n')
    [ -n "$safe" ] && printf '%s\t%s\n' "$NOW" "$safe" >> "$STATE" 2>/dev/null
done

# Prune entries older than the window.
if [ -f "$STATE" ]; then
    awk -F'\t' -v c="$CUTOFF" '$1 ~ /^[0-9]+$/ && $1 >= c' "$STATE" > "$STATE.tmp" 2>/dev/null && mv "$STATE.tmp" "$STATE" 2>/dev/null
fi

# Count DISTINCT branches inside the window.
if [ -f "$STATE" ]; then
    DISTINCT=$(awk -F'\t' '{print $2}' "$STATE" 2>/dev/null | sort -u | grep -c .)
else
    DISTINCT=0
fi
case "$DISTINCT" in ''|*[!0-9]*) DISTINCT=0;; esac

# A whole-repo fan-out is an immediate trip regardless of the counter.
TRIP=0
[ "$FANOUT" -eq 1 ] && TRIP=1
[ "$DISTINCT" -ge "$BLOCK_AT" ] && TRIP=1

MINS=$((WINDOW / 60))
if [ "$FANOUT" -eq 1 ]; then
    SUBJECT="This 'git push --all/--mirror' pushes every local branch at once"
else
    SUBJECT="This makes ${DISTINCT} distinct branches pushed within ${MINS} min"
fi
MSG="${SUBJECT}. Each branch push triggers the full CI suite, so cost scales with branch count: in #65944 a 1-line fix pushed across 13 branches ran ~150+ workflow runs and burned the entire 2,000-minute monthly GitHub Actions allotment in under 3 hours. If you are applying one fix to many branches, stop and use the cheap shape instead: commit the fix once on main (or a single branch), merge it, and let the other branches inherit it via rebase/merge — 1 CI run instead of one per branch. To proceed anyway, raise CC_PUSH_BLAST_BLOCK, set CC_PUSH_BLAST_GUARD=warn to only warn, or =off to disable. State resets after ${WINDOW}s of no pushes: ${STATE}"

if [ "$TRIP" -eq 1 ]; then
    if [ "$MODE" = "warn" ]; then
        echo "git-push-blast-radius-guard: $MSG" >&2
        exit 0
    fi
    # block (default): structured decision so the model sees the reason.
    jq -n --arg r "$MSG" '{decision: "block", reason: $r}'
    exit 0
elif [ "$DISTINCT" -ge "$WARN_AT" ]; then
    echo "git-push-blast-radius-guard: ${DISTINCT} distinct branches pushed within ${MINS} min — each push triggers CI; consider fix-on-main + rebase if applying one change to many branches (#65944). Blocks at ${BLOCK_AT}." >&2
fi

exit 0
