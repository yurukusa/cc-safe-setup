#!/bin/bash
# api-busyloop-guard.sh — Stop a single Bash command that busy-polls a
#                         rate-limited API in an unbounded loop with no delay
#
# Solves: When asked to "wait for the CI run", the model reaches for a generic
# shell poll instead of the purpose-built command, e.g.
#
#     until gh run view <run-id> 2>&1 | grep -q "completed"; do true; done
#
# `do true; done` spins as fast as the shell allows, calling `gh` (the GitHub
# REST API) hundreds of times a minute. In #65985 this drained the 5,000 req/h
# limit to 0/5000 within minutes and blocked every gh command for the rest of
# the hour. Worse, the loops were started in the background and kept running
# silently after the session moved on — nothing cleaned them up. The same shape
# hammers any rate-limited CLI (curl/wget/aws/gcloud/kubectl) the same way.
#
# Existing hooks miss this exact shape:
#   - loop-detector.sh keys on the *same command* repeating across separate tool
#     calls. Here the loop lives *inside one* Bash command, so the hook sees it
#     only once and never trips.
#   - api-rate-limit-guard.sh / api-rate-limit-tracker.sh only match curl/wget/
#     http and likewise count *separate* tool calls — an internal shell loop is
#     a single call to them, and `gh` is not even in their match set.
#   - unbounded-output-guard.sh stops infinite *output* generators (yes, cat
#     /dev/zero), not API busy-loops.
#   - webfetch-runaway-guard.sh counts the WebFetch *tool*, not Bash loops.
#
# Why two precision levels (so legitimate loops are not blocked):
#   block (default) fires ONLY on the unambiguous busy-wait signature — an
#     unbounded while/until/for((;;)) loop whose body is a no-op (true / : /
#     continue / sleep 0) that calls a rate-limited CLI with no real sleep.
#     A no-op-body poll has essentially no legitimate use: a real wait always
#     sleeps. This is exactly the #65985 incident.
#   warn (stderr, non-blocking) fires on the broader shape — any unbounded
#     while/until/for((;;)) loop calling such a CLI with no sleep — because a
#     counter-bounded loop can look the same to a pattern match and we would
#     rather nudge than wrongly block it.
#   Bounded loops are left completely alone: `for x in <list>` and `while read`
#     (stream/file consumption) terminate on their own, and any loop that
#     already sleeps or already uses `gh run watch` is the correct form.
#
# The right fix, surfaced in the message:
#   - For GitHub Actions: `gh run watch <run-id> --exit-status` streams status,
#     exits on completion/failure/cancel, and makes efficient API use — no loop.
#   - For any poll: put a `sleep N` in the body plus a terminal-state or
#     max-iteration exit so it cannot spin forever or linger in the background.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Config (all optional):
#   CC_API_BUSYLOOP_GUARD=block   block | warn | off   (default: block)
# Related: https://github.com/anthropics/claude-code/issues/65985

INPUT=$(cat)

MODE="${CC_API_BUSYLOOP_GUARD:-block}"
[ "$MODE" = "off" ] && exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# 1. An unbounded loop construct: while / until (condition loops = the classic
#    poll) or a C-style for ((...)). `for x in <list>` is bounded, so excluded.
echo "$COMMAND" | grep -qE '(^|[^[:alnum:]_])(while|until)([^[:alnum:]_]|$)' \
  || echo "$COMMAND" | grep -qE 'for[[:space:]]*\(\(' \
  || exit 0

# 2. Bounded stream/file consumption (`while read ... done < file`) terminates
#    at EOF — not a poll. Leave it alone.
echo "$COMMAND" | grep -qE '(while|until)[^;]*\bread\b' && exit 0

# 3. A rate-limited network CLI somewhere in the command.
echo "$COMMAND" | grep -qE '(^|[^[:alnum:]_./-])(gh|curl|wget|aws|gcloud|kubectl)[[:space:]]' || exit 0

# 4. Already throttled? A positive sleep, or the purpose-built gh run watch,
#    means this is the correct form — allow it.
echo "$COMMAND" | grep -qE '\bsleep[[:space:]]+([1-9][0-9]*|[0-9]*\.[0-9]*[1-9])' && exit 0
echo "$COMMAND" | grep -qE '\bgh[[:space:]]+run[[:space:]]+watch\b' && exit 0

# Tailor the fix hint to the CLI in play.
if echo "$COMMAND" | grep -qE '(^|[^[:alnum:]_./-])gh[[:space:]]'; then
    FIX="Use 'gh run watch <run-id> --exit-status': it streams status, exits automatically on completion/failure/cancel, and makes one efficient call instead of a busy poll. GitHub's REST limit is 5,000 req/h and a no-delay loop can drain it to 0 in minutes (#65985)."
else
    FIX="Add a 'sleep N' inside the loop body and a terminal-state or max-iteration exit, or use the tool's own blocking/wait subcommand. A no-delay loop hammers the API's rate limit and, if backgrounded, keeps running unnoticed (#65985)."
fi

# The unambiguous busy-wait signatures, either of which has essentially no
# legitimate no-sleep form:
#   (a) a no-op / empty loop body (true / : / continue / sleep 0), or
#   (b) an explicitly infinite loop (while true | while : | until false |
#       for ((;;))), which never terminates on its own.
# A counter- or condition-bounded loop (e.g. `while [ $n -lt 5 ]`) matches
# neither and only warns.
BUSY=0
if echo "$COMMAND" | grep -qE 'do[[:space:]]+(true|:|continue|sleep[[:space:]]+0)[[:space:]]*;?[[:space:]]*done' \
   || echo "$COMMAND" | grep -qE 'do[[:space:]]*;[[:space:]]*done' \
   || echo "$COMMAND" | grep -qE 'while[[:space:]]+(true|:)([^[:alnum:]_]|$)' \
   || echo "$COMMAND" | grep -qE 'until[[:space:]]+false([^[:alnum:]_]|$)' \
   || echo "$COMMAND" | grep -qE 'for[[:space:]]*\(\([[:space:]]*;[[:space:]]*;[[:space:]]*\)\)'; then
    BUSY=1
fi

MSG="This command busy-polls a rate-limited API in an unbounded loop with no delay. $FIX Set CC_API_BUSYLOOP_GUARD=warn to only warn, or =off to disable."

if [ "$MODE" = "block" ] && [ "$BUSY" -eq 1 ]; then
    echo "api-busyloop-guard: $MSG" >&2
    exit 2
fi

# Broader shape, or warn mode: nudge without blocking.
echo "api-busyloop-guard: $MSG" >&2
exit 0
