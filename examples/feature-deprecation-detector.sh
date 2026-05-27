#!/bin/sh
# feature-deprecation-detector.sh — Detect Claude Code feature deprecations from tool output.
#
# Background:
#   On 2026-04-09 the `/buddy` companion was removed in v2.1.97 without changelog mention.
#   Issue #45596 ("Bring Back Buddy") accumulated 1,987 reactions, the second-largest
#   single feature request in anthropics/claude-code history. The structural failure pattern:
#   silent removal, no opt-in deprecation, no migration guidance.
#
#   This hook detects when a previously-working slash command, skill, or capability
#   suddenly returns "Unknown skill: X" or similar deprecation signals, and surfaces
#   the deprecation context to the operator before they spend time troubleshooting
#   what is actually a removed feature.
#
# Trigger: PostToolUse (advisory, exit 0)
# Detection axes:
#   1. "Unknown skill: <name>" pattern in tool output → likely deprecated slash command
#   2. "Command not found: /<name>" pattern → likely removed CLI command
#   3. "Skill <name> is deprecated" pattern → explicit deprecation notice
#   4. "This feature has been removed" pattern → explicit removal notice
#
# When detected, the hook outputs a NOTICE pointing to:
#   - The Claude Code release notes (where deprecations should be documented)
#   - The cc-safe-setup cluster tracker (community-tracked deprecation patterns)
#   - The relevant GitHub issue cluster if known (e.g. #45596 for /buddy)
#
# Environment variables:
#   CC_DEPRECATION_QUIET=1  → suppress all output (default 0)
#   CC_DEPRECATION_KNOWN_REMOVALS=/path → custom known-removal list (one slash command per line)

set -eu

INPUT=$(cat)

# Extract tool output (stderr or stdout). PostToolUse provides tool_response.output.
TOOL_OUTPUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.output // .tool_response.content // empty' 2>/dev/null || true)
[ -z "$TOOL_OUTPUT" ] && exit 0

# Skip if quiet mode requested
QUIET="${CC_DEPRECATION_QUIET:-0}"
if [ "$QUIET" = "1" ]; then
    exit 0
fi

# Built-in known removals (slash commands or features that have been silently removed)
# Format: "command|release|context|reference"
KNOWN_REMOVALS_BUILTIN='
/buddy|v2.1.97 (2026-04-09)|Companion feature removed without changelog mention|https://github.com/anthropics/claude-code/issues/45596
'

# Allow custom known-removal list via environment
CUSTOM_LIST="${CC_DEPRECATION_KNOWN_REMOVALS:-}"
if [ -n "$CUSTOM_LIST" ] && [ -f "$CUSTOM_LIST" ]; then
    KNOWN_REMOVALS_BUILTIN="${KNOWN_REMOVALS_BUILTIN}$(printf '\n')$(cat "$CUSTOM_LIST")"
fi

# Detection axis 1: "Unknown skill: X" → check against known removals
detected_command=""
detected_context=""
detected_reference=""

# Pattern 1: Unknown skill / Unknown command
if printf '%s' "$TOOL_OUTPUT" | grep -qE 'Unknown skill:|Unknown command:|Command not found:'; then
    # Extract the command name
    skill_name=$(printf '%s' "$TOOL_OUTPUT" | grep -oE '(Unknown skill: [a-zA-Z0-9_-]+|Unknown command: /[a-zA-Z0-9_-]+|Command not found: /[a-zA-Z0-9_-]+)' | head -1 | sed -E 's/.*[: /]//')

    if [ -n "$skill_name" ]; then
        # Check known removals
        cmd_key="/${skill_name}"
        line=$(printf '%s' "$KNOWN_REMOVALS_BUILTIN" | grep -F "${cmd_key}|" | head -1)
        if [ -n "$line" ]; then
            detected_command="$cmd_key"
            detected_context=$(printf '%s' "$line" | cut -d'|' -f3)
            detected_reference=$(printf '%s' "$line" | cut -d'|' -f4)
            release_info=$(printf '%s' "$line" | cut -d'|' -f2)

            cat >&2 <<EOF
NOTICE: \`${detected_command}\` appears to have been removed from Claude Code.
  Release: ${release_info}
  Context: ${detected_context}
  Reference: ${detected_reference}
  Cluster tracking: https://github.com/yurukusa/cc-safe-setup (deprecation pattern monitoring)
EOF
            exit 0
        fi

        # Unknown command but not in known list — still surface it as a possible deprecation
        cat >&2 <<EOF
NOTICE: Skill or command \`${skill_name}\` not recognized.
  If this previously worked, it may have been deprecated without changelog notice.
  Check release notes: https://docs.anthropic.com/en/release-notes/claude-code
  Report or check existing reports: https://github.com/anthropics/claude-code/issues?q=${skill_name}
EOF
        exit 0
    fi
fi

# Pattern 2: Explicit deprecation notice
if printf '%s' "$TOOL_OUTPUT" | grep -qiE 'is deprecated|has been deprecated|has been removed|feature has been removed'; then
    matched_line=$(printf '%s' "$TOOL_OUTPUT" | grep -iE 'is deprecated|has been deprecated|has been removed|feature has been removed' | head -1)
    cat >&2 <<EOF
NOTICE: Deprecation signal detected in tool output:
  > ${matched_line}
  Check release notes for migration guidance: https://docs.anthropic.com/en/release-notes/claude-code
EOF
    exit 0
fi

exit 0
