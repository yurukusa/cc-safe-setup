#!/bin/bash
# sandbox-relative-path-audit.sh — Catch sandbox filesystem rules that look set but do nothing
#
# WHAT THIS CATCHES (all three make a rule you wrote have zero effect, with no error):
#
#   1. Rules written under the wrong key. Sandbox filesystem rules live at
#      `sandbox.filesystem.denyRead` (and denyWrite / allowRead / allowWrite).
#      Writing them under `permissions.*` is silently ignored — that key holds
#      tool permission rules, not sandbox paths. This is the easiest mistake to
#      make because both are called "deny" and both live in settings.json.
#
#   2. Filesystem rules present while the sandbox is off. `sandbox.filesystem.*`
#      only takes effect when the sandbox is enabled (`sandbox.enabled: true`,
#      or enabled from the /sandbox panel). Rules sitting under a disabled
#      sandbox protect nothing.
#
#   3. Deny paths written with a trailing slash, on Claude Code older than
#      2.1.224. `denyRead: "~/.aws/"` was silently bypassable on Linux and macOS
#      until that release. Writing the same path without the trailing slash works
#      on every version.
#
# HISTORY (2026-08-08): this hook used to read `permissions.denyRead` and warn
# that relative paths are silently ignored. Both were wrong against the current
# spec — the key never held sandbox paths, so the check found nothing on any
# machine, and relative paths are NOT ignored: they resolve against the settings
# file's own location (the official example uses `"allowRead": ["."]`). The file
# name is kept so existing settings.json registrations keep working.
#
# TRIGGER: PreToolUse  MATCHER: "Bash|Write|Edit"
# Always exits 0 — this warns, it never blocks.

INPUT=$(cat)

# Only run once per session
MARKER="/tmp/cc-sandbox-audit-$$"
[ -f "$MARKER" ] && exit 0
touch "$MARKER"

command -v jq >/dev/null 2>&1 || exit 0

SETTINGS_FILES=""
for F in "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" \
         ".claude/settings.json" ".claude/settings.local.json"; do
    [ -f "$F" ] && SETTINGS_FILES="$SETTINGS_FILES $F"
done
[ -z "$SETTINGS_FILES" ] && exit 0

FOUND=0

for SFILE in $SETTINGS_FILES; do
    # A settings file that does not parse is its own failure; other hooks report it.
    jq empty "$SFILE" >/dev/null 2>&1 || continue

    # --- 1. sandbox path rules written under permissions.* ---------------
    for KEY in denyRead denyWrite allowRead allowWrite; do
        WRONG=$(jq -r ".permissions.${KEY}[]? // empty" "$SFILE" 2>/dev/null)
        [ -z "$WRONG" ] && continue
        echo "SANDBOX WARNING: '${KEY}' is under 'permissions' in $SFILE and has no effect." >&2
        echo "  Sandbox filesystem rules belong at sandbox.filesystem.${KEY}." >&2
        echo "  Move them:  { \"sandbox\": { \"enabled\": true, \"filesystem\": { \"${KEY}\": [ ... ] } } }" >&2
        FOUND=1
    done

    # --- 2. filesystem rules present but sandbox not enabled --------------
    HAS_FS=$(jq -r '(.sandbox.filesystem // {}) | keys | length' "$SFILE" 2>/dev/null)
    if [ "${HAS_FS:-0}" -gt 0 ]; then
        # Do NOT write `.sandbox.enabled // "unset"` here: jq's `//` treats false as
        # empty, so the exact value this check exists to find would be replaced by
        # the default and the branch below could never run. Ask whether the key is
        # present, then read it.
        ENABLED=$(jq -r 'if (.sandbox // {} | has("enabled")) then (.sandbox.enabled | tostring) else "unset" end' "$SFILE" 2>/dev/null)
        if [ "$ENABLED" = "false" ]; then
            echo "SANDBOX WARNING: sandbox.filesystem rules in $SFILE are inert — sandbox.enabled is false." >&2
            FOUND=1
        fi
        DISABLED=$(jq -r '.sandbox.filesystem.disabled // "unset"' "$SFILE" 2>/dev/null)
        if [ "$DISABLED" = "true" ]; then
            echo "SANDBOX WARNING: sandbox.filesystem.disabled is true in $SFILE — the deny/allow paths below it do nothing." >&2
            FOUND=1
        fi
    fi

    # --- 3. deny paths with a trailing slash (bypassable before 2.1.224) --
    for KEY in denyRead denyWrite; do
        PATHS=$(jq -r ".sandbox.filesystem.${KEY}[]? // empty" "$SFILE" 2>/dev/null)
        [ -z "$PATHS" ] && continue
        while IFS= read -r P; do
            [ -z "$P" ] && continue
            # "/" itself is a legitimate root rule, not a trailing-slash mistake.
            [ "$P" = "/" ] && continue
            case "$P" in
                */)
                    echo "SANDBOX WARNING: ${KEY} entry \"$P\" ends with '/' in $SFILE." >&2
                    echo "  Before Claude Code 2.1.224 this was silently bypassable on Linux and macOS." >&2
                    echo "  Write it without the trailing slash: \"${P%/}\"" >&2
                    FOUND=1
                    ;;
            esac
        done <<< "$PATHS"
    done
done

if [ "$FOUND" -eq 1 ]; then
    echo "" >&2
    echo "  Docs: https://code.claude.com/docs/en/sandboxing" >&2
    echo "  Check what is actually in force with the /sandbox panel." >&2
fi

exit 0
