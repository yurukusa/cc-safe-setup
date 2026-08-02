#!/bin/bash
# ================================================================
# scope-expansion-receipt.sh — Receipt-and-refuse layer for
#                              destructive operations outside scope
# ================================================================
# PURPOSE:
#   PreToolUse on Bash. When a destructive operation is detected,
#   writes a structured JSONL receipt before the call, and refuses
#   (exit 2) when the targeted path falls outside any declared scope.
#
#   Based on Keesan12's articulation of the principle
#   "subagent output is evidence, not authorization", filed against
#   anthropics/claude-code#61102. The hook makes the receipt the
#   load-bearing surface: even when the model has been persuaded by
#   subagent output, the destructive call lands a record AND
#   requires the target to match a declared scope.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHY THIS MATTERS:
#   anthropics/claude-code#61102 reported Claude Code expanding
#   scope from "delete caches and simulators" to a 120 GB sweep:
#   node_modules across all projects, npm cache, Spotlight index,
#   UV/Cursor/OpenCode data. Subagent reports listed these as
#   "removable" — the model collapsed "can be deleted" into
#   "should be deleted". The same shape appears across the
#   #60226 / #60475 / #60620 / #60977 sub-agent boundary cluster.
#
#   Existing hooks (subagent-destructive-git-guard,
#   gh-cli-destructive-guard, rm-safety-net) catch specific verbs
#   or specific commands. This hook is orthogonal: it catches
#   destructive operations regardless of subagent origin, by
#   matching the targeted PATH against an operator-declared
#   scope list. When the scope list is empty (default), it runs
#   in receipt-only mode (always exits 0) so adoption is safe.
#
# WHAT IT DETECTS (destructive verbs):
#   - rm -rf / rm -fR / rm -Rf / rm -fr
#   - find ... -delete  /  find ... -exec rm
#   - npm cache clean --force / yarn cache clean / pnpm store prune
#   - npx rimraf / npx del-cli
#   - cargo clean / go clean -cache
#   - dd if=...  (overwrite-class)
#
# RECEIPT FORMAT (one JSONL per detected call):
#   {"ts":"2026-05-22T03:50:00Z",
#    "command":"<full command>",
#    "paths":["<extracted target paths>"],
#    "scope_match":"cache" | null,
#    "decision":"execute" | "refuse"}
#
# RECEIPT LOCATION:
#   ${HOME}/.claude/receipts/destructive-YYYY-MM-DD.jsonl
#
# CONFIGURATION:
#   CC_RECEIPT_SCOPES — JSON object of declared scopes, e.g.
#       {"cache":["~/Library/Caches","~/.npm/_cacache"],
#        "simulator":["~/Library/Developer/CoreSimulator"]}
#     Paths are matched as prefixes. Tilde expansion uses $HOME.
#     If unset, the hook only writes receipts (never refuses).
#
#   CC_RECEIPT_BYPASS=1 — single-call escape hatch. The receipt
#     is still written (with decision="execute-bypassed"); refuse
#     logic is skipped. Use only when you have read the receipt
#     and verified the intent.
#
#   CC_RECEIPT_DIR — override the receipt directory
#     (default: ${HOME}/.claude/receipts)
#
# RELATED:
#   https://github.com/anthropics/claude-code/issues/61102
#   https://github.com/anthropics/claude-code/issues/60226
#   https://github.com/anthropics/claude-code/issues/60475
#   https://github.com/anthropics/claude-code/issues/60977
#   https://gist.github.com/yurukusa/8c0d19d59730868672270e7312492d1d
#   (Receipt persistence layer — the architecture this hook implements)
# ================================================================

set -u

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-scope-expansion-receipt-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [scope-expansion-receipt]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

DESTRUCTIVE_PATTERN='(\brm[[:space:]]+-[a-zA-Z]*[rRfF][a-zA-Z]*[[:space:]]|\bfind[[:space:]].*[[:space:]]-delete\b|\bfind[[:space:]].*-exec[[:space:]]+rm\b|\bnpm[[:space:]]+cache[[:space:]]+clean\b|\byarn[[:space:]]+cache[[:space:]]+clean\b|\bpnpm[[:space:]]+store[[:space:]]+prune\b|\bnpx[[:space:]]+rimraf\b|\bnpx[[:space:]]+del-cli\b|\bcargo[[:space:]]+clean\b|\bgo[[:space:]]+clean[[:space:]]+-cache\b|\bdd[[:space:]]+if=)'

if ! printf '%s' "$COMMAND" | grep -qE "$DESTRUCTIVE_PATTERN"; then
    exit 0
fi

# Extract candidate target paths (heuristic: tokens that look like paths)
PATHS=$(printf '%s' "$COMMAND" | tr -s '[:space:]' '\n' | grep -E '^(/|~/|\$HOME|\./)' | sed "s|^~|${HOME}|" | sed "s|^\$HOME|${HOME}|" | sort -u | tr '\n' ' ')

# Build JSONL fields
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CMD_JSON=$(printf '%s' "$COMMAND" | jq -Rs -c .)
PATHS_JSON=$(printf '%s\n' $PATHS | jq -Rn -c '[inputs | select(length > 0)]')

# Decide based on CC_RECEIPT_SCOPES
SCOPES_JSON="${CC_RECEIPT_SCOPES:-}"
BYPASS="${CC_RECEIPT_BYPASS:-0}"
DECISION="execute"
MATCHED_SCOPE_JSON="null"

if [ -n "$SCOPES_JSON" ] && [ -n "$PATHS" ]; then
    REFUSE=false
    FIRST_MATCH=""
    for P in $PATHS; do
        # For each path, find which scope (if any) contains it as a prefix
        MATCH=$(printf '%s' "$SCOPES_JSON" | jq -r --arg p "$P" --arg home "$HOME" '
            to_entries[] as $entry |
            $entry.value[]? as $scope |
            ($scope | sub("^~"; $home) | sub("^\\$HOME"; $home)) as $expanded |
            select($p | startswith($expanded)) |
            $entry.key
        ' 2>/dev/null | head -1)
        if [ -z "$MATCH" ]; then
            REFUSE=true
            break
        else
            FIRST_MATCH="$MATCH"
        fi
    done
    if [ "$REFUSE" = "true" ]; then
        DECISION="refuse"
    elif [ -n "$FIRST_MATCH" ]; then
        MATCHED_SCOPE_JSON="\"$FIRST_MATCH\""
    fi
fi

if [ "$BYPASS" = "1" ] && [ "$DECISION" = "refuse" ]; then
    DECISION="execute-bypassed"
fi

# Write receipt
RECEIPT_DIR="${CC_RECEIPT_DIR:-${HOME}/.claude/receipts}"
mkdir -p "$RECEIPT_DIR" 2>/dev/null
RECEIPT_FILE="${RECEIPT_DIR}/destructive-$(date +%Y-%m-%d).jsonl"

printf '{"ts":"%s","command":%s,"paths":%s,"scope_match":%s,"decision":"%s"}\n' \
    "$TS" "$CMD_JSON" "$PATHS_JSON" "$MATCHED_SCOPE_JSON" "$DECISION" \
    >> "$RECEIPT_FILE" 2>/dev/null

if [ "$DECISION" = "refuse" ]; then
    echo "BLOCKED: scope-expansion-receipt — destructive operation targeting paths outside declared scopes." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    if [ -n "$PATHS" ]; then
        echo "Paths: $PATHS" >&2
    fi
    SCOPE_NAMES=$(printf '%s' "$SCOPES_JSON" | jq -r 'keys | join(", ")' 2>/dev/null)
    echo "Declared scopes: $SCOPE_NAMES" >&2
    echo "Receipt: $RECEIPT_FILE" >&2
    echo "" >&2
    echo "Principle: subagent output is evidence, not authorization." >&2
    echo "  (https://github.com/anthropics/claude-code/issues/61102)" >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  1. Verify the operation is genuinely in scope (read the user request again)." >&2
    echo "  2. Either add the target path prefix to CC_RECEIPT_SCOPES, or" >&2
    echo "  3. Re-issue with CC_RECEIPT_BYPASS=1 (recorded in the receipt)." >&2
    exit 2
fi

exit 0
