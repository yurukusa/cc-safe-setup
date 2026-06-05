#!/bin/bash
# image-dimension-guard.sh — Block Read of oversized images that trigger a costly retry loop
#
# Solves: When Claude reads/attaches an image whose dimensions exceed the API
# limit (2000px per side for many-image requests), the API returns a
# 400 invalid_request_error. Claude Code silently removes the image and then
# RETRIES (observed 41x in #65636). Each retry mutates the conversation prefix,
# which invalidates the prompt cache: cache reads collapse and the whole
# context is re-written to the cache every turn, inflating session cost ~35x
# (one such loop was ~66% of a session's total cost).
#
# This checks an image's pixel dimensions BEFORE the Read tool sends it and
# blocks (or warns) when a side exceeds the limit, so the loop never starts.
# Dimensions are read from the file header with no external dependency
# (PNG/JPEG/GIF/BMP); it falls back to ImageMagick `identify` for other
# formats. It FAILS OPEN when dimensions cannot be determined, so it never
# breaks a normal Read.
#
# Complements image-file-validator.sh, which blocks FAKE images (wrong MIME);
# this one blocks REAL images that are simply too large.
#
# TRIGGER: PreToolUse  MATCHER: "Read"
# Config:
#   CC_IMAGE_DIM_LIMIT=2000   max px per side (2000 = many-image API limit; raise to 8000 for single-image-only workflows)
#   CC_IMAGE_DIM_GUARD=block  block | warn | off
# Related: https://github.com/anthropics/claude-code/issues/65636

INPUT=$(cat)

MODE="${CC_IMAGE_DIM_GUARD:-block}"
[ "$MODE" = "off" ] && exit 0
LIMIT="${CC_IMAGE_DIM_LIMIT:-2000}"

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Only raster formats have a pixel cap that triggers this 400 (skip svg/ico).
case "${FILE,,}" in
    *.png|*.jpg|*.jpeg|*.gif|*.bmp|*.webp|*.tiff|*.tif) ;;
    *) exit 0 ;;
esac

# Read "W H" from the file header with no hard dependency.
DIMS=$(python3 - "$FILE" 2>/dev/null <<'PY'
import sys, struct
def dims(path):
    with open(path, 'rb') as f:
        head = f.read(26)
        if head[:8] == b'\x89PNG\r\n\x1a\n':
            w, h = struct.unpack('>II', head[16:24]); return w, h
        if head[:6] in (b'GIF87a', b'GIF89a'):
            w, h = struct.unpack('<HH', head[6:10]); return w, h
        if head[:2] == b'BM':
            w, h = struct.unpack('<ii', head[18:26]); return abs(w), abs(h)
        if head[:2] == b'\xff\xd8':  # JPEG: scan SOF markers
            f.seek(2)
            while True:
                b = f.read(1)
                if not b: break
                if b != b'\xff': continue
                marker = f.read(1)
                while marker == b'\xff': marker = f.read(1)
                if not marker: break
                m = marker[0]
                if m in (0xd8, 0xd9) or 0xd0 <= m <= 0xd7: continue
                seg = f.read(2)
                if len(seg) < 2: break
                length = struct.unpack('>H', seg)[0]
                if m in (0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf):
                    data = f.read(5)
                    if len(data) < 5: break
                    h, w = struct.unpack('>HH', data[1:5]); return w, h
                f.seek(length - 2, 1)
    return None
try:
    r = dims(sys.argv[1])
    if r: print(r[0], r[1])
except Exception:
    pass
PY
)

# Fallback for formats the header parser skips (e.g. WEBP/TIFF).
if [ -z "$DIMS" ] && command -v identify >/dev/null 2>&1; then
    DIMS=$(identify -format '%w %h' "$FILE[0]" 2>/dev/null | head -1)
fi

# Fail open if dimensions are unknown — never break a normal Read.
[ -z "$DIMS" ] && exit 0
W=$(printf '%s' "$DIMS" | awk '{print $1}')
H=$(printf '%s' "$DIMS" | awk '{print $2}')
case "$W" in ''|*[!0-9]*) exit 0;; esac
case "$H" in ''|*[!0-9]*) exit 0;; esac

MAX="$W"; [ "$H" -gt "$W" ] && MAX="$H"
[ "$MAX" -le "$LIMIT" ] && exit 0

BASE="${FILE##*/}"
MSG="${BASE} is ${W}x${H}px, exceeding the ${LIMIT}px per-side API limit for many-image requests. Sending it returns a 400 error; Claude Code then silently strips the image and retries (observed 41x in #65636), which invalidates the prompt cache and can inflate session cost ~35x. Resize it first, e.g. 'convert ${BASE} -resize ${LIMIT}x${LIMIT} small-${BASE}' (ImageMagick) or 'sips -Z ${LIMIT} ${BASE}' (macOS), then read the smaller copy. Set CC_IMAGE_DIM_LIMIT to change the threshold, CC_IMAGE_DIM_GUARD=warn to only warn, or =off to disable."

if [ "$MODE" = "warn" ]; then
    echo "image-dimension-guard: $MSG" >&2
    exit 0
fi

# block (default): emit a structured block decision (exit 0, like image-file-validator).
jq -n --arg r "$MSG" '{decision: "block", reason: $r}'
exit 0
