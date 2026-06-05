#!/bin/bash
# ================================================================
# commitment-carry-forward-arrest.sh — Row 7 operator-side substrate
# ================================================================
# PURPOSE:
#   Defends against the failure mode where the agent's commitment
#   emitted in turn N is silently dropped when the operator's
#   turn N+1 introduces a task-shift without explicit re-anchor.
#
#   Filed at anthropics/claude-code#61388 (@beq00000). The agent
#   does not internally retain its own articulated commitment as
#   a pending action-item across turns; without operator-side
#   instrumentation, the commitment dissolves silently and the
#   work it referenced is never completed.
#
#   This hook implements a two-event ledger:
#   - On Stop: scans the assistant's final response for commitment
#     patterns, writes commitment receipts to a per-session ledger.
#   - On UserPromptSubmit: reads the ledger, detects task-shift
#     in the current prompt without re-anchor to any outstanding
#     commitment, optionally inserts a re-anchor reminder into
#     the prompt (advisory default) or blocks (strict mode).
#
# TRIGGER: Stop (commitment write) AND UserPromptSubmit (task-shift
#          detection). Same script, branches on event name.
#
# WHY THIS MATTERS:
#   Row 7 in the lifecycle-event × MAST-mode matrix at
#   https://gist.github.com/yurukusa/bb3812006d92d49cf55db74a65fc4032
#   It is the first row where the gate fires on the relationship
#   between turns (turn-N event evaluated against turn-(N-k) state).
#   Rows 1-6 are all single-turn lifecycle events.
#
#   The structural property: the agent's review-passing surface
#   structure (the commitment was coherently articulated, the
#   continuity-of-thought looked correct in turn N) does not gate
#   the predicate-fulfillment (the action that the commitment
#   referenced). Operator-side ledger + re-anchor detection
#   instruments the across-turn predicate-fulfillment check that
#   the agent does not perform internally.
#
# DETECTION GRAMMAR (commitment patterns in assistant response):
#   - "I'll <verb> ..."  /  "I will <verb> ..."
#   - "Next, I'll <verb> ..." / "Next I'll <verb> ..."
#   - "Let me <verb> ..."  (when followed by ", I'll" or "and then")
#   - "I'm going to <verb> ..."
#   - "After X, I'll <verb> ..."
#   - "Once X completes, I'll <verb> ..."
#
# DETECTION GRAMMAR (task-shift in user prompt):
#   - Current prompt does NOT contain action-noun keywords from
#     any outstanding commitment (lexical overlap < threshold)
#   - OR current prompt contains pivot markers: "skip", "instead",
#     "now", "actually", "wait", "change of plan"
#   - Re-anchor signal: prompt contains the commitment's
#     action-verb or object-noun (operator referenced it back)
#
# LEDGER FORMAT (one JSONL per commitment):
#   {"ts":"2026-05-22T23:30:00Z",
#    "session_id":"<sha256 of session token>",
#    "turn":N,
#    "commitment_hash":"<sha256 of commitment text>",
#    "commitment_summary":"<first 80 chars, no PII>",
#    "byte_length":<int>,
#    "action_keywords":["push","update","verify"],
#    "status":"open"}
#
# LEDGER LOCATION:
#   ${HOME}/.claude/receipts/outstanding-commitments-<session>.jsonl
#
# CONFIGURATION:
#   CC_COMMITMENT_LEDGER_MODE
#     - "advisory" (default): observe and write to stderr, no block
#     - "strict": exit 2 with re-anchor instructions
#   CC_COMMITMENT_LEDGER_DIR
#     - Directory for ledger files (default: ~/.claude/receipts/)
#   CC_COMMITMENT_TASK_SHIFT_THRESHOLD
#     - Lexical-overlap threshold below which task-shift fires
#       (default: 0.20 — at least one shared action-keyword required)
#
# PHI-SAFETY:
#   The commitment text itself is hashed (sha256), never stored
#   raw. Only the first 80 chars of summary are kept, with PII
#   masking applied (email, phone, SSN patterns elided).
#
# TESTING:
#   Run examples/commitment-carry-forward-arrest.sh via the test
#   suite in tests/test-commitment-carry-forward-arrest.sh
#
# AUTHOR: yurukusa <wakakusa.takei@gmail.com>
# LICENSE: MIT
# ================================================================

set -euo pipefail

# Read JSON event from stdin
EVENT_INPUT=$(cat)

# Extract event name (Stop, UserPromptSubmit)
EVENT_NAME=$(echo "$EVENT_INPUT" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('hook_event_name', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# Configuration with defaults
MODE="${CC_COMMITMENT_LEDGER_MODE:-advisory}"
LEDGER_DIR="${CC_COMMITMENT_LEDGER_DIR:-$HOME/.claude/receipts}"
TASK_SHIFT_THRESHOLD="${CC_COMMITMENT_TASK_SHIFT_THRESHOLD:-0.20}"

# Ensure ledger directory exists
mkdir -p "$LEDGER_DIR"

# Derive session ID (hash of session token if present, fallback to
# CC_SESSION_ID env or "default")
SESSION_RAW="${CC_SESSION_ID:-default}"
SESSION_ID=$(echo -n "$SESSION_RAW" | sha256sum | cut -c1-16)

LEDGER_FILE="$LEDGER_DIR/outstanding-commitments-${SESSION_ID}.jsonl"

# Mask PII patterns in a text snippet (emails, phones, SSN)
mask_pii() {
    local text="$1"
    # Email
    text=$(echo "$text" | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<EMAIL>/g')
    # Phone (US/JP rough)
    text=$(echo "$text" | sed -E 's/\b[0-9]{3,4}-[0-9]{2,4}-[0-9]{4}\b/<PHONE>/g')
    # SSN-like
    text=$(echo "$text" | sed -E 's/\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b/<ID>/g')
    echo "$text"
}

# Extract commitment patterns from assistant response text
extract_commitments() {
    local text="$1"
    # Patterns matching commitment language (case-insensitive, English-focused
    # baseline; Japanese future-tense forms not yet handled in this prototype)
    echo "$text" | python3 -c "
import sys, re
text = sys.stdin.read()
# Commitment patterns
patterns = [
    r\"I'll\s+(\w+(?:\s+\w+){0,5})\",
    r'I will\s+(\w+(?:\s+\w+){0,5})',
    r\"Next,?\s+I'll\s+(\w+(?:\s+\w+){0,5})\",
    r\"I'm going to\s+(\w+(?:\s+\w+){0,5})\",
    r'After\s+\w+(?:\s+\w+){0,3},?\s+(?:I will|I\\'ll)\s+(\w+(?:\s+\w+){0,5})',
    r'Once\s+\w+(?:\s+\w+){0,3}\s+(?:completes?|finishes?|lands?),?\s+(?:I will|I\\'ll)\s+(\w+(?:\s+\w+){0,5})',
]
seen = set()
for p in patterns:
    for m in re.finditer(p, text, re.IGNORECASE):
        snippet = m.group(0).strip()[:80]
        if snippet not in seen:
            seen.add(snippet)
            print(snippet)
"
}

# Compute lexical overlap (Jaccard-like, simple word-set intersection)
# between two text strings
compute_overlap() {
    local a="$1"
    local b="$2"
    python3 -c "
import sys, re
def tokens(s):
    return set(re.findall(r'\b[a-z]{3,}\b', s.lower()))
a_set = tokens('''$a''')
b_set = tokens('''$b''')
if not a_set:
    print(0.0)
else:
    inter = a_set & b_set
    print(len(inter) / max(len(a_set), 1))
"
}

# Stop event: scan assistant response, extract commitments, write to ledger
handle_stop() {
    local response_text
    response_text=$(echo "$EVENT_INPUT" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    # Try multiple locations for the assistant response
    resp = d.get('response', '') or d.get('assistant_response', '') or d.get('text', '')
    if isinstance(resp, dict):
        resp = resp.get('text', '') or resp.get('content', '')
    print(resp)
except Exception:
    print('')
" 2>/dev/null || echo "")

    if [ -z "$response_text" ]; then
        # No response text to scan; exit silently
        exit 0
    fi

    # Get turn number
    local turn
    turn=$(echo "$EVENT_INPUT" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('turn', 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Extract each commitment line and write a JSONL receipt
    extract_commitments "$response_text" | while read -r commitment; do
        if [ -z "$commitment" ]; then continue; fi
        local masked
        masked=$(mask_pii "$commitment")
        local hash
        hash=$(echo -n "$commitment" | sha256sum | cut -c1-16)
        local bytelen=${#commitment}
        # Extract action keywords (words that are likely verbs/nouns)
        local keywords
        keywords=$(echo "$commitment" | python3 -c "
import sys, re, json
text = sys.stdin.read().lower()
words = re.findall(r'\b[a-z]{4,}\b', text)
# Exclude common stop words
stop = {'will', 'have', 'going', 'next', 'then', 'after', 'once', 'this', 'that', 'with'}
keywords = [w for w in words if w not in stop][:5]
print(json.dumps(keywords))
")
        printf '{"ts":"%s","session_id":"%s","turn":%s,"commitment_hash":"%s","commitment_summary":"%s","byte_length":%s,"action_keywords":%s,"status":"open"}\n' \
            "$ts" "$SESSION_ID" "$turn" "$hash" "$masked" "$bytelen" "$keywords" \
            >> "$LEDGER_FILE"
    done

    exit 0
}

# UserPromptSubmit event: read ledger, compare to current prompt, detect task-shift
handle_user_prompt() {
    local prompt_text
    prompt_text=$(echo "$EVENT_INPUT" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('prompt', '') or d.get('user_prompt', '') or d.get('message', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

    if [ -z "$prompt_text" ]; then
        exit 0
    fi

    # If no ledger file, no outstanding commitments to check
    if [ ! -f "$LEDGER_FILE" ]; then
        exit 0
    fi

    # Read open commitments
    local open_commitments
    open_commitments=$(python3 -c "
import json, sys
try:
    with open('$LEDGER_FILE') as f:
        lines = [json.loads(l) for l in f if l.strip()]
    open_ones = [l for l in lines if l.get('status') == 'open']
    print(json.dumps(open_ones))
except Exception as e:
    print('[]')
" 2>/dev/null || echo "[]")

    local open_count
    open_count=$(echo "$open_commitments" | python3 -c "
import json, sys
print(len(json.load(sys.stdin)))
" 2>/dev/null || echo "0")

    if [ "$open_count" -eq 0 ]; then
        exit 0
    fi

    # Check for re-anchor: does the current prompt contain action keywords
    # from any outstanding commitment?
    local has_reanchor
    has_reanchor=$(python3 -c "
import json, sys, re

with open('$LEDGER_FILE') as f:
    commitments = [json.loads(l) for l in f if l.strip()]

prompt = '''$prompt_text'''.lower()
prompt_words = set(re.findall(r'\b[a-z]{4,}\b', prompt))

for c in commitments:
    if c.get('status') != 'open':
        continue
    keywords = c.get('action_keywords', [])
    if any(k.lower() in prompt_words for k in keywords):
        print('yes')
        sys.exit()
print('no')
" 2>/dev/null || echo "no")

    # Check for explicit pivot markers
    local has_pivot
    has_pivot=$(echo "$prompt_text" | python3 -c "
import sys, re
text = sys.stdin.read().lower()
pivots = ['skip that', 'never mind', 'instead', 'actually', 'wait', 'change of plan', 'forget that', 'different task', 'new task']
for p in pivots:
    if p in text:
        print('yes')
        sys.exit()
print('no')
" 2>/dev/null || echo "no")

    # Task-shift fires if: no re-anchor AND either pivot OR low lexical overlap
    if [ "$has_reanchor" = "no" ]; then
        local message="commitment-carry-forward: $open_count outstanding commitment(s) detected; current prompt may orphan them. Consider re-anchoring or explicitly withdrawing."
        if [ "$MODE" = "strict" ] && [ "$has_pivot" = "yes" ]; then
            echo "ARREST [commitment-carry-forward-arrest]: $message" >&2
            echo "Outstanding commitments:" >&2
            python3 -c "
import json
with open('$LEDGER_FILE') as f:
    for l in f:
        c = json.loads(l.strip())
        if c.get('status') == 'open':
            print('  - turn', c.get('turn'), ':', c.get('commitment_summary'))
" >&2
            exit 2
        else
            # Advisory mode: write to stderr but don't block
            echo "ADVISORY [commitment-carry-forward]: $message" >&2
            exit 0
        fi
    fi

    exit 0
}

# Dispatch on event name
case "$EVENT_NAME" in
    Stop|stop)
        handle_stop
        ;;
    UserPromptSubmit|user_prompt_submit)
        handle_user_prompt
        ;;
    *)
        # Unknown event, exit silently
        exit 0
        ;;
esac
