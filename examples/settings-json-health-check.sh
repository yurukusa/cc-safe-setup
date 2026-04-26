#!/bin/bash
# settings-json-health-check.sh — settings corruption guard (Incident 10)
# Why: A malformed settings.json can silently break the session (hook
#      definitions ignored, permissions reset to defaults) and the built-in
#      /doctor diagnostic can be dismissed by the user, leaving no warning.
#      This hook runs at SessionStart, validates both user-level and
#      project-level settings.json as JSON, writes a dated backup if a file
#      fails to parse, and exits non-zero so Claude Code refuses to proceed
#      with a broken configuration.
# Event: SessionStart
# Action: jq parse both settings files. If either fails: backup + refuse.
#         If /doctor has been dismissed recently: warn on stderr (does not
#         refuse the session, only reminds the user).
#
# Environment:
#   CC_SKIP_DOCTOR_CHECK=1        suppress the /doctor dismissed warning
#   SETTINGS_HEALTH_USER_PATH     override (default ~/.claude/settings.json)
#   SETTINGS_HEALTH_PROJECT_PATH  override (default ./.claude/settings.json)

set -u

USER_SETTINGS="${SETTINGS_HEALTH_USER_PATH:-${HOME}/.claude/settings.json}"
PROJECT_SETTINGS="${SETTINGS_HEALTH_PROJECT_PATH:-./.claude/settings.json}"

INPUT=$(cat 2>/dev/null)   # consume stdin if piped; SessionStart may or may not pipe

backup_and_warn() {
  local path="$1"
  local backup="${path}.broken.$(date +%Y%m%d-%H%M%S)"
  cp -p "$path" "$backup" 2>/dev/null && \
    echo "⚠ settings-json-health-check: $path failed to parse, backup written to $backup" >&2
  echo "  Fix or restore before continuing. Claude Code will not read a broken settings file." >&2
}

RC=0

for path in "$USER_SETTINGS" "$PROJECT_SETTINGS"; do
  if [ -s "$path" ]; then
    if ! jq -e '.' "$path" >/dev/null 2>&1; then
      backup_and_warn "$path"
      RC=2
    fi
  fi
done

# Check for /doctor dismissal. Several CC versions record this in a sentinel
# file at ~/.claude/doctor-dismissed.* — pattern varies, so we match any
# file matching the prefix and warn if one was written in the last 30 days.
if [ "${CC_SKIP_DOCTOR_CHECK:-0}" != "1" ]; then
  DISMISSED=$(find "${HOME}/.claude" -maxdepth 2 -name 'doctor-dismissed*' -mtime -30 -print 2>/dev/null | head -1)
  if [ -n "$DISMISSED" ]; then
    echo "ℹ settings-json-health-check: /doctor diagnostic has been dismissed ($DISMISSED)" >&2
    echo "  Run /doctor again to see current diagnostics, or set CC_SKIP_DOCTOR_CHECK=1 to silence this notice." >&2
  fi
fi

exit "$RC"
