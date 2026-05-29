#!/bin/bash
# deny-rule-integrity-verifier.sh — Catch deny-rule bypasses through whitespace normalization
#
# Solves: Cluster 6 Axis 5 — deny rules don't enforce the safety constraints
#         users configure. A deny pattern Bash(rm -rf:*) catches `rm -rf /`
#         but is silently bypassed by:
#           - extra whitespace (`rm  -rf /`)
#           - backslash-newline line continuations (`rm \<newline>-rf /`)
#           - tab characters in place of spaces (`rm	-rf /`)
#         The matching engine compares the raw command string against the
#         pattern body literally, so any whitespace anomaly slips past.
#
# Issues addressed: meta-issue #30519 Axis 5 (deny rules have same bugs as
#         allow rules), #35954 (backslash-escaped whitespace warning
#         framework), and the broader pattern that whitespace-sensitive
#         literal matching can be defeated trivially.
#
# How it works: PreToolUse hook on Bash. For each Bash() deny pattern in
#   permissions.deny across the four standard settings locations, the
#   hook checks:
#     1. Does the RAW command match the pattern? (the matching engine
#        catches this case; if yes, this hook does nothing)
#     2. Does the NORMALIZED command match the pattern? (whitespace
#        collapsed, line continuations joined)
#   If raw misses and normalized hits — that is the bypass. The hook
#   blocks with exit code 2 by default; CC_DENY_INTEGRITY_WARN_ONLY=1
#   converts the block to a stderr advisory while letting the command
#   through.
#
#   Pattern extraction supports the three Claude Code Bash() shapes:
#     Bash(<exact>)          — exact match
#     Bash(<prefix>:*)       — prefix match (the common form)
#     Bash(*)                — wildcard — skipped (already matches raw)
#
# Scope of normalization (v1):
#   - Strip backslash-newline line continuations (`\<newline>` → ` `)
#   - Collapse any whitespace run (spaces, tabs, newlines) to a single space
#   - Trim leading and trailing whitespace
#   Flag combination/reordering normalization (`-rf` vs `-r -f` vs `-fr`)
#   is OUT OF SCOPE for v1 — those bypass shapes need command-aware logic
#   beyond uniform string normalization and warrant a separate hook.
#
# Environment variables:
#   CC_DENY_INTEGRITY_DISABLE=1   — disable verification entirely
#   CC_DENY_INTEGRITY_WARN_ONLY=1 — log the bypass to stderr but do not block
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -uo pipefail

INPUT=$(cat)

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
[ "${CC_DENY_INTEGRITY_DISABLE:-0}" = "1" ] && exit 0

# Collect Bash() deny patterns from all four standard settings locations.
DENY_FILE=$(mktemp)
trap 'rm -f "$DENY_FILE"' EXIT
for CFG in \
    "${HOME}/.claude/settings.json" \
    "${HOME}/.claude/settings.local.json" \
    "./.claude/settings.json" \
    "./.claude/settings.local.json"; do
    [ -f "$CFG" ] || continue
    jq -r '.permissions.deny // [] | .[] | select(type == "string" and startswith("Bash("))' \
        "$CFG" 2>/dev/null >> "$DENY_FILE" || true
done

[ ! -s "$DENY_FILE" ] && exit 0

# Normalize: strip backslash-newline (line continuation), collapse all
# whitespace to single space, trim.
NORMALIZED=$(printf '%s' "$COMMAND" \
    | sed -E ':a;N;$!ba;s/\\\n/ /g' \
    | tr '\t\n' '  ' \
    | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')

# If normalization is a no-op, nothing to do — the standard matcher
# already handles this command.
if [ "$NORMALIZED" = "$COMMAND" ]; then
    exit 0
fi

# Check each deny pattern.
while IFS= read -r PATTERN; do
    [ -z "$PATTERN" ] && continue

    # Extract pattern body. Handles:
    #   Bash(<body>)        → BODY=<body>, SUFFIX_GLOB=0
    #   Bash(<body>:*)      → BODY=<body>, SUFFIX_GLOB=1
    BODY=""
    SUFFIX_GLOB=0
    if [[ "$PATTERN" =~ ^Bash\((.+):\*\)$ ]]; then
        BODY="${BASH_REMATCH[1]}"
        SUFFIX_GLOB=1
    elif [[ "$PATTERN" =~ ^Bash\((.+)\)$ ]]; then
        BODY="${BASH_REMATCH[1]}"
        SUFFIX_GLOB=0
    fi
    [ -z "$BODY" ] && continue

    # Bash(*) — wildcard pattern — would match raw already.
    [ "$BODY" = "*" ] && continue

    # Match logic: a command matches the pattern if it equals BODY exactly
    # or (when the pattern has the :* glob suffix) if it starts with BODY
    # at a word boundary. The boundary rule:
    #   - If BODY ends in an alphanumeric char (rm, git, curl) the next
    #     character must be a space — otherwise `Bash(rm:*)` would block
    #     `rmdir`.
    #   - If BODY ends in a non-alphanumeric char (=, -, /, .) the next
    #     character can be attached — `Bash(dd if=:*)` should match
    #     `dd if=/dev/zero ...`.
    raw_matches() {
        local CMD="$1" BDY="$2" GLOB="$3"
        if [ "$CMD" = "$BDY" ]; then
            return 0
        fi
        if [ "$GLOB" = "1" ]; then
            local LAST_CHAR="${BDY: -1}"
            if [[ "$LAST_CHAR" =~ [a-zA-Z0-9] ]]; then
                case "$CMD" in
                    "$BDY "*) return 0 ;;
                esac
            else
                case "$CMD" in
                    "$BDY"*) return 0 ;;
                esac
            fi
        fi
        return 1
    }

    if raw_matches "$COMMAND" "$BODY" "$SUFFIX_GLOB"; then
        # Standard matcher already catches this — nothing for us to do.
        continue
    fi

    if raw_matches "$NORMALIZED" "$BODY" "$SUFFIX_GLOB"; then
        # BYPASS DETECTED.
        CMD_SAFE_PRINT=$(printf '%s' "$COMMAND" | head -c 300 | tr -d '\000')
        {
            echo "[deny-rule-integrity-verifier] Deny-rule bypass detected."
            echo ""
            echo "  Configured deny pattern : $PATTERN"
            echo "  Raw command (excerpt)   : $CMD_SAFE_PRINT"
            echo "  Normalized command      : $NORMALIZED"
            echo ""
            echo "The normalized form matches your configured deny pattern, but the raw"
            echo "command bypasses literal matching through whitespace anomalies"
            echo "(extra spaces, tab characters, or backslash-newline line continuations)."
            echo "Cluster 6 Axis 5 — meta-issue #30519 (Claude Code permission matching)."
        } >&2
        if [ "${CC_DENY_INTEGRITY_WARN_ONLY:-0}" = "1" ]; then
            echo "" >&2
            echo "(CC_DENY_INTEGRITY_WARN_ONLY=1 is set — command will proceed)" >&2
            exit 0
        else
            echo "" >&2
            echo "Blocking. Set CC_DENY_INTEGRITY_WARN_ONLY=1 to convert this to a" >&2
            echo "warning, or CC_DENY_INTEGRITY_DISABLE=1 to silence the hook." >&2
            exit 2
        fi
    fi
done < "$DENY_FILE"

exit 0
