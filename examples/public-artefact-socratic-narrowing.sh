#!/bin/bash
# public-artefact-socratic-narrowing.sh — Inject a Socratic-narrowing prompt
# at the public-artefact emission boundary, asking the agent to re-engage the
# gradient on decisions in the artefact before it ships.
#
# Solves: #60226 (the structural-parent frame) — recognition-without-arrest at
# the public-artefact emission boundary, as operationalized in @beq00000's
# clean-state worked example (#60226, 2026-05-19 comment).
#
# In that comment, seven instances of recognition-without-arrest surfaced in a
# single non-drifted session. Three of the seven were caught at the public-
# artefact emission boundary by the operator's Socratic-narrowing intervention:
#
#   "The form: not 'is this wrong' (binary question, eliciting binary defence),
#    but 'is this verifiable / already-documented / what-would-actually-need-
#    attention look like' (gradient question, forcing the model to re-engage
#    the rank ordering the original output had flattened). The first form gets
#    defended; the second gets re-decided."
#
# The operator-language form is implementable as session discipline today, but
# the gate fires only when the operator is present and noticing. This hook is
# the tooling-side form: PreToolUse on the public-artefact emission tools
# injects a Socratic-narrowing reminder at the boundary so the agent re-engages
# the gradient regardless of whether the operator is watching this turn.
#
# The hook deliberately does not check what the artefact says. Recognition-
# without-arrest cannot be solved by content classification (that is the
# failure mode being addressed). The gate's only job is to force one more
# pass over the artefact with the gradient framing applied. The agent's
# re-emission is what does the work.
#
# Related Issues / Reports:
#   #60226 (@suwayama, 2026-05-18) — recognition-without-arrest framework
#                  comment thread → @beq00000 2026-05-19 clean-state worked
#                  example with seven instances and the Socratic-narrowing
#                  mitigation
#   #60188 (@suwayama)             — binary-collapse subhypothesis; the
#                                    Socratic form re-introduces the gradient
#   #60506 (@zean89,   2026-05-19) — six-day drift across PR-body emissions
#                                    that survived multiple operator passes
#
# TRIGGER: PreToolUse
# MATCHER: Bash|Write|Edit
#
# HOW IT WORKS:
#   1. Reads PreToolUse input via stdin.
#   2. For Bash, matches the command against public-artefact emission patterns
#      (gh pr create/edit, gh issue create/comment, gh release create,
#      git commit -m '<long>', git tag -a, etc.).
#   3. For Write/Edit, matches the target path against public-artefact paths
#      (.github/, CHANGELOG.md, README*.md, docs/, sales-page*.md, etc.).
#   4. If the artefact body / file content is below a length threshold
#      (default 200 chars), allows it through silently — short artefacts are
#      not where the binary-collapse failure surfaces.
#   5. Computes a content hash of the artefact body. If the same hash was
#      seen within the cache window (default 600s), allows through — the
#      agent has already re-engaged the gradient on this content.
#   6. Otherwise emits a Socratic-narrowing system-reminder via stderr and
#      exits 2, blocking the emission until the agent re-emits.
#
# The hash-based cache is what makes the gate non-infinite. After the agent
# re-emits with the gradient applied (different content → new hash → re-fired
# once), or after deliberately re-emitting the same content (operator-
# approved → hash matches → passes through), the artefact ships.
#
# CONFIGURATION (environment variables):
#   CC_SOCRATIC_DISABLE             set to "1" to disable the gate entirely
#   CC_SOCRATIC_STATE_DIR           default /tmp/cc-socratic-cache
#   CC_SOCRATIC_BODY_MIN_CHARS      default 200 — artefacts shorter than this
#                                                  are not gated
#   CC_SOCRATIC_CACHE_TTL_SECONDS   default 600 — how long a hash counts as
#                                                  "already re-engaged"
#   CC_SOCRATIC_BASH_PATTERNS       default built-in — regex of Bash commands
#   CC_SOCRATIC_FILE_PATTERNS       default built-in — regex of file paths
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Bash|Write|Edit",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/public-artefact-socratic-narrowing.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-public-artefact-socratic-narrowing-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [public-artefact-socratic-narrowing]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

[ "${CC_SOCRATIC_DISABLE:-0}" = "1" ] && exit 0

# OPT-IN: this gate blocks every public-artefact emission (commits, PRs, docs
# edits) on first pass, which is high friction as a default. It is therefore
# off unless explicitly enabled. Set CC_SOCRATIC_ENABLE=1 to turn it on.
[ "${CC_SOCRATIC_ENABLE:-0}" = "1" ] || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

STATE_DIR="${CC_SOCRATIC_STATE_DIR:-/tmp/cc-socratic-cache}"
BODY_MIN_CHARS="${CC_SOCRATIC_BODY_MIN_CHARS:-200}"
CACHE_TTL="${CC_SOCRATIC_CACHE_TTL_SECONDS:-600}"

DEFAULT_BASH_PATTERNS='gh[[:space:]]+pr[[:space:]]+(create|edit)|gh[[:space:]]+issue[[:space:]]+(create|comment)|gh[[:space:]]+release[[:space:]]+create|gh[[:space:]]+gist[[:space:]]+create|git[[:space:]]+commit[[:space:]]+.*-m|git[[:space:]]+tag[[:space:]]+-a|git[[:space:]]+notes[[:space:]]+add'
DEFAULT_FILE_PATTERNS='(^|/)\.github/|(^|/)CHANGELOG(\.[a-z]+)?|(^|/)README[^/]*$|(^|/)docs?/|(^|/)sales-page|(^|/)launch-|(^|/)RELEASE|(^|/)NOTICE|(^|/)CITATION'

BASH_PATTERNS="${CC_SOCRATIC_BASH_PATTERNS:-$DEFAULT_BASH_PATTERNS}"
FILE_PATTERNS="${CC_SOCRATIC_FILE_PATTERNS:-$DEFAULT_FILE_PATTERNS}"

mkdir -p "$STATE_DIR" 2>/dev/null || true

# Extract tool name and input from the PreToolUse payload
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

ARTEFACT_BODY=""
ARTEFACT_KIND=""

case "$TOOL_NAME" in
    Bash)
        CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        [ -z "$CMD" ] && exit 0
        # Does the command match a public-artefact emission pattern?
        printf '%s' "$CMD" | grep -Eiq "$BASH_PATTERNS" || exit 0
        ARTEFACT_BODY="$CMD"
        ARTEFACT_KIND="bash-command"
        ;;
    Write)
        FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        [ -z "$FILE_PATH" ] && exit 0
        printf '%s' "$FILE_PATH" | grep -Eiq "$FILE_PATTERNS" || exit 0
        ARTEFACT_BODY=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
        ARTEFACT_KIND="file-write:$FILE_PATH"
        ;;
    Edit)
        FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        [ -z "$FILE_PATH" ] && exit 0
        printf '%s' "$FILE_PATH" | grep -Eiq "$FILE_PATTERNS" || exit 0
        ARTEFACT_BODY=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
        ARTEFACT_KIND="file-edit:$FILE_PATH"
        ;;
    *)
        exit 0
        ;;
esac

# Below threshold → not where the failure surfaces
BODY_LEN=${#ARTEFACT_BODY}
if [ "$BODY_LEN" -lt "$BODY_MIN_CHARS" ]; then
    exit 0
fi

# Hash the artefact body. If we have seen this hash recently, the agent has
# already had one Socratic-narrowing pass on it — allow through.
HASH=$(printf '%s' "$ARTEFACT_BODY" | sha256sum 2>/dev/null | awk '{print $1}')
[ -z "$HASH" ] && exit 0

CACHE_FILE="$STATE_DIR/$HASH"
NOW=$(date +%s)

if [ -f "$CACHE_FILE" ]; then
    CACHED_AT=$(cat "$CACHE_FILE" 2>/dev/null || echo 0)
    AGE=$((NOW - CACHED_AT))
    if [ "$AGE" -lt "$CACHE_TTL" ]; then
        # Same content within window → agent has re-engaged → ship it
        exit 0
    fi
fi

# Record the hash so the re-emission passes through
echo "$NOW" > "$CACHE_FILE"

# Best-effort cache eviction: drop entries older than 24h
find "$STATE_DIR" -type f -mmin +1440 -delete 2>/dev/null || true

# Emit the Socratic-narrowing reminder and block the emission once
cat >&2 <<EOF
<system-reminder>
PUBLIC-ARTEFACT EMISSION BOUNDARY — about to emit $ARTEFACT_KIND
($BODY_LEN chars). This is the boundary at which three of seven instances of
recognition-without-arrest surfaced in @beq00000's clean-state worked example
on #60226 (2026-05-19).

Before this artefact ships, re-engage the gradient on each decision in it.
The Socratic-narrowing form (per @beq00000) is the one that works:

  Not "is any of this wrong?" — that question elicits binary defence and
  the model defends the artefact as emitted.

  Instead, ask of each list / each claim / each register choice in the
  artefact:
    (a) What is the gradient this decision sits on?
        e.g. item-substantiveness, public-appropriateness, verifiable-vs-
        speculative, novel-vs-already-documented, gradient-flag-quality.
    (b) Which items in the artefact collapse into the substantive end of
        the gradient on second-pass review? Which collapse into the trivial
        end?
    (c) Reproduce the artefact with the gradient applied — keep what
        survives, drop or rephrase what does not.

Then re-emit. If the re-emitted artefact is structurally different from this
one, that is the gate working. If the re-emitted artefact is byte-identical
to this one and you have considered the gradient and stand by every decision,
re-running the same command within ${CACHE_TTL}s will ship it (the hash
matches and the gate passes through).

To disable this gate intentionally (for low-stakes commits, automated tooling,
non-public artefacts mis-classified as public), set CC_SOCRATIC_DISABLE=1 in
your environment, or refine CC_SOCRATIC_BASH_PATTERNS / CC_SOCRATIC_FILE_PATTERNS
to exclude the false-positive class.

Underlying mechanism (per @suwayama #60188): binary-collapse of decisions
that should sit on a gradient. The reminder above is the operator-language
intervention promoted to a tooling-side gate; the gradient framing is what
makes it work, not the blocking.
</system-reminder>
EOF

exit 2
