#!/bin/bash
# ================================================================
# bash-allowlist-secondary-check.sh — Re-check Bash commands against
#                                     the user's settings.json allowlist
# ================================================================
# PURPOSE:
#   When the Bash tool fires, this hook independently parses the
#   allowlist from `.claude/settings.json` (and global
#   `~/.claude/settings.json`) and verifies the command matches an
#   allowed pattern. If no pattern matches, it warns to stderr (or
#   blocks in strict mode) — providing a second line of defence
#   against authorization-layer bypasses.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHY THIS MATTERS:
#   Issue #56117 reported that during a session running a Skill,
#   `Bash` tool calls for commands NOT present in the settings.json
#   allowlist (e.g. `git add`, `git commit`, `git push`) executed
#   without triggering the authorization prompt. The user was never
#   asked to approve. The allowlist contained only `git diff`, `git
#   log`, `git status`, no `Bash(*)` broad rule, and
#   `--dangerously-skip-permissions` was not used.
#
#   This is an authorization-layer bypass: the tool that should have
#   enforced the allowlist failed to do so silently. Skills, custom
#   agents, or other inner contexts may continue to expose similar
#   bypasses.
#
#   This hook re-evaluates the allowlist independently of Claude
#   Code's internal logic. It does not replace the primary check —
#   it backs it up.
#
# WHAT IT CHECKS:
#   1. Reads `permissions.allow` from `.claude/settings.json` (project)
#      and `~/.claude/settings.json` (user). Local settings
#      (`.claude/settings.local.json`) are also merged.
#   2. Extracts Bash patterns of the form `Bash(<pattern>)`.
#   3. Tests the Bash command against each pattern using a simple
#      matcher: exact match, prefix match for patterns ending in `:*`,
#      and wildcard for `Bash(*)`.
#   4. If no pattern matches, emits a warning that names the command
#      and references #56117.
#
# OUTPUT:
#   Warning to stderr when the command does not match any allowlist
#   pattern. Default: exit 0 (advisory). Strict mode: exit 2 (block).
#
# CONFIGURATION:
#   CC_BASH_ALLOWLIST_STRICT — set to "1" to block when no pattern
#       matches (default: warn only)
#   CC_BASH_ALLOWLIST_QUIET — set to "1" to silence warnings (still
#       blocks in strict mode)
#
# LIMITATIONS:
#   - The matcher is intentionally simple. It does not perfectly
#     replicate Claude Code's internal matching, which uses richer
#     glob semantics. Some allowlist entries may produce false
#     warnings; tune patterns or use strict mode selectively.
#   - The hook reads JSON via `jq`. If `jq` is missing, the hook
#     exits 0 silently rather than failing the Bash call.
#   - This hook does not record approvals. Repeated commands matching
#     the same gap will repeat the warning.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/56117
# ================================================================

set -u

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# No command, nothing to check.
[ -z "$COMMAND" ] && exit 0

# jq is required to read settings; fall through silently if missing.
command -v jq >/dev/null 2>&1 || exit 0

STRICT="${CC_BASH_ALLOWLIST_STRICT:-0}"
QUIET="${CC_BASH_ALLOWLIST_QUIET:-0}"

# Collect allow patterns from up to three settings files.
collect_allow_patterns() {
    local f
    for f in \
        "$HOME/.claude/settings.json" \
        ".claude/settings.json" \
        ".claude/settings.local.json"
    do
        [ -r "$f" ] || continue
        jq -r '.permissions.allow // [] | .[]' "$f" 2>/dev/null
    done
}

PATTERNS=$(collect_allow_patterns)

# Extract only Bash() patterns. Other tools are out of scope.
BASH_PATTERNS=$(printf '%s\n' "$PATTERNS" | grep -E '^Bash\(' | sed -E 's/^Bash\((.*)\)$/\1/')

# Strip outer whitespace from the command for matching purposes.
TRIMMED_CMD=$(printf '%s' "$COMMAND" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')

# A Bash(*) pattern allows everything — matches and exits.
if printf '%s\n' "$BASH_PATTERNS" | grep -qx '\*'; then
    exit 0
fi

# Try to match the command against any pattern.
matched=0
while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in
        *":*")
            # Prefix match: pattern is "<prefix>:*" — match if the command starts with <prefix>.
            prefix="${pat%:\*}"
            case "$TRIMMED_CMD" in
                "$prefix"|"$prefix "*|"$prefix"$'\t'*)
                    matched=1
                    break
                    ;;
            esac
            ;;
        *)
            # Exact-or-prefix-with-space: pattern matches if the command is exactly the
            # pattern, or the pattern is the leading token followed by a space/tab.
            case "$TRIMMED_CMD" in
                "$pat"|"$pat "*|"$pat"$'\t'*)
                    matched=1
                    break
                    ;;
            esac
            ;;
    esac
done <<< "$BASH_PATTERNS"

if [ "$matched" -eq 1 ]; then
    exit 0
fi

# No match. Emit a warning unless quiet, and block in strict mode.
if [ "$QUIET" != "1" ]; then
    SHORT_CMD=$(printf '%s' "$TRIMMED_CMD" | head -c 120)
    printf '⚠️  Bash command not matched by any settings.json allow pattern (Issue #56117 defence-in-depth):\n' >&2
    printf '    command: %s\n' "$SHORT_CMD" >&2
    printf '    note:    Claude Code should have prompted before running this. If it did not, the\n' >&2
    printf '             primary allowlist check may have been bypassed (e.g. inside a Skill).\n' >&2
    printf '    action:  Add an explicit allow rule, deny the run, or set CC_BASH_ALLOWLIST_STRICT=1 to block.\n' >&2
    printf '    issue:   https://github.com/anthropics/claude-code/issues/56117\n' >&2
fi

if [ "$STRICT" = "1" ]; then
    exit 2
fi

exit 0
