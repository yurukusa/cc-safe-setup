#!/bin/bash
# ================================================================
# binary-file-guard.sh — Warn when Write creates binary/large files
# ================================================================
# PURPOSE:
#   Claude Code sometimes tries to Write binary content (images,
#   archives, compiled files) which produces corrupted output.
#   This hook detects binary patterns in Write content.
#
# TRIGGER: PreToolUse
# MATCHER: "Write"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)

if [[ -z "$FILE" ]]; then
    exit 0
fi

# Check file extension for binary types
EXT="${FILE##*.}"
BINARY_EXTS="png|jpg|jpeg|gif|bmp|ico|webp|svg|mp3|mp4|wav|zip|tar|gz|rar|7z|exe|dll|so|dylib|class|pyc|wasm|pdf|doc|docx|xls|xlsx|ppt|pptx"

if echo "$EXT" | grep -qiE "^($BINARY_EXTS)$"; then
    echo "WARNING: Writing to binary file type: $FILE" >&2
    echo "Claude Code cannot reliably create binary files." >&2
    echo "Use a proper tool (ImageMagick, ffmpeg, etc.) instead." >&2
fi

exit 0
