#!/bin/bash
# write-nul-corruption-detector.sh — Detect NUL-byte corruption after Write/Edit
#
# Solves: On some setups (notably the Windows Cowork workspace mount) Claude
#         Code's Write/Edit tools return success while the file written to the
#         host disk is silently corrupted — the tail is replaced with NUL bytes
#         (\x00). Because the byte count can be unchanged, `wc -c` and a glance
#         at `tail` look fine, so the corruption passes review and only surfaces
#         later when the file fails to parse or build. (GitHub Issue #70414)
#
# How it works:
#   After Write or Edit, if the target is a text-ish file (not a known binary
#   extension) and contains NUL bytes, raise exit 2 so Claude is told the write
#   landed corrupted and should re-verify, instead of trusting the reported
#   success. NUL padding survives a byte-count check; this catches it. Pure
#   truncation without NUL bytes needs a separate size comparison and is out of
#   scope for this hook.
#
# Why exit 2 (not a silent warning): a corrupted write is a data-integrity event
# — the model just recorded "done" against a file that is broken on disk. exit 2
# feeds the message back so the model stops trusting the success and re-checks.
#
# TRIGGER: PostToolUse  MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.file // empty' 2>/dev/null)

[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

# Skip known binary formats — NUL bytes are legitimate there, not corruption.
case "$FILE" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.bmp|*.tiff|*.pdf|*.zip|*.gz|*.tgz|*.bz2|*.xz|*.7z|*.rar|*.tar|*.jar|*.war|*.class|*.so|*.o|*.a|*.dylib|*.dll|*.exe|*.bin|*.wasm|*.woff|*.woff2|*.ttf|*.otf|*.eot|*.mp3|*.mp4|*.wav|*.avi|*.mov|*.mkv|*.flac|*.ogg|*.webm|*.pyc|*.pdb|*.db|*.sqlite|*.sqlite3|*.parquet|*.dat)
        exit 0 ;;
esac

# Detect NUL bytes by counting them out. The previous check used `grep -aPq`,
# but -P is GNU-only: on BSD grep (macOS) it failed, the failure was swallowed
# by 2>/dev/null, and the corrupted write was reported as clean. Comparing the
# byte count with and without NULs is exact and works on every platform.
if [ "$(wc -c < "$FILE" 2>/dev/null || echo 0)" -ne "$(tr -d '\000' < "$FILE" 2>/dev/null | wc -c)" ]; then
    echo "⚠ NUL bytes found in $FILE right after Write/Edit — the write may have landed corrupted (e.g. Cowork/Windows silent NUL-padding, #70414)." >&2
    echo "  The tool reported success, but a text file should not contain NUL. The byte count can be unchanged, so 'wc -c' and 'tail' will not reveal this." >&2
    echo "  Verify:  tr -d '\\000' < \"$FILE\" | wc -c   (compare with wc -c on the file itself)" >&2
    echo "  Inspect: cat -v \"$FILE\" | tail        (NUL shows as ^@)" >&2
    echo "  Recover: git checkout -- \"$FILE\"  (if tracked), or re-write and re-verify before trusting 'done'." >&2
    exit 2
fi

exit 0
