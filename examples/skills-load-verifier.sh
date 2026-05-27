set -u
INPUT=$(cat)
MIN_DESC_LEN="${CC_SKILLS_MIN_DESC_LEN:-10}"
if [ -n "${CC_SKILLS_DIRS:-}" ]; then
    IFS=':' read -ra SKILLS_DIRS <<< "$CC_SKILLS_DIRS"
else
    SKILLS_DIRS=(
        "$HOME/.claude/skills"
        ".claude/skills"
    )
fi
FINDINGS=()
for skills_root in "${SKILLS_DIRS[@]}"; do
    [ -d "$skills_root" ] || continue
    for skill_dir in "$skills_root"/*; do
        [ -d "$skill_dir" ] || continue
        skill_name_from_dir=$(basename "$skill_dir")
        skill_md="$skill_dir/SKILL.md"
        if [ ! -f "$skill_md" ]; then
            FINDINGS+=("$skill_dir: missing SKILL.md (directory present but no SKILL.md file)")
            continue
        fi
        if [ ! -r "$skill_md" ]; then
            FINDINGS+=("$skill_md: unreadable (permission or dangling symlink)")
            continue
        fi
        first_line=$(head -n 1 "$skill_md" 2>/dev/null || echo "")
        if [ "$first_line" != "---" ]; then
            FINDINGS+=("$skill_md: missing YAML frontmatter (file does not start with ---)")
            continue
        fi
        frontmatter=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$skill_md" 2>/dev/null)
        if [ -z "$frontmatter" ]; then
            FINDINGS+=("$skill_md: empty or unterminated frontmatter block")
            continue
        fi
        name=$(printf '%s\n' "$frontmatter" | grep -E '^name:[[:space:]]*' | head -n 1 | sed -E 's/^name:[[:space:]]*//; s/[[:space:]]+$//; s/^["'\'']//; s/["'\'']$//')
        if [ -z "$name" ]; then
            FINDINGS+=("$skill_md: missing or empty 'name' field in frontmatter")
            continue
        fi
        description=$(printf '%s\n' "$frontmatter" | grep -E '^description:[[:space:]]*' | head -n 1 | sed -E 's/^description:[[:space:]]*//; s/[[:space:]]+$//; s/^["'\'']//; s/["'\'']$//')
        if [ -z "$description" ]; then
            FINDINGS+=("$skill_md: missing or empty 'description' field in frontmatter")
            continue
        fi
        desc_len=${#description}
        if [ "$desc_len" -lt "$MIN_DESC_LEN" ]; then
            FINDINGS+=("$skill_md: 'description' too short ($desc_len chars, minimum $MIN_DESC_LEN) — will likely be skipped or surface poorly")
            continue
        fi
        if [ "$name" != "$skill_name_from_dir" ]; then
            FINDINGS+=("$skill_md: 'name: $name' does not match directory name '$skill_name_from_dir' (slash command will use the frontmatter name, not the directory)")
            continue
        fi
    done
done
[ ${#FINDINGS[@]} -eq 0 ] && exit 0
MSG="DETECTED: Skills configured but malformed in a way that will silently fail to load.
Each Skill below has a structural problem that the Claude Code runtime does not surface as an error. The session proceeds without the Skill, and the model loses access to its slash command and instructions without any warning. Common causes: incomplete copy-paste from documentation, hand-edited frontmatter, missing SKILL.md after directory rename.
Findings:"
for finding in "${FINDINGS[@]}"; do
    MSG="$MSG
  - $finding"
done
MSG="$MSG
To fix each finding: open the SKILL.md file, ensure the frontmatter has the form
  ---
  name: <kebab-case-name-matching-directory>
  description: <one-sentence summary, at least $MIN_DESC_LEN chars>
  ---
After fixing, restart the session to verify the Skill loads. See related issues:
  https://github.com/anthropics/claude-code/issues/62421 (settings-side fabrication)
  https://github.com/anthropics/claude-code/issues/62049 (paths field silent no-op)"
jq -n --arg msg "$MSG" '
{
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $msg
    }
}'
exit 0
