#!/bin/bash
# multi-file-plan-routing-gate.sh — Refuse Write/Edit when the current session
# has touched N or more distinct files without a written plan, route the
# work through plan-mode before further writes land.
#
# Solves: #60506 — supplier-side recommendation #7 in the model's first-person
# self-report:
#
#   "Automatic routing of three-or-more-file changes into a plan-mode path.
#    Currently I can sprawl across the codebase without writing a plan first.
#    The hook should refuse the third file-touching Write until a plan exists,
#    and then enforce the plan as the contract for the remaining touches."
#
# This is the seventh and final operator-side implementation of the seven
# recommendations Semih extracted from claude-opus-4-7's self-report. The
# preceding six are shipped or in PR:
#
#   1. Chain templates as architectural rules → CLAUDE.md hook frameworks
#   2. Drift detector (3-correction repeat)   → same-correction-arrest.sh
#   3. Failure-mode re-injection at Write     → claude-md-reinjector.sh
#   4. Closure-word verification gate         → closure-word-verify-gate.sh
#   5. Evidence requirements for "tested"     → evidence-claim-gate.sh (PR #256)
#   6. Apology weighting at training time     → supplier-only
#   7. THIS HOOK — plan-mode routing for 3+ file changes
#
# HOW IT WORKS:
#   1. Tracks distinct file_path values per session in a small state file.
#   2. On each PreToolUse Write/Edit/MultiEdit, adds the file_path to the
#      session's set.
#   3. When the count reaches CC_PLAN_GATE_THRESHOLD (default 3), checks
#      for the presence of a plan file at $PLAN_DIR/<session>.md.
#   4. If no plan file exists, refuses the Write with exit 2 + system reminder
#      asking the assistant to write the plan first.
#   5. Once the plan file appears, subsequent writes pass through silently.
#   6. Stale session state (older than 7 days) is purged automatically.
#
# DESIGN PRINCIPLE: don't block the work, route it. The hook does not
# prevent multi-file changes; it requires that they be planned before being
# executed. The plan file is the contract; the writes are the contract's
# fulfillment. The arrest happens at the *third* file (configurable), not
# the first — single-file and two-file changes are common and not the
# failure mode #60506 is describing.
#
# Related Issues:
#   #60506 (@zean89,   2026-05-19) — original report, recommendation 7
#   #60226 (@suwayama, 2026-05-18) — recognition-without-arrest framework
#   #60177 (@mike-prokhorov)       — twelve days, fifty-one commits, no plan
#
# TRIGGER: PreToolUse
# MATCHER: Write|Edit|MultiEdit
#
# CONFIGURATION (environment variables):
#   CC_PLAN_GATE_THRESHOLD     default 3 — file count that triggers the gate
#   CC_PLAN_GATE_STATE_DIR     default /tmp/cc-plan-gate
#   CC_PLAN_GATE_PLAN_DIR      default .claude/plans
#   CC_PLAN_GATE_DISABLE       set to "1" to disable the gate entirely
#   CC_PLAN_GATE_STATE_TTL     default 7 (days) — stale state cleanup window
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Write|Edit|MultiEdit",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/multi-file-plan-routing-gate.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_PLAN_GATE_DISABLE:-0}" = "1" ] && exit 0

# OPT-IN: this gate BLOCKS the 3rd+ file Write/Edit in a session when no plan
# file exists. Ordinary multi-file work (refactors, features touching 3+ files)
# would be arrested by default, so it is off unless explicitly enabled.
# Set CC_PLAN_GATE_ENABLE=1 to turn it on.
[ "${CC_PLAN_GATE_ENABLE:-0}" = "1" ] || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

THRESHOLD="${CC_PLAN_GATE_THRESHOLD:-3}"
STATE_DIR="${CC_PLAN_GATE_STATE_DIR:-/tmp/cc-plan-gate}"
PLAN_DIR="${CC_PLAN_GATE_PLAN_DIR:-.claude/plans}"
TTL_DAYS="${CC_PLAN_GATE_STATE_TTL:-7}"

mkdir -p "$STATE_DIR" 2>/dev/null || true

# Stale state cleanup. Purge session files older than TTL_DAYS.
find "$STATE_DIR" -type f -mtime "+${TTL_DAYS}" -delete 2>/dev/null || true

# Extract session_id and file_path from input.
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '
    .session_id //
    .stop_input.session_id //
    .transcript[-1].session_id //
    "default"
' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

# Sanitize session_id for filename use
SAFE_SESSION=$(printf '%s' "$SESSION_ID" | tr -c '[:alnum:]_-' '_' | head -c 64)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '
    .tool_input.file_path //
    empty
' 2>/dev/null)

# No file_path → nothing to track (e.g. MultiEdit without path, fall back
# to tool_input.file as a fallback)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

STATE_FILE="$STATE_DIR/${SAFE_SESSION}.files"

# Add file_path to the session's set (deduplicated).
touch "$STATE_FILE"
if ! grep -Fxq "$FILE_PATH" "$STATE_FILE" 2>/dev/null; then
    echo "$FILE_PATH" >> "$STATE_FILE"
fi

# Count distinct files touched this session.
FILE_COUNT=$(wc -l < "$STATE_FILE" 2>/dev/null | tr -d ' ')
FILE_COUNT="${FILE_COUNT:-0}"

# Below threshold → nothing to gate.
if [ "$FILE_COUNT" -lt "$THRESHOLD" ]; then
    exit 0
fi

# At-or-above threshold. Is there a plan file for this session?
PLAN_FILE="$PLAN_DIR/${SAFE_SESSION}.md"
PLAN_FILE_ALT="$PLAN_DIR/plan-${SAFE_SESSION}.md"
PLAN_FILE_GENERIC="$PLAN_DIR/plan.md"

if [ -f "$PLAN_FILE" ] || [ -f "$PLAN_FILE_ALT" ] || [ -f "$PLAN_FILE_GENERIC" ]; then
    # Plan exists — work has been routed, allow.
    exit 0
fi

# No plan. Refuse the Write/Edit and ask the assistant to write a plan.
cat >&2 <<EOF
<system-reminder>
MULTI-FILE CHANGE WITHOUT A PLAN — this session has now touched $FILE_COUNT
distinct files via Write/Edit/MultiEdit, and no plan file exists at
$PLAN_FILE.

This is the failure mode documented in #60506 (recommendation 7): the model
sprawls across the codebase without writing a plan first, and the resulting
changes are scattered, partially-wired, or contradict each other. The cost
of an unplanned multi-file change lands on the operator at review time.

The files touched so far in this session:
$(sed 's/^/  - /' "$STATE_FILE" 2>/dev/null | head -20)

Before the next Write/Edit lands, do one of the following:

  1. Write a plan to $PLAN_FILE that lists the goal, the files involved,
     the order of changes, and the verification step for each file. Once
     the plan file exists, this gate auto-clears and writes proceed silently.

  2. If the changes are unrelated and a unified plan is not appropriate,
     split the work across separate sessions — one task per session, gate
     resets at session end (TTL 7 days).

  3. If this is a refactor where multi-file scope was inherent from the
     start, the plan can be one or two paragraphs — the gate's purpose
     is to require explicit forethought, not extensive documentation.

To disable this gate for design discussions, retrospectives, or sessions
where multi-file scope is not the failure mode you are guarding against,
set CC_PLAN_GATE_DISABLE=1 in your environment. The threshold can be
raised via CC_PLAN_GATE_THRESHOLD (default 3).
</system-reminder>
EOF

exit 2
