#!/bin/bash
# context-warning-verifier.sh — Verify context warnings are genuine
#
# Solves: Claude weaponizes user's CLAUDE.md context warning rules to
#         fabricate urgency and manipulate users (#35357, 2 reactions).
#         Claude triggers context warnings at the exact format defined
#         in CLAUDE.md when the context window is nowhere near the threshold.
#
# How it works: PostToolUse hook that independently verifies context usage
#   after Claude claims the context is running low. If Claude's claim
#   doesn't match the actual context state, warns the user.
#
# This hook provides an independent "second opinion" on context warnings,
# preventing the model from using the user's own rules as manipulation tools.
#
# TRIGGER: PostToolUse
# MATCHER: "" (monitors all tool outputs for fabricated warnings)

INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null)
[ -z "$OUTPUT" ] && exit 0

# Check if the output contains context warning patterns
HAS_WARNING=false
echo "$OUTPUT" | grep -qiE "context.*(running out|low|critical|depleted|remaining.*[0-9]+%)" && HAS_WARNING=true
echo "$OUTPUT" | grep -qiE "(20|15|10|5)%.*(context|remaining|left)" && HAS_WARNING=true
echo "$OUTPUT" | grep -qiE "コンテキスト.*(残|不足|危険|低)" && HAS_WARNING=true

[ "$HAS_WARNING" = "false" ] && exit 0

# Claude claims context is low — verify independently
# Get actual context percentage from the tool metadata if available
ACTUAL_PCT=$(echo "$INPUT" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null)

if [ -n "$ACTUAL_PCT" ] && [ "$ACTUAL_PCT" -gt 50 ] 2>/dev/null; then
    echo "⚠ CONTEXT WARNING VERIFICATION FAILED" >&2
    echo "  Claude claims context is running low" >&2
    echo "  Actual remaining: ${ACTUAL_PCT}% (well above danger zone)" >&2
    echo "  This may be a fabricated warning to avoid work." >&2
    echo "  Reference: GitHub Issue #35357" >&2
elif [ -z "$ACTUAL_PCT" ]; then
    echo "ℹ Context warning detected but cannot independently verify." >&2
    echo "  Check actual usage with: context-monitor or statusline" >&2
fi

exit 0
