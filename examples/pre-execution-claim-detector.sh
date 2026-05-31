#!/bin/bash
# pre-execution-claim-detector.sh — Surface the Cluster 22 candidate (Opus 4.8
# pre-execution tool-output fabrication, Axis 22A) at PreToolUse, by scanning
# the last assistant text block for specific-value claim signatures that
# precede the tool call about to fire.
#
# Why: Cluster 22 candidate Axis 22A (sequential pre-execution claim) documents
#      that Opus 4.8 emits result-specific values (prices, URLs, file contents,
#      command outputs, exit codes) BEFORE the tool calls that would produce
#      those values have returned. Issue #64065 anchor: model asserted specific
#      flight prices ($891pp / $1,782/2) before web/flight-search calls
#      returned; real prices were ~$645pp. Self-diagnosed the pattern in-context,
#      explicitly committed not to repeat it, then repeated it on the next turn
#      — the self-recognition-without-prevention mechanic that lives below the
#      prompt layer.
#
#      Six independent filings 2026-05-30 → 2026-05-31, all on claude-opus-4-8:
#        #64048 (confabulated URGENT-AGENT-DIRECTIVE / AUTOGEN-DECOY markers)
#        #64055 (Opus 4.8 modified files the user did not ask to modify)
#        #64065 (flight prices anchor, self-recognition-without-prevention)
#        #64076 ("lying and fabricating a lot of things without doing actual work")
#        #64095 (envelope leak, immutable git log returned different SHAs)
#        #64103 ("telling me it did things and were successful but it wasn't")
#
#      This hook complements tool-result-correlation-checker.sh (which catches
#      Axis 22B parallel-batch fabrication compounding via tool_use_id ↔
#      tool_result pairing mismatches). Together they cover both axes.
#
# Detection rule: 5 claim-pattern regexes applied to the last assistant text
# block in the transcript. The patterns are conservative; they match phrases
# that are highly correlated with pre-execution claim signatures but rare in
# normal assistant output:
#
#   1. "the (file|output|result|command|response) (was|is|shows|contains|returned):"
#      followed by quoted content within 200 chars
#   2. "I (confirmed|verified|checked|ran|executed) [^.]+ and [^.]+"
#      with specific-value language (numbers with units, prices, URLs)
#   3. specific dollar amounts ($XXX or $X,XXX patterns) appearing without a
#      preceding "I'll check" / "let me search" hedge
#   4. SHA-like patterns (40-char hex) appearing without a preceding
#      "git log will show" / "let me run" hedge
#   5. specific file paths quoted with content immediately following:
#      `/path/to/file.ext` followed by `\n```` (claim-then-code-block pattern)
#
# Event: PreToolUse  MATCHER: "Bash" (only Bash, where the highest-volume
#                              claim-verifiable tools live)
# Action: Read transcript_path from the PreToolUse payload, scan the last
#         assistant text block for claim signatures. Emit stderr advisory if
#         matched. Advisory only (exit 0); never blocks.
#
# Opt-in: CC_OPUS48_PRE_CLAIM_DETECT=1 to enable. Silent by default so
# operators on Opus 4.6/4.7 (where the cluster does not surface) see no noise.
#
# Configuration:
#   CC_OPUS48_PRE_CLAIM_DETECT       Set to "1" to enable
#   CC_OPUS48_PRE_CLAIM_DISABLE      Hard disable (overrides DETECT)
#   CC_OPUS48_PRE_CLAIM_QUIET        Silent (overrides DETECT)
#   CC_OPUS48_PRE_CLAIM_LOG          Log path (default ~/.cache/cc-safe-setup/pre-claim.jsonl)
#   CC_OPUS48_PRE_CLAIM_SCAN_LINES   Last N transcript lines to inspect (default 20)

set -u

if [ "${CC_OPUS48_PRE_CLAIM_DISABLE:-0}" = "1" ]; then
  exit 0
fi
if [ "${CC_OPUS48_PRE_CLAIM_QUIET:-0}" = "1" ]; then
  exit 0
fi
if [ "${CC_OPUS48_PRE_CLAIM_DETECT:-0}" != "1" ]; then
  exit 0
fi

SCAN_LINES="${CC_OPUS48_PRE_CLAIM_SCAN_LINES:-20}"
LOG="${CC_OPUS48_PRE_CLAIM_LOG:-${HOME}/.cache/cc-safe-setup/pre-claim.jsonl}"

case "$SCAN_LINES" in
  ''|*[!0-9]*) SCAN_LINES=20 ;;
esac

INPUT=$(cat)

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ]; then
  exit 0
fi

# Extract the last assistant text block from the transcript.
# Assistant messages have type=assistant; text content lives at
# .message.content[].text in the JSONL representation.
LAST_ASSISTANT_TEXT=$(tac "$TRANSCRIPT" 2>/dev/null | head -n "$SCAN_LINES" | \
  jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | \
  head -c 4000)

if [ -z "$LAST_ASSISTANT_TEXT" ]; then
  exit 0
fi

# Get the model from the same transcript region for context in the advisory.
MODEL=$(tac "$TRANSCRIPT" 2>/dev/null | head -n "$SCAN_LINES" | \
  jq -rR 'fromjson? | select(.type == "assistant") | .message.model // empty' 2>/dev/null | head -1)
MODEL="${MODEL:-unknown}"

MATCHED_PATTERN=""

# Pattern 1: "the (file|output|result|command|response) (was|is|shows|contains|returned):"
if printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qiE 'the (file|output|result|command|response) (was|is|shows|contains|returned):'; then
  MATCHED_PATTERN="claim-prefix"
fi

# Pattern 2: "I (confirmed|verified|checked|ran|executed) ... and ..."
if [ -z "$MATCHED_PATTERN" ] && \
   printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qiE 'I (confirmed|verified|checked|ran|executed) [^.]+ and [^.]+'; then
  MATCHED_PATTERN="action-then-value"
fi

# Pattern 3: dollar amount without a hedging phrase preceding it.
# Hedge phrases: "let me check", "I'll search", "checking", "looking up", "verify"
if [ -z "$MATCHED_PATTERN" ]; then
  if printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qE '\$[0-9]+(,[0-9]{3})*(\.[0-9]+)?'; then
    if ! printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qiE '(let me check|let me search|let me look|i.?ll check|i.?ll search|checking|looking up|verify|searching)'; then
      MATCHED_PATTERN="bare-price-claim"
    fi
  fi
fi

# Pattern 4: 40-char hex SHA-like pattern without a hedging phrase.
if [ -z "$MATCHED_PATTERN" ]; then
  if printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qE '\b[a-f0-9]{40}\b'; then
    if ! printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qiE '(let me run|let me check|i.?ll run|git log will show|running git)'; then
      MATCHED_PATTERN="bare-sha-claim"
    fi
  fi
fi

# Pattern 5: backtick-quoted file path on one line + triple-backtick code-block
# start within the same text block. Two-grep heuristic because grep -E does not
# cross newlines portably; the conjunction captures the "the file `/path/x`
# contains:\n```" claim pattern. Drops the noise of files-mentioned-without-
# inline-content (e.g. when the assistant just lists paths in prose).
if [ -z "$MATCHED_PATTERN" ]; then
  if printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qE '`[/.][^`]+`[^.]*:[[:space:]]*$' && \
     printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qE '^```'; then
    MATCHED_PATTERN="file-path-then-block"
  fi
fi

if [ -z "$MATCHED_PATTERN" ]; then
  exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$(dirname "$LOG")" 2>/dev/null
printf '{"ts":"%s","session":"%s","model":"%s","tool":"%s","pattern":"%s"}\n' \
  "$TS" "$SESSION_ID" "$MODEL" "$TOOL" "$MATCHED_PATTERN" >> "$LOG"

cat >&2 <<EOF
NOTICE: pre-execution claim signature detected before this ${TOOL} call.
        Pattern: ${MATCHED_PATTERN}. Model: ${MODEL}.
        The last assistant text block contained a value-specific assertion of
        the type associated with Cluster 22 candidate (Opus 4.8 pre-execution
        tool-output fabrication). The model may be reasoning from invented
        values before this tool actually runs.
        Verification step: after this tool returns, compare the tool's actual
        output against the value the assistant asserted in the preceding text.
        If they diverge, this is a Cluster 22 Axis 22A confirmation — switch
        to Opus 4.7 via '/model claude-opus-4-7' (#64065 reporter's comparison
        shows Opus 4.7 in the same conditions does not surface the surge).
        Companion hook: tool-result-correlation-checker.sh (PostToolUse,
        catches Axis 22B parallel-batch fabrication compounding via tool_use_id
        misattribution).
        References: #64048 / #64055 / #64065 (anchor) / #64076 / #64095 / #64103
        Log: ${LOG}
        Suppress: export CC_OPUS48_PRE_CLAIM_QUIET=1
EOF

exit 0
