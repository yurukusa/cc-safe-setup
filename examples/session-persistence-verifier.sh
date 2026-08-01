set -uo pipefail
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-session-persistence-verifier-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [session-persistence-verifier]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
  3. If on 2.1.144/2.1.145, consider downgrading to 2.1.143 (see #60984)
  4. If on the native installer era (2.1.168-2.1.170), a separate write-path
     break is reported (#66486, partially patched in 2.1.170; #66734). It can
     hit interactive sessions while spawned/headless sessions persist fine, and
     can outlive an on-disk binary upgrade because the broken state lives in a
     long-running process. Fully quit ALL Claude Code instances and relaunch --
     a fresh launch has restored persistence per those reports.
CC_PERSISTENCE_CHECK_DISABLE=1 to skip this check.
EOF
        exit 2
    fi
    exit 0
fi
if [ ! -s "$JSONL_FILE" ]; then
    cat >&2 << EOF
[session-persistence-verifier] Session JSONL file is empty: ${JSONL_FILE}
This matches a JSONL writer regression. Two reported windows:
  - #60984 (2.1.144/2.1.145): downgrade to 2.1.143 (last-known-good).
  - #66486 / #66734 (native installer era, 2.1.168-2.1.170): the break can
    outlive an on-disk binary upgrade because it lives in a long-running
    process; fully quit ALL Claude Code instances and relaunch.
  1. Back up the in-memory transcript NOW (copy/paste from sidebar to a file)
  2. Verify your version: claude --version
  3. Apply the matching fix above for your version window
  4. A mirror backup of ~/.claude/projects/**/*.jsonl (size-comparison skip)
     preserves transcripts before an empty file can overwrite them
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
This is a metadata-only stub: the file exists but holds no conversation. Two
reported windows produce this shape:
  - #60984 (2.1.144/2.1.145): JSONL writer broken; downgrade to 2.1.143.
  - #66486 / #66734 (native installer era, 2.1.168-2.1.170): interactive
    sessions stub out while spawned/headless sessions persist fine, and the
    break can outlive an on-disk binary upgrade (it lives in a long-running
    process). Fully quit ALL Claude Code instances and relaunch; a fresh launch
    has restored persistence per those reports.
Sidebar history for this session will appear empty.
Action items (do this before exiting):
  1. Back up the in-memory transcript NOW (copy/paste from sidebar to a file)
  2. Verify your version: claude --version
  3. Apply the matching fix above for your version window
  4. A mirror backup of ~/.claude/projects/**/*.jsonl (size-comparison skip)
     preserves transcripts before a stub can overwrite them
CC_PERSISTENCE_CHECK_DISABLE=1 to skip this check.
CC_PERSISTENCE_REQUIRED='custom-regex' to override the required event types.
EOF
    exit 2
fi
exit 0
