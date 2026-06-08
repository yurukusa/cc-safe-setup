#!/bin/bash
# disabled-feature-toggle-advisor.sh — SessionStart advisory that surfaces
# feature DISABLE / opt-out toggles set in your settings.json `env` block, so
# you notice one a plugin installer flipped without telling you.
#
# Why: any plugin installer can write `~/.claude/settings.json` freely. Real
# case (#66232): the claude-mem plugin wrote CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
# during install with no consent and no warning. A user with 75 accumulated
# memory files saw apparent total memory loss on the next session — the files
# were intact on disk, just no longer loaded — and spent ~30 minutes diagnosing
# what looked like catastrophic data loss. The same vector flips ANY env toggle
# (telemetry, 1M context, interleaved thinking, growthbook, ...), and the user
# has no way to tell which a plugin touched without reading the file.
#
# What this does: at SessionStart, list every *DISABLE* / *NONESSENTIAL* /
# *OPT_OUT* env key set to a truthy value in user + project settings.json, and
# name the built-in behavior each one turns off. The point is recognition: if
# you did not set one yourself, an installer probably did.
#
# Gap this fills: memory-chain-audit.sh treats CLAUDE_CODE_DISABLE_AUTO_MEMORY
# as a cost-saving you opt INTO; it never warns when the toggle is set against
# your intent. No existing hook surfaces silently-set disable toggles.
#
# Honest scope: ADVISORY only. It never blocks and cannot tell whether you or a
# plugin set a toggle — it only makes the toggles visible so you can decide.
# Silent when nothing is disabled.
#
# TRIGGER: SessionStart  MATCHER: ""
# Config: CC_DISABLE_TOGGLE_ADVISOR=off   disable entirely (default: on)
# Related: https://github.com/anthropics/claude-code/issues/66232

[ "${CC_DISABLE_TOGGLE_ADVISOR:-on}" = "off" ] && exit 0

INPUT=$(cat 2>/dev/null)

# Resolve project dir for project-level settings (env first, then payload cwd).
PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ]; then
    PROJ=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi

# Emit the env keys in a settings file that look like a disable/opt-out toggle
# AND are set to a truthy value (1 / true / yes / on). Ignore parse errors.
collect() {
    [ -r "$1" ] || return 0
    jq -r '
        (.env // {}) | to_entries[]
        | select(.key | test("DISABLE|NONESSENTIAL|OPT_?OUT"; "i"))
        | select((.value|tostring|ascii_downcase) as $v
                 | ($v=="1" or $v=="true" or $v=="yes" or $v=="on"))
        | .key
    ' "$1" 2>/dev/null
}

found=$( {
    collect "$HOME/.claude/settings.json"
    collect "$HOME/.claude/settings.local.json"
    if [ -n "$PROJ" ]; then
        collect "$PROJ/.claude/settings.json"
        collect "$PROJ/.claude/settings.local.json"
    fi
} | sort -u )

# Nothing disabled → stay silent (advisory hooks must not add noise).
[ -z "$found" ] && exit 0

{
    echo "disabled-feature-toggle-advisor: feature DISABLE toggles are active in your settings.json env block:"
    while IFS= read -r k; do
        [ -z "$k" ] && continue
        case "$k" in
            *AUTO_MEMORY*)  note="persistent memory will NOT load — your memory files stay on disk but look lost (#66232)" ;;
            *1M_CONTEXT*)   note="1M context window is turned off" ;;
            *INTERLEAVED*)  note="interleaved thinking is turned off" ;;
            *NONESSENTIAL*|*TELEMETRY*|*ERROR_REPORTING*|*GROWTHBOOK*) note="telemetry / server-side experiments are turned off" ;;
            *)              note="a built-in behavior is turned off" ;;
        esac
        echo "  - ${k}  →  ${note}"
    done <<EOF
$found
EOF
    echo "If you did not set these yourself, a plugin installer may have written them silently"
    echo "(real case: #66232, a plugin disabled auto-memory on install). Review the env block of"
    echo "~/.claude/settings.json and remove a key to restore that feature. Set"
    echo "CC_DISABLE_TOGGLE_ADVISOR=off to silence this notice."
} >&2

exit 0
