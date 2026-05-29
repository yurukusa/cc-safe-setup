#!/bin/bash
# ================================================================
# claude-code-version-pin-advisor.sh — SessionStart advisory for
# Cluster 16 (v2.1.154+ messages role 'system' API 400)
# ================================================================
# PURPOSE:
#   Claude Code v2.1.154 onward shipped a request-assembly
#   regression that serializes `system`-role content from
#   SessionStart hooks, plugin context, Skill metadata, and
#   compaction summaries as peer entries inside the `messages[]`
#   array instead of the top-level `system` field. The Anthropic
#   Messages API rejects this with `API Error: 400 messages[N].role
#   must be either 'user' or 'assistant', but got 'system'`.
#
#   Four sub-patterns surface this defect:
#     16A — Custom agents via /agents (Issue #63457)
#     16B — Strict Anthropic-compatible providers (#63366, #63469)
#     16C — VS Code extension (#63473, #63510)
#     16D — Long-lived session context operations (#63396 Variant 1)
#
#   The defect lives in code paths the hook layer cannot reach at
#   request-assembly time. No hook can prevent the 400. The only
#   workaround is the version pin to v2.1.153.
#
#   This hook surfaces the warning at SessionStart so the operator
#   knows the workaround BEFORE they lose a session to the 400.
#   It does not block; it advises.
#
# DETECTION:
#   At SessionStart, parse `claude --version` (or read
#   CLAUDE_CODE_VERSION env var if set) to obtain the running
#   semver. Compare against the threshold (default 2.1.154). If
#   at or above, emit an advisory naming the four sub-patterns
#   and the pin command.
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# OUTPUT:
#   Advisory only, never blocks. Prints to stderr.
#
# CONFIGURATION:
#   CC_VERSION_PIN_ADVISOR_DISABLE=1    — disable entirely
#   CC_VERSION_PIN_ADVISOR_QUIET=1      — silence after
#                                         acknowledgment
#   CC_VERSION_PIN_ADVISOR_THRESHOLD    — override threshold semver
#                                         (default "2.1.154")
#   CC_VERSION_PIN_ADVISOR_CLAUDE_BIN   — override path to claude
#                                         binary (default: look up
#                                         on PATH)
#   CLAUDE_CODE_VERSION                 — if set, the hook uses this
#                                         instead of calling
#                                         `claude --version`. Useful
#                                         for tests and for
#                                         environments where the
#                                         binary lookup is slow.
#
# RELATED:
#   Cluster 16 entry in cc-safe-setup cluster-tracker.html
#   English field guide:
#     https://gist.github.com/yurukusa/05c120466996734f7bc2ad6d41fdedec
#   Anchor case for resolution tracking:
#     https://github.com/anthropics/claude-code/issues/63469
#
# DESIGN NOTES:
#   - The hook does NOT pin the version. The operator decides.
#     The hook surfaces the advisory so the operator can decide.
#   - The semver comparison is done in pure bash (no external
#     dependencies on sort -V or similar). Each component is
#     compared numerically; suffix tags (e.g. "-beta") are
#     stripped.
#   - When the version output is malformed or the binary is
#     missing, the hook fails open (exit 0 silent). It does NOT
#     warn that detection failed — that would be a noise source
#     in environments where Claude Code is invoked through a
#     wrapper or shim that doesn't expose --version.

set -u

if [ "${CC_VERSION_PIN_ADVISOR_DISABLE:-0}" = "1" ]; then
    exit 0
fi
if [ "${CC_VERSION_PIN_ADVISOR_QUIET:-0}" = "1" ]; then
    exit 0
fi

# Consume stdin if provided (SessionStart hooks receive JSON input)
if [ ! -t 0 ]; then
    cat >/dev/null 2>&1 || true
fi

THRESHOLD="${CC_VERSION_PIN_ADVISOR_THRESHOLD:-2.1.154}"

# Obtain running Claude Code version
detect_version() {
    # Prefer env var if set (tests, controlled environments)
    if [ -n "${CLAUDE_CODE_VERSION:-}" ]; then
        echo "$CLAUDE_CODE_VERSION"
        return 0
    fi
    local claude_bin="${CC_VERSION_PIN_ADVISOR_CLAUDE_BIN:-}"
    if [ -z "$claude_bin" ]; then
        claude_bin=$(command -v claude 2>/dev/null || true)
    fi
    if [ -z "$claude_bin" ] || [ ! -x "$claude_bin" ]; then
        return 1
    fi
    local out
    out=$("$claude_bin" --version 2>/dev/null) || return 1
    # Output format: "2.1.153 (Claude Code)" or similar
    # Extract the first semver-looking token
    echo "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1
}

# Compare two semvers: returns 0 if $1 >= $2, 1 otherwise.
# Strips suffix tags after a dash.
semver_gte() {
    local a="${1%%-*}"
    local b="${2%%-*}"
    # Validate format - if either is not "N.N.N", treat as not-comparable
    case "$a" in
        *[!0-9.]*) return 1 ;;
        *) ;;
    esac
    case "$b" in
        *[!0-9.]*) return 1 ;;
        *) ;;
    esac
    local IFS=.
    local -a parts_a parts_b
    read -ra parts_a <<< "$a"
    read -ra parts_b <<< "$b"
    # Compare up to 3 components
    local i
    for i in 0 1 2; do
        local na="${parts_a[$i]:-0}"
        local nb="${parts_b[$i]:-0}"
        # Validate each component is numeric
        case "$na" in
            ''|*[!0-9]*) na=0 ;;
        esac
        case "$nb" in
            ''|*[!0-9]*) nb=0 ;;
        esac
        if [ "$na" -gt "$nb" ]; then
            return 0
        elif [ "$na" -lt "$nb" ]; then
            return 1
        fi
    done
    # Equal — counts as >=
    return 0
}

VERSION=$(detect_version)
if [ -z "$VERSION" ]; then
    # Fail open: detection failed, do not warn
    exit 0
fi

# Compare against threshold; warn only if at or above
if ! semver_gte "$VERSION" "$THRESHOLD"; then
    exit 0
fi

{
    echo "ADVISORY: Claude Code $VERSION may hit Cluster 16 (API Error 400 messages[].role 'system')."
    echo "  Four sub-patterns observed since v$THRESHOLD:"
    echo "    16A — Custom agents via /agents (Issue #63457, clean rollback to 2.1.153 fully resolves)"
    echo "    16B — Strict Anthropic-compatible providers (#63366, #63469 has-repro)"
    echo "    16C — VS Code extension (#63473, #63510)"
    echo "    16D — Long-lived session context operations after compact/clear/model-switch (#63396 Variant 1)"
    echo "  Workaround (the only path until upstream fix):"
    echo "    npm install -g @anthropic-ai/claude-code@2.1.153"
    echo "    export CLAUDE_CODE_DISABLE_AUTO_UPDATE=1   # add to ~/.bashrc or ~/.zshrc"
    echo "  Anchor case to subscribe for the upstream fix signal:"
    echo "    https://github.com/anthropics/claude-code/issues/63469"
    echo "  Field guide (sub-patterns, architectural axis, comparison to Cluster 8 & 13):"
    echo "    https://gist.github.com/yurukusa/05c120466996734f7bc2ad6d41fdedec"
    echo "  Silence after acknowledgment: export CC_VERSION_PIN_ADVISOR_QUIET=1"
} >&2

exit 0
