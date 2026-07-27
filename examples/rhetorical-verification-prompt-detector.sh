#!/bin/bash
# rhetorical-verification-prompt-detector.sh — UserPromptSubmit hook
# Trigger: UserPromptSubmit
# Matcher: ""
#
# Solves: Issue #60107 — "the agent treated my question as rhetorical and
#         confirmed". User asked a verification question; agent emitted an
#         unconditional confirmation without running any verification step.
#         User trusted the confirmation, deployed to production, and the
#         deployed system crashed in full.
#
# Class of failure: claim-vs-reality divergence at the verification layer.
#         The user's explicit verification intent ("is this really working?",
#         "did this actually deploy?", "are you sure this is safe?") gets
#         flattened by the model into a rhetorical-question reading, which
#         the model then answers with social affirmation rather than with
#         a tool-driven verification step.
#
# HOW IT WORKS:
#   When the user submits a prompt containing verification-intent markers,
#   the hook emits an additionalContext payload (via hookSpecificOutput)
#   that explicitly tells the agent: this is a verification request, not
#   a rhetorical one — do not respond with a bare affirmation; either run
#   verification tool calls (Bash, Read, Grep) or state explicitly that
#   verification was not performed.
#
# WHY THIS MATTERS:
#   The 60107 failure shape is one of the cleanest examples of the broader
#   pattern where the response surface asserts a claim that the runtime
#   never verified. Most prevention efforts focus on the agent's *output*
#   (caveat checkers, claim-vs-caveat validators). This hook addresses the
#   *input* side: by labeling the user's prompt explicitly as a verification
#   request before the agent processes it, the rhetorical-reading failure
#   mode is harder to enter in the first place.
#
# TRIGGER: UserPromptSubmit
# MATCHER: ""
#
# CONFIGURATION:
#   CC_RHETORICAL_VERIFY_DISABLE=1   disable the hook entirely
#   CC_RHETORICAL_VERIFY_LOG=path    append detection events (default off)
#
# SAFETY:
#   - Read-only on the prompt; never modifies the user's input.
#   - Emits advisory context via hookSpecificOutput; does not block the prompt.
#   - The user's exact prompt still reaches the agent unchanged.
#   - Exit 0 always; never blocks the session.
#
# REFERENCES:
#   - anthropics/claude-code#60107 (2026-05-18, the canonical case)
#   - https://gist.github.com/yurukusa/a5b2a32ca57e75eb1e96adcf67bcf2c3 (the
#     nine-axis verification compilation, Axis 8 for self-acknowledged
#     structural divergence)
set -euo pipefail

[ "${CC_RHETORICAL_VERIFY_DISABLE:-}" = "1" ] && exit 0

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
[ -z "$PROMPT" ] && exit 0

# Detection patterns — verification-intent markers.
# English and Japanese forms are both checked.
# These are conservative: only match phrases that strongly imply
# the user is asking for a *check*, not a *task*.
EN_PATTERNS='are you sure|are you certain|did (this|that|it) actually|did (this|that|it) really|did you (actually|really|verify|check|confirm)|can you (confirm|verify|double-?check|make sure)|is (this|that|it) (really|actually|definitely|truly) (working|correct|safe|done|deployed|complete|finished)|is (this|that|it) safe to|please (confirm|verify|double-?check|make sure)|just to (confirm|verify|be sure|double-?check)|double[ -]check|sanity check|are we (sure|certain|good)'

JA_PATTERNS='本当に|確かに|大丈夫(です)?(か|\?)|本当か|確認した|確認して(くれ|ください)|もう一度確認|再確認|間違いない(か|ですか|\?)?|本当だ?ね|チェックして|本当に(動いて|できて|終わって|成功して)|間違いなく'

MATCHED_MARKER=""

if echo "$PROMPT" | grep -qiE "$EN_PATTERNS"; then
    MATCHED_MARKER=$(echo "$PROMPT" | grep -oiE "$EN_PATTERNS" | head -1)
elif echo "$PROMPT" | grep -qE "$JA_PATTERNS"; then
    MATCHED_MARKER=$(echo "$PROMPT" | grep -oE "$JA_PATTERNS" | head -1)
fi

[ -z "$MATCHED_MARKER" ] && exit 0

# Optional logging
if [ -n "${CC_RHETORICAL_VERIFY_LOG:-}" ]; then
    {
        printf '[%s] rhetorical-verify-detected: marker=%q prompt_head=%q\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MATCHED_MARKER" "${PROMPT:0:200}"
    } >> "$CC_RHETORICAL_VERIFY_LOG" 2>/dev/null || true
fi

# Emit additionalContext via hookSpecificOutput.
# Claude Code reads this as a system note to the agent.
ADDITIONAL_CONTEXT="Verification-intent detected in this user prompt (marker: \"${MATCHED_MARKER}\"). Treat this prompt as a verification request, NOT as a rhetorical question. Do not respond with a bare affirmation, social-confirmation phrase, or unverified \"yes\" / \"that's correct\" / \"all good\" / \"安心してください\". Instead: (1) run concrete verification tool calls (Bash, Read, Grep, file tests, status checks) appropriate to what is being verified; or (2) if verification is impossible in this context, state EXPLICITLY that verification was not performed and identify which check is missing. This guard exists because anthropics/claude-code#60107 documents a case where a verification question was read as rhetorical, an unverified confirmation was emitted, and the user's production system crashed in full as a direct consequence."

# Produce JSON output for hookSpecificOutput
jq -n \
    --arg ctx "$ADDITIONAL_CONTEXT" \
    '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: $ctx
        }
    }'

exit 0
