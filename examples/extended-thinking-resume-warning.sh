#!/bin/bash
# extended-thinking-resume-warning.sh — Warn before resuming a session whose
#                                        transcript carries the 13A precursor.
#
# Solves: Cluster 13 Axis A — the resume serialization corruption that wedges
#         extended-thinking sessions on a permanent API 400. Claude Code
#         persists thinking blocks to the session transcript with the
#         `thinking` field emptied to "" but the `signature` field retained
#         from the original response. When the session is resumed, the client
#         sends `{"thinking": "", "signature": "<original>"}` to the API; the
#         signature was computed over the original non-empty thinking text,
#         so validation fails and the session is permanently wedged.
#
# Issue addressed: #63147 (central case, 33 reactions). Field guide:
#         https://gist.github.com/yurukusa/8c6be069f602399238356a9c9b719a45
#
# How it works: SessionStart hook. When the session source indicates a resume
#   or continue, finds the transcript directory for the current project
#   (~/.claude/projects/<slug>/) and reads the most recent .jsonl file. Scans
#   the file for assistant thinking blocks where `thinking` is empty but
#   `signature` is non-empty — the on-disk shape that becomes the 13A wedge
#   on the next API request.
#
#   If the pattern is present, the hook emits a stderr advisory naming
#   sub-pattern 13A, pointing at the field guide, and listing the recommended
#   actions (save state, start fresh). The hook NEVER blocks — exit 0 always.
#
# Heuristic notes:
#   - Claude Code's project slug is the absolute project dir with leading
#     slash stripped and remaining `/` replaced with `-` (e.g.
#     `/home/u/proj` → `home-u-proj`). The hook recomputes this from
#     CC_PROJECT_DIR or PWD; if the layout differs in a future client
#     version the hook fails open rather than emitting a stale warning.
#   - Trailing thinking blocks in healthy sessions are *also* frequently
#     stored empty-but-signed (per #63147 evidence), so the hook fires on
#     a SHAPE that is common, not a SHAPE that is uniquely broken. The
#     advisory is calibrated to match: it warns the operator that resume
#     may hit the 400, not that it definitely will.
#
# Environment variables:
#   CC_EXTENDED_THINKING_RESUME_DISABLE=1   — disable advisory entirely
#   CC_EXTENDED_THINKING_RESUME_VERBOSE=1   — include per-block sizes
#   CC_EXTENDED_THINKING_RESUME_TRANSCRIPT  — override transcript path (test)
#   CC_EXTENDED_THINKING_RESUME_FORCE=1     — fire regardless of source (test)
#
# TRIGGER: SessionStart
# MATCHER: "" (filters event internally)

set -uo pipefail

INPUT=$(cat)
[ "${CC_EXTENDED_THINKING_RESUME_DISABLE:-0}" = "1" ] && exit 0

EVENT=$(printf '%s' "$INPUT" | jq -r '.event // .hook_event_name // empty' 2>/dev/null)
case "$EVENT" in
    session_start|SessionStart|sessionstart) ;;
    *) exit 0 ;;
esac

# Only fire on resume/continue. Some clients send `source: "resume"`,
# others `source: "continue"`, others omit it. Fail-open: when the source
# field is missing or unknown, default to scanning (the cost is one
# advisory if the transcript happens to carry the precursor shape).
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)
if [ "${CC_EXTENDED_THINKING_RESUME_FORCE:-0}" != "1" ]; then
    case "$SOURCE" in
        resume|continue|"") ;;
        startup|fresh|new) exit 0 ;;
        *) ;;  # unknown source — scan anyway
    esac
fi

# Locate the transcript file.
LATEST="${CC_EXTENDED_THINKING_RESUME_TRANSCRIPT:-}"
if [ -z "$LATEST" ]; then
    PROJ_DIR="${CC_PROJECT_DIR:-$PWD}"
    SLUG=$(printf '%s' "$PROJ_DIR" | sed 's|^/||; s|/|-|g')
    TRANSCRIPT_DIR="${HOME}/.claude/projects/${SLUG}"
    [ -d "$TRANSCRIPT_DIR" ] || exit 0
    LATEST=$(ls -t "$TRANSCRIPT_DIR"/*.jsonl 2>/dev/null | head -1)
fi
[ -n "$LATEST" ] || exit 0
[ -r "$LATEST" ] || exit 0

# Scan for empty-thinking + non-empty-signature blocks. Read each line as
# raw text and use fromjson? so malformed lines are silently skipped rather
# than aborting the scan.
SCAN=$(jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "thinking" and ((.thinking // "") | length) == 0 and ((.signature // "") | length) > 0) | (.signature | length)' "$LATEST" 2>/dev/null || true)
[ -z "$SCAN" ] && exit 0

COUNT=$(printf '%s\n' "$SCAN" | grep -c .)
SIG_LENGTHS=$(printf '%s' "$SCAN" | tr '\n' ' ')

{
    echo "[extended-thinking-resume-warning] Cluster 13A precursor detected."
    echo ""
    echo "  Transcript: $LATEST"
    echo "  Empty-text signed thinking block(s): ${COUNT}"
    echo ""
    echo "Resuming this session may hit the persistent API 400:"
    echo "    \`thinking\` blocks in the latest assistant message cannot be modified."
    echo ""
    echo "Once it fires, the wedge persists for the life of the transcript —"
    echo "every subsequent turn re-sends the same corrupted message and re-fails."
    echo ""
    echo "Recommended actions:"
    echo "  - If resume is critical, save state from the running process now."
    echo "  - Otherwise start a fresh session; the wedge cannot be cleared in-session."
    echo "  - Disable extended thinking via /model if your next task allows."
    echo ""
    echo "Reference: https://github.com/anthropics/claude-code/issues/63147"
    echo "Field guide: https://gist.github.com/yurukusa/8c6be069f602399238356a9c9b719a45"
    if [ "${CC_EXTENDED_THINKING_RESUME_VERBOSE:-0}" = "1" ]; then
        echo ""
        echo "(per-block signature lengths: ${SIG_LENGTHS})"
    fi
} >&2

exit 0
