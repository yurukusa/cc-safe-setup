#!/bin/bash
# ================================================================
# git-submodule-guard.sh — Block the data-destroying variant of
#                          `git submodule deinit` before it runs
# ================================================================
# PURPOSE:
#   `git submodule deinit -f <path>` (or `--force`) removes the
#   submodule's working tree. The -f / --force flag is exactly what
#   makes git delete a submodule working tree that still has
#   uncommitted or un-added changes. Without -f, git refuses when the
#   submodule has local modifications — that built-in refusal is a
#   safety net, and -f overrides it.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHY THIS MATTERS:
#   #68920 (2026-06) — asked to tidy up an unused submodule reference,
#   Claude Code ran `git submodule deinit -f` followed by `git rm`,
#   and the submodule's uncommitted edits and .gitignored config
#   (editor settings, etc.) were deleted with no confirmation. This is
#   a path that the usual rm -rf / reset --hard / clean -fd guards do
#   NOT catch, because `deinit` does not look like a destructive
#   command. Recovery is only partial: committed work is in the
#   reflog and staged work survives in the index (restore with
#   `git checkout-index`, not visible to `git fsck`), but edits that
#   were never `git add`-ed are gone.
#
# WHAT IT DOES:
#   - `git submodule deinit` WITH -f / --force  -> block (exit 2) by
#     default, so the force-override of git's own safety net is
#     stopped before any work is lost. Opt out to warn-only with
#     SUBMODULE_DEINIT_BLOCK=0.
#   - `git submodule deinit` WITHOUT a force flag, or `git submodule
#     rm` -> warn only (exit 0). git itself refuses the unforced
#     deinit when there are local changes, so a reminder is enough.
#
# CONFIG:
#   SUBMODULE_DEINIT_BLOCK=1   (default: 1 = block forced deinit; 0 = warn-only)
#
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-git-submodule-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [git-submodule-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

BLOCK_MODE="${SUBMODULE_DEINIT_BLOCK:-1}"

# Forced deinit: the variant that deletes uncommitted submodule work (#68920).
# Match `git submodule deinit` followed, within the same command segment
# (no pipe / && / ; in between), by a -f or --force flag.
if echo "$COMMAND" | grep -qE '\bgit\s+submodule\s+deinit\b[^|&;]*(-f\b|--force\b)'; then
    if [ "$BLOCK_MODE" = "1" ]; then
        echo "BLOCKED: git-submodule-guard: 'git submodule deinit -f/--force' deletes the submodule working tree, including uncommitted and un-added changes, irreversibly (Claude Code incident #68920)." >&2
        echo "  Safer path: commit or 'git stash' your submodule work first, or run 'git submodule deinit' WITHOUT -f (git refuses if there are local changes)." >&2
        echo "  To allow for legitimate cleanup: export SUBMODULE_DEINIT_BLOCK=0 (warn-only mode)." >&2
        exit 2
    fi
    echo "WARNING: 'git submodule deinit -f/--force' force-removes the submodule working tree and can delete uncommitted work (#68920). Commit or stash first." >&2
    exit 0
fi

# Unforced deinit / submodule rm: warn only (git's own safety still applies).
if echo "$COMMAND" | grep -qE '\bgit\s+submodule\s+(deinit|rm)\b'; then
    echo "WARNING: Removing git submodule. This may break builds. Uncommitted submodule changes are at risk; commit or stash first." >&2
fi
exit 0
