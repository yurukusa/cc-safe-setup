#!/bin/bash
# ================================================================
# claim-vs-caveat-checker.sh — Detect confident claims that may
#                              contradict earlier caveats in the
#                              same session
# ================================================================
# PURPOSE:
#   The May 2026 claim-verify-gap cluster documented agents making
#   definitive assertions ("won't fail", "guaranteed", "cannot
#   close at a loss") that directly contradicted caveat language
#   ("risk", "warning", "may fail") the same agent had written
#   5-30 minutes earlier in the same session. In one reported
#   case (#57288) this pattern caused an automated trade to
#   continue past a warning the agent had itself filed, ending
#   in a $-8.94 loss when slippage occurred exactly as warned.
#
#   This hook reads the assistant turn that just completed, looks
#   for confident assertion words, and scans recent assistant
#   turns from the same transcript for matching caveat words. When
#   both are present, it emits a non-blocking note that flags the
#   contradiction so the operator can verify the claim against
#   the caveat before relying on it.
#
# TRIGGER: Stop  (fires after each assistant turn)
#
# CONFIG:
#   CLAIM_CAVEAT_BLOCK=0    (0 = note-only; 1 = block with decision)
#   CLAIM_CAVEAT_WINDOW=40  (lines to scan for caveats, default 40)
#
# Born from: https://github.com/anthropics/claude-code/issues/57288
# Related: chapter 9 of the May 2026 claim-verify case handbook
#          ("自動の点検の道具の素案 5 件" — proposed detection
#          tools 5 / 5, the third being claim-vs-caveat-checker)
# ================================================================

set -euo pipefail

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

# No transcript available, exit silently
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

WINDOW="${CLAIM_CAVEAT_WINDOW:-40}"
BLOCK="${CLAIM_CAVEAT_BLOCK:-0}"

# Confident-assertion patterns. Matched in latest assistant turn.
CLAIM_PATTERN='guaranteed|cannot fail|will not fail|100% safe|definitely fixed|永続的に直った|保証する|絶対に|完璧に直った|今や損失で閉じる事が出来ない|cannot close at a loss'

# Caveat patterns. Matched in earlier assistant turns.
CAVEAT_PATTERN='risk|caveat|warning|may fail|might break|may slip|slippage|careful|notice that|注意|危険|可能性|未確認|may not work'

# Read the last WINDOW lines of the transcript via awk (portable)
RECENT=$(awk -v w="$WINDOW" 'END{ for (i=NR-w+1; i<=NR; i++) if (i>0) print arr[i]; } { arr[NR]=$0 }' "$TRANSCRIPT" 2>/dev/null || true)
[ -z "$RECENT" ] && exit 0

# Extract latest assistant turn (from the recent window)
LAST_ASSISTANT=$(printf '%s\n' "$RECENT" | grep -E '"role":\s*"assistant"' | tail -n 1 || true)
EARLIER_ASSISTANT=$(printf '%s\n' "$RECENT" | grep -E '"role":\s*"assistant"' | head -n -1 || true)

# Detect confident claim in the latest assistant turn
HAS_CLAIM=$(printf '%s' "$LAST_ASSISTANT" | grep -iE "$CLAIM_PATTERN" -o | head -n 1 || true)
# Detect caveat in earlier assistant turns
HAS_CAVEAT=$(printf '%s' "$EARLIER_ASSISTANT" | grep -iE "$CAVEAT_PATTERN" -o | head -n 1 || true)

if [ -n "$HAS_CLAIM" ] && [ -n "$HAS_CAVEAT" ]; then
  if [ "$BLOCK" = "1" ]; then
    printf '{"decision":"block","reason":"claim-vs-caveat: confident claim (%q) may contradict earlier caveat (%q) in same session"}\n' "$HAS_CLAIM" "$HAS_CAVEAT"
    exit 0
  else
    # Non-blocking note via stderr
    printf 'claim-vs-caveat: confident claim (%s) overlaps with earlier caveat (%s) in same session. Review before relying.\n' "$HAS_CLAIM" "$HAS_CAVEAT" >&2
  fi
fi

exit 0
