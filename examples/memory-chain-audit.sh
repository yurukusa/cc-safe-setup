#!/bin/bash
# memory-chain-audit.sh — extractMemories double-cache detector (Incident 7)
# Why: Claude Code's extractMemories feature fires a background call at the
#      end of each turn to update persistent memory. When the default is ON,
#      this background call carries its own cache chain that roughly doubles
#      the API cost per turn. Users who have not set
#      CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 are paying for the feature silently.
# Event: PostToolUse  MATCHER: "*"   (the extractMemories background call
#                                     fires as a Stop-event after the turn,
#                                     so we observe it one turn later)
# Action: Log cumulative main-chain vs extractMemories-chain cost per session.
#         If the ratio is consistently ≥ 1 (extractMemories costs match or
#         exceed the main chain), the log shows the user that the feature is
#         doubling their bill.
#
# Review with:
#   awk -F'\t' '{ main+=$3; mem+=$4 } END { if (main>0) printf "main=%d mem=%d ratio=%.2f\n", main, mem, mem/main }' \
#     ~/.claude/logs/memory-chain.log
#
# If the ratio is near or above 1 and you do not actively rely on auto-memory,
# set CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 in your shell rc.

set -u

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/memory-chain.log"
mkdir -p "$LOG_DIR" 2>/dev/null

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
[ "$SESSION_ID" = "unknown" ] && exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

# Main-chain cost = total input+output for the last assistant turn tagged
# "main". extractMemories-chain cost = the same for the last turn tagged as
# a memory call. Tags differ between client versions; we match on the
# presence of "extractMemories" / "memory" in the request metadata.

MAIN=$(tac "$TRANSCRIPT" 2>/dev/null \
       | grep -m1 '"type":"assistant"' \
       | jq -r '(.message.usage.input_tokens // 0) + (.message.usage.output_tokens // 0)' 2>/dev/null)

MEM=$(grep 'extractMemor\|"memory"' "$TRANSCRIPT" 2>/dev/null | tail -1 \
      | jq -r '(.message.usage.input_tokens // 0) + (.message.usage.output_tokens // 0)' 2>/dev/null)

MAIN=${MAIN:-0}
MEM=${MEM:-0}

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\t%s\t%s\t%s\n' "$TS" "$SESSION_ID" "$MAIN" "$MEM" >> "$LOG_FILE"

exit 0
