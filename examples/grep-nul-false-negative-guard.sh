set -uo pipefail
#
# The registration was missing from this header. The installer reads TRIGGER
# and MATCHER from here and falls back to PreToolUse / Bash when both are
# absent, so this hook was being registered at a moment where the field it
# reads is always empty: it installed, it appeared in the settings, and it
# did nothing. Measured 2026-08-04 across examples/: 14 files were like this.
# TRIGGER: PostToolUse
# MATCHER: "Grep"
INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "Grep" ] || exit 0
RESP=$(printf '%s' "$INPUT" | jq -r '.tool_response // .tool_result // empty' 2>/dev/null)
printf '%s' "$RESP" | grep -qiE 'no matches found|no files found' || exit 0
SEARCH=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // "."' 2>/dev/null)
[ -e "$SEARCH" ] || exit 0
HIT=$(find "$SEARCH" -type f \
        -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null \
      | head -300 \
      | while read -r f; do
          if LC_ALL=C grep -qaP '\x00' "$f" 2>/dev/null; then echo "$f"; break; fi
        done)
if [ -n "$HIT" ]; then
  echo "[grep-nul-guard] Grep returned no matches, but '$HIT' contains a NUL byte." >&2
  echo "  ripgrep silently suppresses matches in files it treats as binary, so this" >&2
  echo "  'no matches' may be a false negative. Before concluding the pattern is absent," >&2
  echo "  re-search in text mode, e.g.  rg -a --text <pattern> <path>  (or  grep -aP)." >&2
fi
exit 0
