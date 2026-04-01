#!/bin/bash
# image-file-validator.sh — Block Read of fake image files that corrupt sessions
#
# Solves: When Claude reads a file with an image extension (.png, .jpg, etc.)
# that isn't actually an image (text, Git LFS pointer, error log), the content
# gets base64-encoded and sent to the API, causing a 400 error. The corrupt
# block stays in the JSONL transcript, permanently breaking the session.
#
# Uses `file --mime-type` (magic byte detection) to verify the file is
# actually an image before allowing the Read tool to process it.
#
# TRIGGER: PreToolUse  MATCHER: "Read"
# Related: https://github.com/anthropics/claude-code/issues/24387

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Only check files with image extensions
case "${FILE,,}" in
    *.png|*.jpg|*.jpeg|*.gif|*.bmp|*.webp|*.svg|*.ico|*.tiff|*.tif)
        ;;
    *)
        exit 0
        ;;
esac

# Verify the file is actually an image using magic bytes
MIME=$(file --mime-type -b "$FILE" 2>/dev/null)
case "$MIME" in
    image/*)
        # Valid image — allow
        exit 0
        ;;
    *)
        echo "{\"decision\": \"block\", \"reason\": \"Blocked: ${FILE##*/} has an image extension but is actually ${MIME}. Reading non-image files with image extensions corrupts the session (base64-encoded garbage causes API 400 errors). Rename the file or check its contents in an external terminal.\"}"
        exit 0
        ;;
esac
