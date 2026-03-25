INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]] && exit 0
[ -z "$FILE" ] && exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
[ ! -f "$FILE" ] && exit 0
CKPT_DIR=".claude/checkpoints"
mkdir -p "$CKPT_DIR" 2>/dev/null
BASENAME=$(basename "$FILE")
TIMESTAMP=$(date +%H%M%S)
CKPT_FILE="${CKPT_DIR}/${BASENAME}.${TIMESTAMP}.bak"
cp "$FILE" "$CKPT_FILE" 2>/dev/null
ls -t "${CKPT_DIR}/${BASENAME}".*.bak 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null
exit 0
