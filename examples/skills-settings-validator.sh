#!/bin/bash
# ================================================================
# skills-settings-validator.sh — Detect fabricated Skills-related
# settings fields in settings.json with no validation
# ================================================================
# PURPOSE:
#   Issue #62421 documents Claude Code accepting non-existent
#   Skills-related settings fields (e.g. `disabledSkills`) without
#   validation. A sub-agent or operator writes the fabricated field
#   into ~/.claude/settings.json or .claude/settings.local.json;
#   the write succeeds, restart succeeds, the targeted skills
#   remain active. Silent no-op.
#
#   The runtime has no schema validation for settings.json, so
#   typos, hallucinated fields, and out-of-date examples all
#   produce the same silent acceptance. Operators discover the
#   non-effect by trial-and-error, often after many sessions.
#
# DETECTION:
#   At SessionStart, scan settings.json and settings.local.json
#   for top-level keys matching common Skills-fabrication patterns:
#     - disabledSkills, enabledSkills (the canonical fabrication)
#     - skillsConfig, skillConfig, skillsSettings
#     - skillRouting, skillFilter, skillAllowlist, skillDenylist
#     - excludeSkills, includeSkills, allowedSkills, deniedSkills
#   These are the names sub-agents most commonly invent when asked
#   to "disable a skill" via settings.json. None exist in the
#   actual Claude Code schema.
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# OUTPUT:
#   When fabricated fields detected: a system-reminder via
#   hookSpecificOutput.additionalContext warning the model and
#   operator that the fields will be silently ignored, and
#   listing them by source file.
#
# CONFIGURATION:
#   CC_SKILLS_SETTINGS_FILES    — colon-separated list of settings
#                                 files to scan. Default scans
#                                 ~/.claude/settings.json,
#                                 ~/.claude/settings.local.json,
#                                 .claude/settings.json,
#                                 .claude/settings.local.json
#   CC_SKILLS_EXTRA_PATTERNS    — additional space-separated field
#                                 names to flag as fabricated.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/62421
# ================================================================

set -u

# Default fabricated-field patterns. Additional patterns can be
# added via CC_SKILLS_EXTRA_PATTERNS.
FABRICATED_FIELDS=(
    disabledSkills
    enabledSkills
    skillsConfig
    skillConfig
    skillsSettings
    skillRouting
    skillFilter
    skillAllowlist
    skillDenylist
    excludeSkills
    includeSkills
    allowedSkills
    deniedSkills
)

if [ -n "${CC_SKILLS_EXTRA_PATTERNS:-}" ]; then
    for pat in $CC_SKILLS_EXTRA_PATTERNS; do
        FABRICATED_FIELDS+=("$pat")
    done
fi

# Discover settings files. Default scans both global and project
# scope, both regular and local variants.
if [ -n "${CC_SKILLS_SETTINGS_FILES:-}" ]; then
    IFS=':' read -ra SETTINGS_FILES <<< "$CC_SKILLS_SETTINGS_FILES"
else
    SETTINGS_FILES=(
        "$HOME/.claude/settings.json"
        "$HOME/.claude/settings.local.json"
        ".claude/settings.json"
        ".claude/settings.local.json"
    )
fi

# Detection. For each file that exists, jq-read its top-level
# keys and check for any fabricated-field match.
FINDINGS=()
for file in "${SETTINGS_FILES[@]}"; do
    [ -f "$file" ] || continue
    # Skip if not valid JSON.
    jq empty "$file" 2>/dev/null || continue
    # Read top-level keys.
    KEYS=$(jq -r 'keys[]' "$file" 2>/dev/null || echo "")
    for key in $KEYS; do
        for fab in "${FABRICATED_FIELDS[@]}"; do
            if [ "$key" = "$fab" ]; then
                FINDINGS+=("$file: $key")
            fi
        done
    done
done

# Exit clean if nothing fabricated.
[ ${#FINDINGS[@]} -eq 0 ] && exit 0

# Build the warning message.
MSG="DETECTED: Skills-related settings fields with no schema definition (will be silently ignored).

These fields do not exist in the Claude Code settings schema. Writing them produces no error and no effect — the targeted skills remain active regardless. Common cause: a sub-agent invented the field name when asked to disable a skill via settings.json (issue #62421).

Findings:"
for finding in "${FINDINGS[@]}"; do
    MSG="$MSG
  - $finding"
done

MSG="$MSG

To actually disable a skill, remove or rename the SKILL.md file from the skill directory. To filter at runtime, use a PreToolUse hook that checks active context rather than relying on a non-existent settings field. See:
  https://github.com/anthropics/claude-code/issues/62421"

# Emit as JSON system-reminder so it surfaces to both the operator
# (stderr fallback) and the model (additionalContext).
jq -n --arg msg "$MSG" '
{
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $msg
    }
}'

exit 0
