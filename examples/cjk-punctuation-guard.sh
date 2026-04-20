#!/bin/bash
# cjk-punctuation-guard.sh — Detect CJK punctuation corruption after Write/Edit
#
# Solves: Claude Code's Write and Edit tools silently convert full-width CJK
#         punctuation to half-width ASCII (，→, 。→. 「→" etc.) without warning.
#         This corrupts Chinese, Japanese, and Korean text.
#         (GitHub Issue #50975)
#
# How it works:
#   After Write or Edit, checks if the file contains CJK characters.
#   If yes, runs git diff to see if any full-width punctuation was replaced
#   with half-width equivalents in the same commit.
#
# TRIGGER: PostToolUse  MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.file // empty' 2>/dev/null)

[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

# Only check files that contain CJK characters
if ! grep -Pq '[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]' "$FILE" 2>/dev/null; then
    exit 0
fi

# Check git diff for punctuation changes (full-width → half-width)
DIFF=$(git diff -- "$FILE" 2>/dev/null)
[ -z "$DIFF" ] && exit 0

# Detect suspicious patterns: removed full-width, added half-width in same hunk
# Common corruptions: ，→, 。→. 、→, ：→: ；→; ！→! ？→? 「→" 」→" （→( ）→)
REMOVED_FW=$(echo "$DIFF" | grep '^-' | grep -Pc '[，。、：；！？「」（）【】『』]' 2>/dev/null || echo 0)
ADDED_HW=$(echo "$DIFF" | grep '^+' | grep -Pc '[,\.;:!\?\(\)\[\]]' 2>/dev/null || echo 0)

if [ "$REMOVED_FW" -gt 0 ] && [ "$ADDED_HW" -gt 0 ]; then
    echo "⚠ WARNING: CJK punctuation may have been corrupted in $FILE" >&2
    echo "  $REMOVED_FW lines with full-width punctuation removed" >&2
    echo "  $ADDED_HW lines with half-width punctuation added" >&2
    echo "  Review: git diff -- \"$FILE\"" >&2
    echo "  Undo:   git checkout -- \"$FILE\"" >&2
    # Warning only (exit 0), not blocking — the write already happened
fi

exit 0
