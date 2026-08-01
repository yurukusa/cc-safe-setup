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
#   find ... | xargs rm  without the null-delimited pair -print0 / xargs -0 (#69793 —
#     a path with spaces splits into multiple targets and rm -rf wipes an unrelated dir)
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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-rm-safety-net-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [rm-safety-net]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# The extractions in this hook used grep -oP, which is GNU-only. BSD grep
# (macOS) rejects -P, so the targets came back empty and every critical-path
# check silently found nothing to inspect. The GNU path is left exactly as it
# was; an equivalent runs where -P is absent. Defined at file scope because the
# find/xargs sections below use it too.
if echo x | grep -qP x 2>/dev/null; then HAS_PCRE=1; else HAS_PCRE=0; fi

# $1 = command word, $2 = operand pattern. \K has no POSIX equivalent, so the
# fallback matches from the command word and strips that prefix afterwards.
extract_operand() {
    if [ "$HAS_PCRE" = 1 ]; then
        grep -oP "$1\\s+\\K$2" 2>/dev/null || true
    else
        grep -oE "$1[[:space:]]+$2" 2>/dev/null | sed -E "s/^$1[[:space:]]+//" || true
    fi
}

# --- rm command analysis ---
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?rm\s'; then
    # Safe targets that can be deleted freely
    SAFE_TARGETS="node_modules|dist|build|__pycache__|\.cache|\.pytest_cache|coverage|\.nyc_output|\.next|\.nuxt|tmp|temp"
    CRITICAL="^/\$|^/home|^/Users|^/etc|^/usr|^/var|^/opt|^/root|^~|^\.\.|^\.git$|(^|/)\.env"

    # Extract the target (last argument after flags)
    if [ "$HAS_PCRE" = 1 ]; then
        TARGET=$(echo "$COMMAND" | grep -oP 'rm\s+[^;|&]*' | awk '{print $NF}')
    else
        TARGET=$(echo "$COMMAND" | grep -oE 'rm[[:space:]]+[^;|&]*' | awk '{print $NF}')
    fi

    # Block path traversal early
    if echo "$TARGET" | grep -qF '..'; then
        echo "BLOCKED: path traversal detected in rm target" >&2
        exit 2
    fi

    # Inspect EVERY non-flag argument for critical paths, not just the last one.
    # The single-TARGET checks below use `awk '{print $NF}'` (last arg only), so
    # "rm -rf /home/user/data node_modules" would early-exit on the safe LAST arg
    # (node_modules) and never inspect the critical FIRST arg — a real bypass.
    # set -f disables glob expansion of the split words (so "rm *.pyc" stays literal).
    set -f
    for arg in $(echo "$COMMAND" | extract_operand 'rm' '[^;|&]*'); do
        case "$arg" in -*) continue ;; esac   # skip flags
        if echo "$arg" | grep -qE "$CRITICAL"; then
            set +f
            echo "BLOCKED: rm targeting critical path: $arg" >&2
            exit 2
        fi
    done
    set +f

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
    # .env is matched at the start OR after any path segment, so a nested path
    # like backend/.env or src/.env is caught too (#65034 — Claude deleted a
    # .env living in a subdirectory, which the start-anchored pattern missed).
    # CRITICAL is defined once near the top of this block (also used by the
    # multi-argument loop above). This single-TARGET check stays as a backstop.
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
    FIND_PATH=$(echo "$COMMAND" | extract_operand 'find' '[^[:space:]]+')
    if echo "$FIND_PATH" | grep -qE '^\.|^node_modules|^dist|^build|^/tmp'; then
        exit 0
    fi
    echo "BLOCKED: find -delete outside safe directory: $FIND_PATH" >&2
    exit 2
fi

# --- find | xargs rm without a null delimiter (#69793) ---
# find prints newline-separated paths; xargs WITHOUT -0 splits on ANY whitespace.
# So a single path containing spaces, e.g. "./Google Photos/a.jpg", is split into
# two arguments: "./Google" and "Photos/a.jpg". With rm -rf, the first token can
# match an UNRELATED real directory ("./Google") and wipe it whole — the reporter
# in #69793 lost ~28,800 files this way. The rm checks above can't catch this:
# the delete targets are produced by find at runtime, so there is no literal path
# in the command string to inspect. The only safe form is the null-delimited pair
# find -print0 | xargs -0 (or avoid xargs: find -delete / -exec rm {} +).
if echo "$COMMAND" | grep -qE 'xargs\b[^|]*\b(rm|rmdir|unlink|shred|trash|trash-put)\b'; then
    # Require BOTH halves of the null-delimited pair: find's -print0 and xargs's -0.
    if ! echo "$COMMAND" | grep -qE '\-print0' \
       || ! echo "$COMMAND" | grep -qE 'xargs\s+[^|]*(-0|--null)'; then
        echo "BLOCKED: 'xargs rm' without a null delimiter — paths with spaces split into multiple targets (#69793)." >&2
        echo "  A path like './Google Photos/a.jpg' splits into './Google' and 'Photos/a.jpg';" >&2
        echo "  rm -rf may then wipe an unrelated real directory. Use one of:" >&2
        echo "    find ... -delete" >&2
        echo "    find ... -exec rm -rf {} +" >&2
        echo "    find ... -print0 | xargs -0 rm -rf" >&2
        exit 2
    fi
fi

# --- shred ---
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?shred\s'; then
    echo "BLOCKED: shred command (secure file deletion)" >&2
    exit 2
fi

exit 0
