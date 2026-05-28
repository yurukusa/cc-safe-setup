#!/bin/bash
# ================================================================
# xml-format-leak-detector.sh — Warn when legacy XML tool-use
#   format markers leak into tool_use input fields in the trailing
#   transcript, signalling sub-pattern 12D (the long-payload
#   attention-dilution decoder flip).
# ================================================================
# PURPOSE:
#   Issue #49747 documents that on longer payloads, Opus 4.7
#   intermittently emits legacy Anthropic XML tool-use syntax
#   inside JSON-format tool calls. Specifically, a string-valued
#   argument ends with a literal `</parameter_name>` closing tag
#   *inside the JSON string*, and subsequent parameters appear as
#   `<parameter name="X">value</parameter>` XML blocks instead of
#   JSON key-value pairs. Because the runtime parses tool calls
#   as strict JSON, the XML-declared parameters never reach the
#   parsed arguments object — required fields come through as
#   undefined, schema validation fails, and the model is forced
#   to retry (the reporter observed 4-6 consecutive attempts per
#   logical turn, each progressively shorter, burning ~1k tokens
#   per failed attempt).
#
#   The reporter confirmed this is a decoder-level format switch:
#   explicit system-prompt rules forbidding XML tags in tool-call
#   strings did NOT prevent the bug. The trigger correlates with
#   total payload length — short arguments succeed on first try,
#   paragraph-length arguments almost always trigger the leak.
#   This is a regression from Opus 4.6.
#
#   The other Cluster 12 sub-pattern detectors react to surface
#   markers ("malformed and could not be parsed") or structural
#   mismatches (stop_reason vs. content blocks). Sub-pattern 12D
#   has neither of those signals — the tool call IS parseable as
#   JSON, just with the XML format chars sitting in a string
#   field. The detection signal for 12D is the literal XML
#   tool-use markers appearing inside tool_use input values.
#
# TRIGGER: PostToolUse  MATCHER: ""
# CLUSTER: 12 (Tool Call Parsing failures in Opus 4.7)
# SUB-PATTERN: 12D (long-payload attention dilution; decoder flip)
#
# BEHAVIOR:
#   - Read transcript_path from PostToolUse hook input.
#   - Scan the trailing LOOKBACK lines for assistant turns
#     carrying tool_use blocks.
#   - For each tool_use block, serialize the input field and
#     search for the literal XML tool-use markers (the lexical
#     fingerprint of the decoder flip): `<parameter name=`,
#     `</parameter>`, `<invoke name=`, `</invoke>`,
#     `</function_calls>`.
#   - If at or above the threshold, emit a one-screen stderr
#     advisory naming sub-pattern 12D and the payload-shortening
#     recovery path.
#   - Rate-limit advisory emission per session via a counter
#     file so the warning does not repeat on every PostToolUse
#     after the first detection.
#   - Always exits 0 (advisory only; never blocks tool execution).
#
# WHY THE TOOL_USE-INPUT CHECK:
#   The XML markers can appear in transcript text for many
#   reasons unrelated to 12D — documentation, prose, discussion
#   of tool-call mechanics. A naive grep of the transcript would
#   fire on those. The 12D signature is specifically the XML
#   markers appearing INSIDE tool_use.input string fields, where
#   they have no semantic role — the model emitted them mid-
#   argument because the decoder flipped from JSON to XML mode.
#   Checking only tool_use.input narrows the detection to the
#   structural location where the leak actually shows up.
#
# CONFIGURATION (env vars):
#   CC_XML_LEAK_DISABLE       Set to "1" to silence.
#   CC_XML_LEAK_LOOKBACK      How many recent transcript lines
#                             to scan. Default 200.
#   CC_XML_LEAK_THRESHOLD     Minimum number of tool_use blocks
#                             with XML markers in input in
#                             LOOKBACK to fire. Default 1.
#                             Single occurrences are rare enough
#                             to be informative; raise if you
#                             work with prose that intentionally
#                             contains these strings.
#   CC_XML_LEAK_COOLDOWN      Minimum tool calls between repeat
#                             advisories per session. Default 30.
#   CC_XML_LEAK_TRANSCRIPT    Override transcript path
#                             (used by tests).
#   CC_XML_LEAK_STATE_DIR     Override state directory
#                             (used by tests). Default
#                             /tmp/cc-xml-leak.
#
# UPSTREAM REFERENCES:
#   #49747 (central case: long-payload XML leak in MCP tool calls,
#           filed 2026-04-17 as the precursor to the May surge)
#   #62123 (the broader "retry also failed" central case, 21 reactions)
#   #62344 (sub-pattern 12A, in-context few-shot poisoning)
#   #62467 (sub-pattern 12B, extended-thinking serialization)
#   #62700 (sub-pattern 12C, spurious malformed notice)
#
# RECOVERY ON A HIT:
#   The defect is at the decoder/serialization layer; explicit
#   prompt-layer rules ("do not emit XML tags") do not recover.
#   The operator-side workarounds documented in #49747:
#     - Shorten string-valued tool arguments. Paragraph-length
#       arguments almost always trigger the leak; one-phrase
#       arguments succeed reliably.
#     - Break a single verbose tool call into multiple smaller
#       tool calls with short payloads each.
#     - For MCP tools you control, lower the verbosity invited
#       by argument descriptions ("brief summary" rather than
#       "detailed explanation").
#     - If using a custom MCP server, consider validating with
#       a parser that recognizes both JSON and legacy XML tool-
#       use formats and reconciles them.
#   /clear (the 12A recovery) and model switching (the 12B
#   recovery) do not address 12D — the defect re-fires on the
#   next long-payload tool call in any session on Opus 4.7.
# ================================================================

set -u

if [ "${CC_XML_LEAK_DISABLE:-0}" = "1" ]; then
    exit 0
fi

LOOKBACK="${CC_XML_LEAK_LOOKBACK:-200}"
THRESHOLD="${CC_XML_LEAK_THRESHOLD:-1}"
COOLDOWN="${CC_XML_LEAK_COOLDOWN:-30}"
STATE_DIR="${CC_XML_LEAK_STATE_DIR:-/tmp/cc-xml-leak}"

INPUT=$(cat 2>/dev/null || true)

TRANSCRIPT_PATH="${CC_XML_LEAK_TRANSCRIPT:-}"
if [ -z "$TRANSCRIPT_PATH" ]; then
    TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

SAFE_SESSION=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_' | head -c 80)
[ -z "$SAFE_SESSION" ] && SAFE_SESSION="default"

mkdir -p "$STATE_DIR" 2>/dev/null

COUNTER_FILE="$STATE_DIR/${SAFE_SESSION}.count"
LASTFIRED_FILE="$STATE_DIR/${SAFE_SESSION}.lastfired"

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Extract every tool_use block's input from the trailing window,
# serialize it back to a compact JSON string, and check whether
# that string contains the literal XML tool-use markers. The
# markers, when they appear inside a JSON string value, are the
# decoder-flip signature documented in #49747.
#
# We check for any of the following substrings:
#   <parameter name=        — opening of a leaked parameter tag
#   </parameter>            — closing of a leaked parameter tag
#   <invoke name=           — opening of a leaked invoke wrapper
#   </invoke>               — closing of a leaked invoke wrapper
#   </function_calls>       — closing of a leaked function_calls wrapper
#
# Lines that fail to parse as JSON are silently skipped.
LEAKS=$(tail -n "$LOOKBACK" "$TRANSCRIPT_PATH" 2>/dev/null | jq -R -r '
    try (fromjson) catch null | select(. != null) | . as $obj |
    (($obj.content // $obj.message.content // [])) as $blocks |
    if ($blocks | type) == "array" then
        $blocks
        | map(select(.type == "tool_use" and (.input != null)))
        | map(.input | tojson)
        | .[]
    else
        empty
    end
' 2>/dev/null | grep -c -E '<parameter name=|</parameter>|<invoke name=|</invoke>|</function_calls>' || true)

LEAKS="${LEAKS:-0}"

if [ "$LEAKS" -lt "$THRESHOLD" ]; then
    exit 0
fi

LASTFIRED=$(cat "$LASTFIRED_FILE" 2>/dev/null || echo 0)
SINCE=$((COUNT - LASTFIRED))

if [ "$LASTFIRED" -gt 0 ] && [ "$SINCE" -lt "$COOLDOWN" ]; then
    exit 0
fi

echo "$COUNT" > "$LASTFIRED_FILE"

cat >&2 <<EOF

⚠️  Detected ${LEAKS} tool_use block(s) whose input contained the
    literal XML tool-use format markers (<parameter name=, </parameter>,
    <invoke name=, </invoke>, or </function_calls>) in the trailing
    ${LOOKBACK} transcript lines.

This is the structural signal for sub-pattern 12D (long-payload
attention dilution / decoder flip), the case filed in #49747. On
longer tool-call payloads, Opus 4.7 intermittently emits legacy
Anthropic XML tool-use syntax inside a JSON-format tool call — a
string-valued argument ends with a literal </parameter_name> tag,
and subsequent parameters appear as XML blocks instead of JSON
key-value pairs. Because the runtime parses tool calls as strict
JSON, the XML-declared parameters never reach the parsed arguments
object: required fields come through as undefined, schema
validation fails, and the model retries 4-6 times per logical turn
(each retry burns ~1k tokens before one finally stays short enough
to escape the decoder flip).

Sub-pattern 12D is distinct from:
  - 12A (#62344) → /clear to recover. 12A is in-context few-shot
    poisoning at the model attention layer. 12D is a decoder-layer
    format switch that does NOT depend on conversation history;
    /clear does not fix it.
  - 12B (#62467) → switch model / disable extended thinking. 12B
    is the extended-thinking serialization defect. 12D fires
    independently of extended thinking; switching model is the
    right workaround only if you are willing to drop to Sonnet
    for the duration of long-payload work.
  - 12C (#62700) → ignore the spurious notice, the tool succeeded.
    12C is a harness false-negative. 12D is a model true-negative:
    the tool genuinely failed to parse because required fields
    are missing from the JSON view.

The reporter (#49747) confirmed this is a decoder-level format
switch: explicit system-prompt rules forbidding XML tags in
tool-call strings did NOT prevent the bug. Recovery is at the
payload-length layer:

  - Shorten string-valued tool arguments. Paragraph-length
    arguments almost always trigger the leak; one-phrase
    arguments succeed reliably.
  - Break a single verbose tool call into multiple smaller
    tool calls with short payloads each.
  - For MCP tools you control, lower the verbosity invited by
    argument descriptions ("brief summary" rather than "detailed
    explanation"). The schema's prose shapes the model's
    expansion budget.
  - If using a custom MCP server, consider validating with a
    parser that recognizes both JSON and legacy XML tool-use
    formats and reconciles them, so the leak does not block
    progress entirely.

This filing predates the May 25-27 surge by more than a month
and is the precursor signal for Cluster 12; the upstream fix
surface depends on which root cause Anthropic prioritizes.

References: #49747 (the central long-payload case), #62123 (the
broader "retry also failed" central case), Cluster 12 in the
cc-safe-setup tracker:
https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html#cluster-tool-call-parsing

Silence: set CC_XML_LEAK_DISABLE=1.
Tune sensitivity: CC_XML_LEAK_THRESHOLD (default 1),
                  CC_XML_LEAK_LOOKBACK (default 200 lines),
                  CC_XML_LEAK_COOLDOWN (default 30 tool calls).

EOF

exit 0
