#!/bin/bash
# ================================================================
# settings-regression-tester.sh — Detect Claude Code version
#                                  bumps that may have silently
#                                  reset permission rules
# ================================================================
# PURPOSE:
#   Two May 2026 incidents documented permission-side regressions
#   that surfaced only after a routine Claude Code version bump:
#
#   #57491 — After v2.1.128, Allow rules in settings.json that had
#            been auto-approving for weeks (Bash(npm:*) and similar)
#            began re-prompting on every invocation. The settings
#            file was unchanged; the runtime's interpretation
#            had drifted.
#   #57486 — After the same bump, persistent memory: directives
#            that had been auto-loaded on previous sessions stopped
#            being referenced after auto-compaction. The user
#            assumed the configuration was still in effect.
#
#   Both incidents share a structural cause: the user's settings
#   were authored against version N, the runtime upgraded to N+1
#   silently, and the settings interpretation drifted. The user
#   has no signal that re-verification is needed.
#
#   On SessionStart, this hook records the current Claude Code
#   version and a hash of settings.json. On subsequent sessions,
#   if the version has changed since the last recorded run, it
#   warns the operator to re-confirm that Allow rules and memory:
#   directives still take effect as expected. State is kept under
#   ~/.claude/version-state.json.
#
# TRIGGER: SessionStart
#
# CONFIG:
#   CC_SETTINGS_REGRESSION_BLOCK=0   (0 = warn; 1 = exit 2)
#   CC_SETTINGS_REGRESSION_STATE=""  (override state file path;
#                                     default: ~/.claude/version-state.json)
#
# Born from:
#   https://github.com/anthropics/claude-code/issues/57491
#   https://github.com/anthropics/claude-code/issues/57486
# Related: chapter 9 of the May 2026 claim-verify case handbook
#          ("自動の点検の道具の素案 5 件" — proposed detection
#          tools 5 / 5, the fifth being settings-regression-tester)
# ================================================================

set -u

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-settings-regression-tester-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [settings-regression-tester]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="${CLAUDE_PROJECT_DIR:-}"

BLOCK="${CC_SETTINGS_REGRESSION_BLOCK:-0}"
STATE_FILE="${CC_SETTINGS_REGRESSION_STATE:-${HOME}/.claude/version-state.json}"

# Resolve `claude --version`. If unavailable (CI test, broken PATH),
# fall back to environment override; on total failure exit silently.
CURRENT_VERSION="${CC_SETTINGS_REGRESSION_VERSION_OVERRIDE:-}"
if [ -z "$CURRENT_VERSION" ]; then
    if command -v claude >/dev/null 2>&1; then
        CURRENT_VERSION=$(claude --version 2>/dev/null | head -n 1 | awk '{print $1}' || true)
    fi
fi
[ -z "$CURRENT_VERSION" ] && exit 0

# Hash the active settings.json files (user + project, each level).
hash_file() {
    [ -f "$1" ] || return 0
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

USER_SETTINGS="${HOME}/.claude/settings.json"
USER_LOCAL="${HOME}/.claude/settings.local.json"
PROJ_SETTINGS=""
PROJ_LOCAL=""
if [ -n "$CWD" ]; then
    PROJ_SETTINGS="${CWD}/.claude/settings.json"
    PROJ_LOCAL="${CWD}/.claude/settings.local.json"
fi

USER_HASH=$(hash_file "$USER_SETTINGS")
USER_LOCAL_HASH=$(hash_file "$USER_LOCAL")
PROJ_HASH=$(hash_file "$PROJ_SETTINGS")
PROJ_LOCAL_HASH=$(hash_file "$PROJ_LOCAL")

# Read prior state if present.
PRIOR_VERSION=""
if [ -f "$STATE_FILE" ]; then
    PRIOR_VERSION=$(jq -r '.version // empty' "$STATE_FILE" 2>/dev/null || true)
fi

# Always update state at the end of this run, even when nothing
# changes — this keeps the state file fresh and prevents the warning
# from firing on every session forever.
write_state() {
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
    jq -n \
        --arg v "$CURRENT_VERSION" \
        --arg t "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg uh "$USER_HASH" \
        --arg ul "$USER_LOCAL_HASH" \
        --arg ph "$PROJ_HASH" \
        --arg pl "$PROJ_LOCAL_HASH" \
        '{version:$v, recorded:$t, hashes:{user:$uh, user_local:$ul, project:$ph, project_local:$pl}}' \
        > "$STATE_FILE" 2>/dev/null || true
}

# First-ever run: record state and exit silently. Do not warn on
# the very first session because there is nothing to compare against.
if [ -z "$PRIOR_VERSION" ]; then
    write_state
    exit 0
fi

# Same version: nothing to flag. Refresh the state's recorded
# timestamp and exit.
if [ "$PRIOR_VERSION" = "$CURRENT_VERSION" ]; then
    write_state
    exit 0
fi

# Version changed. Build a list of representative Allow rules to
# remind the operator to re-verify.
collect_allow_rules() {
    local f="$1"
    [ -f "$f" ] || return 0
    jq -r '.permissions.allow[]? // empty' "$f" 2>/dev/null | head -n 6
}

ALLOW_SAMPLE=$(
    {
        collect_allow_rules "$USER_SETTINGS"
        collect_allow_rules "$USER_LOCAL"
        collect_allow_rules "$PROJ_SETTINGS"
        collect_allow_rules "$PROJ_LOCAL"
    } | sort -u | head -n 6
)

# Detect memory: directives that may need re-loading after the bump.
MEMORY_HITS=""
for f in "$USER_SETTINGS" "$USER_LOCAL" "$PROJ_SETTINGS" "$PROJ_LOCAL"; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    if grep -qE '"memory"[[:space:]]*:' "$f" 2>/dev/null; then
        MEMORY_HITS="${MEMORY_HITS}    ${f}\n"
    fi
done

printf '⚠️  settings-regression-tester: Claude Code version changed (%s -> %s).\n' "$PRIOR_VERSION" "$CURRENT_VERSION" >&2
printf '  Permission rules and memory directives can drift silently across\n' >&2
printf '  version bumps (Issues #57491, #57486). Re-verify before relying.\n' >&2

if [ -n "$ALLOW_SAMPLE" ]; then
    printf '\n  Active Allow rules to re-confirm:\n' >&2
    printf '%s\n' "$ALLOW_SAMPLE" | sed 's/^/    - /' >&2
fi

if [ -n "$MEMORY_HITS" ]; then
    printf '\n  memory directives present (may need re-loading post-compact):\n' >&2
    printf '%b' "$MEMORY_HITS" >&2
fi

printf '\n  References:\n' >&2
printf '    https://github.com/anthropics/claude-code/issues/57491\n' >&2
printf '    https://github.com/anthropics/claude-code/issues/57486\n' >&2
printf '  Recommended fix: run a representative tool (e.g. Bash(npm:test)) and confirm it auto-approves;\n' >&2
printf '  open a fresh session and verify memory: directives are referenced before continuing.\n' >&2

write_state

if [ "$BLOCK" = "1" ]; then
    exit 2
fi

exit 0
