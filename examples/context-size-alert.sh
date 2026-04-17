#!/bin/bash
# context-size-alert.sh — Warn when context window usage exceeds threshold
# Trigger: PostToolUse
# Matcher: (empty — runs after every tool use)
#
# Since v2.1.100, the system prompt grew ~40-50% (~4,000 tokens).
# This hook monitors context usage and warns before you hit limits.
# See: https://github.com/anthropics/claude-code/issues/46339
#
# Optimization tips: https://zenn.dev/yurukusa/books/token-savings-guide
#
# TRIGGER: PostToolUse  MATCHER: ""

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Only check every 10th invocation to minimize overhead
COUNTER_FILE="/tmp/context-size-alert-${SESSION_ID:-default}.count"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
[ $((COUNT % 10)) -ne 0 ] && exit 0

# Check if /cost or /context data is available via transcript
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0

# Count approximate context by transcript file size (rough proxy)
if [ -f "$TRANSCRIPT" ]; then
    SIZE_KB=$(du -k "$TRANSCRIPT" | cut -f1)
    # Rough threshold: 500KB transcript ≈ approaching context limits
    if [ "$SIZE_KB" -gt 500 ]; then
        echo "⚠ Context is large (~${SIZE_KB}KB transcript). Consider /compact or /clear to reduce token cost." >&2
        echo "  Tip: Run /context to see exact usage breakdown." >&2
    fi
fi

exit 0
