#!/bin/bash
# ================================================================
# subagent-inheritance-tester.sh — Audit subagent frontmatter for
#                                   missing tool boundaries and
#                                   non-functional memory directives
# ================================================================
# PURPOSE:
#   Two May 2026 incidents documented subagent docs that looked
#   fine but did not enforce the parent's safety boundary:
#
#   #57068 — A parent settings.json with Deny rule on .env reads
#            did not propagate to a subagent. The subagent read
#            and reported the file's contents because the agent
#            doc omitted an explicit tools: list and inherited a
#            broader default.
#   #57507 — A subagent doc declared its scope using a memory:
#            field. memory: is silently ignored in subagent
#            frontmatter (only tools:, model:, description: and
#            name: are honored). The author believed the scope
#            was bound; the runtime treated it as unbounded.
#
#   On SessionStart, this hook scans ~/.claude/agents/ and the
#   project's .claude/agents/ directory and reports each doc
#   that (a) lacks an explicit tools: list, (b) uses a memory:
#   field, or (c) lacks frontmatter entirely. When the parent
#   settings.json contains Deny rules, the warning escalates
#   because those rules cannot be relied upon for subagents
#   that have no tool binding.
#
# TRIGGER: SessionStart
#
# CONFIG:
#   CC_SUBAGENT_INHERITANCE_BLOCK=0   (0 = warn; 1 = exit 2)
#   CC_SUBAGENT_INHERITANCE_PATHS=""  (extra colon-separated dirs)
#
# Born from:
#   https://github.com/anthropics/claude-code/issues/57068
#   https://github.com/anthropics/claude-code/issues/57507
# Related: chapter 9 of the May 2026 claim-verify case handbook
#          ("自動の点検の道具の素案 5 件" — proposed detection
#          tools 4 / 5, the fourth being subagent-inheritance-tester)
# ================================================================

set -u

INPUT=$(cat 2>/dev/null || true)

# Resolve the project directory if the caller provided it.
PROJECT_DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

BLOCK="${CC_SUBAGENT_INHERITANCE_BLOCK:-0}"
EXTRA="${CC_SUBAGENT_INHERITANCE_PATHS:-}"

SCAN_DIRS=()
[ -d "${HOME}/.claude/agents" ] && SCAN_DIRS+=("${HOME}/.claude/agents")
[ -n "$PROJECT_DIR" ] && [ -d "${PROJECT_DIR}/.claude/agents" ] && SCAN_DIRS+=("${PROJECT_DIR}/.claude/agents")
if [ -n "$EXTRA" ]; then
    IFS=':' read -ra EXTRA_DIRS <<< "$EXTRA"
    for d in "${EXTRA_DIRS[@]}"; do
        [ -d "$d" ] && SCAN_DIRS+=("$d")
    done
fi

# Nothing to audit, exit silently.
if [ "${#SCAN_DIRS[@]}" -eq 0 ]; then
    exit 0
fi

# Collect parent Deny rules. When present, missing tool bindings
# in subagents are escalated because the deny boundary cannot be
# inherited reliably.
DENY_RULES=""
for settings in "${HOME}/.claude/settings.json" \
                "${HOME}/.claude/settings.local.json" \
                "${PROJECT_DIR}/.claude/settings.json" \
                "${PROJECT_DIR}/.claude/settings.local.json"; do
    [ -n "$settings" ] || continue
    [ -f "$settings" ] || continue
    deny=$(jq -r '.permissions.deny[]? // empty' "$settings" 2>/dev/null || true)
    if [ -n "$deny" ]; then
        DENY_RULES="${DENY_RULES}${deny}
"
    fi
done

extract_frontmatter() {
    awk '
        /^---[[:space:]]*$/ {
            if (!opened) { opened=1; next }
            else { exit }
        }
        opened { print }
    ' "$1" 2>/dev/null
}

ISSUES=""

for dir in "${SCAN_DIRS[@]}"; do
    # Find .md files; skip hidden and backup files.
    while IFS= read -r doc; do
        [ -f "$doc" ] || continue
        case "$(basename "$doc")" in
            .*|*.bak|*~) continue ;;
        esac

        # First non-empty line must be `---` for valid frontmatter.
        first=$(awk 'NF { print; exit }' "$doc" 2>/dev/null || true)
        if [ "$first" != "---" ]; then
            ISSUES="${ISSUES}  - ${doc}: no YAML frontmatter; subagent definition will be ignored or treated as bare prompt
"
            continue
        fi

        fm=$(extract_frontmatter "$doc")
        if [ -z "$fm" ]; then
            ISSUES="${ISSUES}  - ${doc}: empty frontmatter block
"
            continue
        fi

        has_tools=$(printf '%s' "$fm" | grep -cE '^[[:space:]]*tools[[:space:]]*:' || true)
        has_memory=$(printf '%s' "$fm" | grep -cE '^[[:space:]]*memory[[:space:]]*:' || true)
        has_name=$(printf '%s' "$fm" | grep -cE '^[[:space:]]*name[[:space:]]*:' || true)

        if [ "$has_name" -eq 0 ]; then
            ISSUES="${ISSUES}  - ${doc}: frontmatter missing required 'name:' key
"
        fi

        if [ "$has_memory" -gt 0 ]; then
            ISSUES="${ISSUES}  - ${doc}: 'memory:' key found in frontmatter — silently ignored at runtime (Issue #57507). Move scope/context into the prompt body.
"
        fi

        if [ "$has_tools" -eq 0 ]; then
            if [ -n "$DENY_RULES" ]; then
                ISSUES="${ISSUES}  - ${doc}: no explicit 'tools:' list; parent Deny rules (e.g. .env) cannot be relied upon to propagate (Issue #57068). Add tools: with the minimum needed.
"
            else
                ISSUES="${ISSUES}  - ${doc}: no explicit 'tools:' list; subagent will inherit the broad default tool set. Pin to least-privilege.
"
            fi
        fi
    done < <(find "$dir" -maxdepth 2 -type f -name '*.md' 2>/dev/null)
done

if [ -z "$ISSUES" ]; then
    exit 0
fi

printf '⚠️  subagent-inheritance-tester: subagent docs with inheritance gaps:\n' >&2
printf '%b' "$ISSUES" >&2
if [ -n "$DENY_RULES" ]; then
    printf '\n  Parent Deny rules in effect:\n' >&2
    printf '%s' "$DENY_RULES" | sed 's/^/    /' >&2
fi
printf '\n  References:\n' >&2
printf '    https://github.com/anthropics/claude-code/issues/57068\n' >&2
printf '    https://github.com/anthropics/claude-code/issues/57507\n' >&2
printf '  Recommended fix: add an explicit tools: list to each agent doc; remove memory: keys.\n' >&2

if [ "$BLOCK" = "1" ]; then
    exit 2
fi

exit 0
