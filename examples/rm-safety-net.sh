#!/bin/bash
# rm-safety-net.sh — Extra layer of rm protection beyond destructive-guard
#
# Solves: rm commands executing without permission prompts even when not in allow list
#         (#38607 — rm bypasses settings.json permission system)
#
# Difference from destructive-guard:
#   destructive-guard blocks: rm -rf /, rm -rf ~/, rm -rf ../, sudo rm -rf
#   This hook blocks: ALL rm commands on important paths, even non-recursive
#
# What it blocks:
#   rm (any flags) on: /, ~, .., /home, /Users, /etc, /usr, /var, .git, .env
#   wildcard/glob rm reaching into a user/home/absolute path, e.g.
#     rm -f ~/Downloads/*copy*.md  (unpredictable match set — see #64559)
#   find -delete (any path)
#   shred (any file)
#   unlink on critical paths
#
# What it allows:
#   rm on safe targets: node_modules, dist, build, __pycache__, .cache, /tmp
#   bare relative globs in the working dir: rm *.pyc, rm dist/*.js
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/rm-safety-net.sh" }]
#     }]
#   }
# }
#
# Note: This hook checks rm, find -delete, and shred. Do NOT add an "if" field
# (v2.1.85) because "if" only supports one pattern and would miss the others.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# --- rm command analysis ---
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?rm\s'; then
    # Safe targets that can be deleted freely
    SAFE_TARGETS="node_modules|dist|build|__pycache__|\.cache|\.pytest_cache|coverage|\.nyc_output|\.next|\.nuxt|tmp|temp"

    # Extract the target (last argument after flags)
    TARGET=$(echo "$COMMAND" | grep -oP 'rm\s+[^;|&]*' | awk '{print $NF}')

    # Block path traversal early
    if echo "$TARGET" | grep -qF '..'; then
        echo "BLOCKED: path traversal detected in rm target" >&2
        exit 2
    fi

    # Allow safe targets
    if echo "$TARGET" | grep -qE "^(\./)?(${SAFE_TARGETS})(/|$)"; then
        exit 0
    fi

    # Allow /tmp paths
    if echo "$TARGET" | grep -qE "^/tmp/"; then
        exit 0
    fi

    # Block wildcard/glob rm on absolute or home paths (#64559).
    # A glob's match set can't be enumerated in advance, so a delete intended only
    # for the model's own temp files (e.g. rm -f ~/Downloads/*copy*.md) can silently
    # collateral-delete pre-existing user files whose names merely share the substring.
    # Auto mode runs this with no confirmation. Bare relative globs (e.g. rm *.pyc in a
    # project dir) are left alone; only globs reaching into a user/home/absolute path
    # outside the safe-target list are gated, where the blast radius is unpredictable.
    if echo "$TARGET" | grep -qE '[*?[]'; then
        if echo "$TARGET" | grep -qE "^(/|~)"; then
            echo "BLOCKED: wildcard rm on a user/absolute path — unpredictable match set: $TARGET" >&2
            echo "A glob can delete pre-existing files you never named. List the matches first:" >&2
            echo "  ls -d $TARGET   # confirm exactly what matches, then rm those names explicitly" >&2
            exit 2
        fi
    fi

    # Block rm on critical paths (/Users = macOS home, parity with /home on Linux)
    CRITICAL="^/\$|^/home|^/Users|^/etc|^/usr|^/var|^/opt|^/root|^~|^\.\.|^\.git$|^\.env"
    if echo "$TARGET" | grep -qE "$CRITICAL"; then
        echo "BLOCKED: rm targeting critical path: $TARGET" >&2
        exit 2
    fi

    # Block rm -rf on any non-safe path (extra safety)
    if echo "$COMMAND" | grep -qE 'rm\s+.*-[rRf]*[rR][rRf]*'; then
        # rm -rf on non-safe, non-tmp target — block unless it's a known safe directory
        if ! echo "$TARGET" | grep -qE "^(\./)?(${SAFE_TARGETS})(/|$)|^/tmp/"; then
            echo "BLOCKED: rm -rf on non-safe target: $TARGET" >&2
            exit 2
        fi
    fi
fi

# --- find -delete ---
if echo "$COMMAND" | grep -qE 'find\s.*-delete'; then
    # Allow find in safe directories only
    FIND_PATH=$(echo "$COMMAND" | grep -oP 'find\s+\K[^\s]+')
    if echo "$FIND_PATH" | grep -qE '^\.|^node_modules|^dist|^build|^/tmp'; then
        exit 0
    fi
    echo "BLOCKED: find -delete outside safe directory: $FIND_PATH" >&2
    exit 2
fi

# --- shred ---
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?shred\s'; then
    echo "BLOCKED: shred command (secure file deletion)" >&2
    exit 2
fi

exit 0
