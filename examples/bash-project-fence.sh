#!/bin/bash
# ================================================================
# bash-project-fence.sh — Block Bash commands that reach outside the project root
# ================================================================
# PURPOSE:
#   Prevents Claude Code from reading, writing, or scanning files
#   outside CLAUDE_PROJECT_DIR via Bash commands. The complement to
#   working-directory-fence.sh (which covers Read/Edit/Write tools).
#   Without this hook, CLAUDE.md restrictions on path scope are
#   model-side soft constraints that the model can ignore.
#
# SOLVES Issue #56739: model ran `find` across the entire Desktop,
#   located a personal file, and sent it to a 3rd-party API without
#   user confirmation. CLAUDE.md had a project-directory restriction
#   that the model ignored. Tool-layer enforcement was absent.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# HOW IT WORKS:
#   Parses the Bash command for absolute path arguments. For each
#   absolute path, resolves it against CLAUDE_PROJECT_DIR (or CWD as
#   fallback). If any path resolves outside the project tree, blocks
#   with exit 2 and a structured explanation.
#
# CONFIGURATION:
#   CC_BASH_FENCE_ALLOW — colon-separated additional allowed prefixes
#     (e.g., "/tmp:/var/log:/home/user/.config")
#     Default: /tmp, /var/tmp, /dev/null, /dev/stdin, /dev/stdout, /dev/stderr
#   CC_BASH_FENCE_ACTION — "block" (default) or "warn"
#   CC_BASH_FENCE_OFF — set to "1" to disable the hook entirely
#
# WHAT IT DOES NOT DO:
#   Does not parse arbitrary shell syntax (pipes, subshells, command
#   substitution). For most cases this is sufficient — the model's
#   surface use of `find`, `cat`, `grep`, `cp`, `mv`, `head`, `tail`,
#   `ls` against absolute paths is what reaches outside the project.
#   Operators who need stricter parsing should add a separate hook.
# ================================================================

set -u

# Honor disable flag
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-bash-project-fence-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [bash-project-fence]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

if [ "${CC_BASH_FENCE_OFF:-0}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Determine project root
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_ROOT=$(realpath -m "$PROJECT_ROOT" 2>/dev/null || printf '%s' "$PROJECT_ROOT")

# Default allowed prefixes (system paths the model legitimately needs)
DEFAULT_ALLOW="/tmp:/var/tmp:/dev/null:/dev/stdin:/dev/stdout:/dev/stderr:/proc"

# Build allow list
ALLOW_PREFIXES="${PROJECT_ROOT}:${DEFAULT_ALLOW}"
if [ -n "${CC_BASH_FENCE_ALLOW:-}" ]; then
    ALLOW_PREFIXES="${ALLOW_PREFIXES}:${CC_BASH_FENCE_ALLOW}"
fi

ACTION="${CC_BASH_FENCE_ACTION:-block}"

# Extract absolute path arguments from the command.
# Match tokens that start with / or ~/, but exclude pure flags (-x), URLs, and
# path-like substrings inside quoted JSON / env var assignments. We use a simple
# tokenizer based on shell word splitting; this misses some edge cases but
# covers the common file-access surface.
#
# Tokens captured:
#   - /absolute/path
#   - ~/home/path (expanded to $HOME)
# Tokens skipped:
#   - flags starting with -
#   - URLs (contain ://)
#   - things that look like options for find: -path X, -name X (handled below)

declare -a OUTSIDE_PATHS=()

# Use a portable word-split. Word-split the command on whitespace and pipes;
# preserve quoted segments roughly by stripping quotes after split.
# shellcheck disable=SC2086
set -f
IFS=$' \t\n|;&'
for tok in $COMMAND; do
    # Strip surrounding quotes
    tok="${tok#\"}"; tok="${tok%\"}"
    tok="${tok#\'}"; tok="${tok%\'}"

    # Strip the punctuation that wraps a command, so a path inside a
    # substitution or a subshell is still seen as a path. The word split above
    # does not break on ( ) or a backtick, so `[[ -n $(ls ~/secrets) ]]` used to
    # produce the token "~/secrets)", which matches neither the ~/ case nor the
    # absolute-path case below, and the reference left the fence unnoticed.
    # Measured 2026-08-04: the bare form was blocked and the wrapped form passed.
    tok="${tok#\$(}"; tok="${tok#(}"; tok="${tok#\`}"
    tok="${tok%)}"; tok="${tok%\`}"

    # Expand ~/ to $HOME
    case "$tok" in
        '~'/*) tok="${HOME}${tok#\~}" ;;
        '~') tok="${HOME}" ;;
    esac

    # Only check tokens that look like absolute paths
    case "$tok" in
        /*) ;;       # absolute path - check it
        *) continue ;;
    esac

    # Skip URLs (e.g., /http://... would be invalid anyway)
    case "$tok" in
        *://*) continue ;;
    esac

    # Resolve symlinks / .. against the filesystem (use -m for nonexistent paths)
    RESOLVED=$(realpath -m "$tok" 2>/dev/null || printf '%s' "$tok")

    # Check against each allowed prefix
    ALLOWED=0
    OLD_IFS="$IFS"
    IFS=':'
    for prefix in $ALLOW_PREFIXES; do
        IFS="$OLD_IFS"
        [ -z "$prefix" ] && continue
        # Normalize prefix
        prefix_norm=$(realpath -m "$prefix" 2>/dev/null || printf '%s' "$prefix")
        # Match if RESOLVED equals prefix or starts with prefix + "/"
        case "$RESOLVED" in
            "$prefix_norm"|"$prefix_norm"/*)
                ALLOWED=1
                break
                ;;
        esac
        IFS=':'
    done
    IFS="$OLD_IFS"

    if [ "$ALLOWED" -eq 0 ]; then
        OUTSIDE_PATHS+=("$RESOLVED")
    fi
done
set +f

if [ "${#OUTSIDE_PATHS[@]}" -eq 0 ]; then
    exit 0
fi

# Report
{
    if [ "$ACTION" = "warn" ]; then
        echo "WARN: Bash command references path outside the project root."
    else
        echo "BLOCKED: Bash command references path outside the project root."
    fi
    echo "  Project root: $PROJECT_ROOT"
    for p in "${OUTSIDE_PATHS[@]}"; do
        echo "  Outside path: $p"
    done
    echo "  Command head: $(printf '%s' "$COMMAND" | head -c 120)"
    echo
    echo "  This hook enforces a project-root allow list at the Bash layer."
    echo "  Background: model-side restrictions (CLAUDE.md, system prompt) can"
    echo "  be ignored. See https://github.com/anthropics/claude-code/issues/56739."
    echo
    echo "  To allow specific paths outside the project, set:"
    echo "    CC_BASH_FENCE_ALLOW=\"/path/one:/path/two\""
    echo "  To downgrade to a warning, set CC_BASH_FENCE_ACTION=warn."
    echo "  To disable entirely, set CC_BASH_FENCE_OFF=1."
} >&2

if [ "$ACTION" = "warn" ]; then
    exit 0
fi

exit 2
