#!/bin/bash
# ================================================================
# goal-loop-detector.sh — Detect unbounded /goal evaluator loops
# ================================================================
# PURPOSE:
#   Claude Code v2.1.139+ ships /goal, an evaluator that fires after
#   every assistant turn and re-checks the user-specified condition.
#   If the condition is unsatisfiable, the evaluator loops without
#   any iteration limit, repeatedly producing the same
#   "condition not satisfied" feedback and consuming weekly quota.
#
#   Issue #58550 documents one operator burning ~50% of weekly budget
#   in 5 hours over 200+ identical evaluator turns. Issue #58465 and
#   #58348 document related /goal loop modes.
#
# WHAT THIS HOOK DOES:
#   1. On every Stop event, hashes the recent assistant message
#   2. Records the last N hashes per session
#   3. If the last N hashes are all identical (suggesting the
#      evaluator is firing the same feedback repeatedly), exits 2
#      with a notice instructing the user to clear the goal
#
#   The hook does not cap legitimate iteration — only identical
#   repetition. A goal that produces progressing output continues
#   normally.
#
# TRIGGER: Stop
#
# CONFIGURATION:
#   CC_GOAL_LOOP_N=5         — number of consecutive identical messages
#                              before exit 2 (default: 5)
#   CC_GOAL_LOOP_MAX_LEN=500 — only count messages shorter than this
#                              as evaluator-like (default: 500 chars)
#   CC_GOAL_LOOP_DISABLE=1   — set to 1 to disable this hook
#
# STATE: ~/.claude/state/goal-loop-detector.json
#   { "<session_id>": ["<hash1>", "<hash2>", ...] }
#
# REFERENCES:
#   - Issue #58550 (200+ iterations, 5h, 50% weekly budget)
#   - Issue #58465 (/goal command loops indefinitely after approval)
#   - Issue #58348 (/goal stop hook infinite loop on unregistered skills)
#   - Issue #58334 (/goal clear not working)
# ================================================================

# Allow disable
if [[ "${CC_GOAL_LOOP_DISABLE:-0}" == "1" ]]; then
    exit 0
fi

# Read hook payload from stdin
INPUT=$(cat)

# Extract session_id and the last assistant message text
# Stop hook payload format (per cc docs):
#   { "session_id": "...", "transcript_path": "...", ... }
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# If we can't find a transcript path, fall back to a no-op
if [[ -z "$TRANSCRIPT_PATH" || ! -r "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

# Get the last assistant message text from the transcript JSONL
# Each line is a JSON message; pick the most recent assistant entry
LAST_TEXT=$(tac "$TRANSCRIPT_PATH" 2>/dev/null | while IFS= read -r line; do
    role=$(echo "$line" | jq -r '.role // .message.role // empty' 2>/dev/null)
    if [[ "$role" == "assistant" ]]; then
        echo "$line" | jq -r '
            (.content // .message.content)
            | if type == "string" then .
              elif type == "array" then (map(select(.type == "text") | .text) | join("\n"))
              else "" end
        ' 2>/dev/null
        break
    fi
done)

# If no recent assistant message, no-op
if [[ -z "$LAST_TEXT" ]]; then
    exit 0
fi

# Only count short messages as evaluator-like
MAX_LEN="${CC_GOAL_LOOP_MAX_LEN:-500}"
TEXT_LEN=${#LAST_TEXT}
if [[ "$TEXT_LEN" -gt "$MAX_LEN" ]]; then
    # Substantive message — reset state for this session
    STATE_DIR="${HOME}/.claude/state"
    STATE_FILE="${STATE_DIR}/goal-loop-detector.json"
    if [[ -f "$STATE_FILE" ]]; then
        mkdir -p "$STATE_DIR"
        TMP=$(mktemp)
        jq --arg sid "$SESSION_ID" 'del(.[$sid])' "$STATE_FILE" > "$TMP" 2>/dev/null || echo '{}' > "$TMP"
        mv "$TMP" "$STATE_FILE"
    fi
    exit 0
fi

# Hash the message content (normalized: strip whitespace variations)
NORMALIZED=$(echo "$LAST_TEXT" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
HASH=$(echo -n "$NORMALIZED" | sha256sum | cut -c1-16)

# Load state
STATE_DIR="${HOME}/.claude/state"
STATE_FILE="${STATE_DIR}/goal-loop-detector.json"
mkdir -p "$STATE_DIR"
if [[ ! -f "$STATE_FILE" ]]; then
    echo '{}' > "$STATE_FILE"
fi

# Append hash to this session's list and keep last N
N="${CC_GOAL_LOOP_N:-5}"
TMP=$(mktemp)
jq --arg sid "$SESSION_ID" --arg h "$HASH" --argjson n "$N" '
    .[$sid] = ((.[$sid] // []) + [$h])[-$n:]
' "$STATE_FILE" > "$TMP" 2>/dev/null || { echo '{}' > "$TMP"; }
mv "$TMP" "$STATE_FILE"

# Check if the last N hashes are all identical
HASHES=$(jq -r --arg sid "$SESSION_ID" '.[$sid] // [] | .[]' "$STATE_FILE" 2>/dev/null)
HASH_COUNT=$(echo "$HASHES" | grep -c . 2>/dev/null || echo 0)
UNIQUE_COUNT=$(echo "$HASHES" | sort -u | grep -c . 2>/dev/null || echo 0)

if [[ "$HASH_COUNT" -ge "$N" && "$UNIQUE_COUNT" -eq 1 ]]; then
    # All N hashes identical — likely /goal evaluator looping
    cat >&2 <<EOF
[goal-loop-detector] Same short message ($TEXT_LEN chars) has fired $N times consecutively in session $SESSION_ID.

This pattern matches the /goal evaluator looping on an unsatisfiable
condition (see issue #58550: 200+ identical iterations consumed 50%
of weekly quota over 5 hours). The /goal command's evaluator currently
has no iteration limit or duplicate detection.

Suggested actions:
  - Run /goal clear to clear an unsatisfiable goal
  - If you intended progress, verify the goal condition is reachable
  - Set CC_GOAL_LOOP_DISABLE=1 to suppress this hook for this session

State file: $STATE_FILE
EOF
    # Reset this session's state so the next turn starts fresh after intervention
    TMP=$(mktemp)
    jq --arg sid "$SESSION_ID" 'del(.[$sid])' "$STATE_FILE" > "$TMP" 2>/dev/null || echo '{}' > "$TMP"
    mv "$TMP" "$STATE_FILE"
    exit 2
fi

exit 0
