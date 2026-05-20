set -uo pipefail
if [ "${CC_PERSISTENCE_CHECK_DISABLE:-0}" = "1" ]; then
    exit 0
fi
INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$SESSION_ID" ]; then
    exit 0
fi
SESSION_DIR="${CC_PERSISTENCE_CHECK_DIR:-${HOME}/.claude/projects}"
JSONL_FILE=""
if [ -d "$SESSION_DIR" ]; then
    JSONL_FILE=$(find "$SESSION_DIR" -maxdepth 3 -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
fi
REQUIRED_REGEX="${CC_PERSISTENCE_REQUIRED:-\"type\":\"(queue-operation|user|assistant)\"}"
if [ -z "$JSONL_FILE" ] || [ ! -f "$JSONL_FILE" ]; then
    if [ "${CC_PERSISTENCE_STRICT:-0}" = "1" ]; then
        cat >&2 << EOF
[session-persistence-verifier] Session JSONL file not found for session ${SESSION_ID}.
The harness may not be persisting this conversation to disk. If this is unexpected:
  1. Back up the in-memory transcript NOW (copy/paste from sidebar to a file)
  2. Check ~/.claude/projects/ for the expected file path
  3. Consider downgrading if you're on 2.1.144/2.1.145 (see #60984)
CC_PERSISTENCE_CHECK_DISABLE=1 to skip this check.
EOF
        exit 2
    fi
    exit 0
fi
if [ ! -s "$JSONL_FILE" ]; then
    cat >&2 << EOF
[session-persistence-verifier] Session JSONL file is empty: ${JSONL_FILE}
This matches the #60984 regression pattern (2.1.144/2.1.145 JSONL writer broken).
  1. Back up the in-memory transcript NOW (copy/paste from sidebar to a file)
  2. Verify your version: claude --version
  3. If on 2.1.144 or 2.1.145, consider downgrading to 2.1.143 (last-known-good)
  4. File #60984 has Anthropic's response history if available
CC_PERSISTENCE_CHECK_DISABLE=1 to skip this check.
EOF
    exit 2
fi
if ! grep -qE "$REQUIRED_REGEX" "$JSONL_FILE" 2>/dev/null; then
    has_ai_title=$(grep -c '"type":"ai-title"' "$JSONL_FILE" 2>/dev/null || echo 0)
    line_count=$(wc -l < "$JSONL_FILE" 2>/dev/null || echo 0)
    cat >&2 << EOF
[session-persistence-verifier] Session JSONL contains no message content: ${JSONL_FILE}
Found ${line_count} lines, of which ${has_ai_title} are ai-title entries.
Missing event types: queue-operation, user, assistant.
This matches the #60984 regression pattern (2.1.144/2.1.145 JSONL writer broken).
Sidebar history for this session will appear empty.
Action items (do this before exiting):
  1. Back up the in-memory transcript NOW (copy/paste from sidebar to a file)
  2. Verify your version: claude --version
  3. If on 2.1.144 or 2.1.145, consider downgrading to 2.1.143
  4. The 2.1.143 version is the last-known-good per the #60984 report
CC_PERSISTENCE_CHECK_DISABLE=1 to skip this check.
CC_PERSISTENCE_REQUIRED='custom-regex' to override the required event types.
EOF
    exit 2
fi
exit 0
