#!/bin/bash
# ================================================================
# tool-result-size-guard.sh — Block or warn on Bash commands likely to produce oversized output
# ================================================================
# PURPOSE:
#   Many Bash patterns produce unbounded or very large output even on small
#   inputs: `find /` (root scan), `ls -R` (recursive ls), `tail -f`
#   (streaming, never returns), `dmesg`, `journalctl` without -n,
#   `git log` without -n / --oneline, `npm ls -a` / `pip list` without
#   filter, `docker logs` without --tail. These burn Claude Code quota
#   fast — a single such call can consume several percent of the monthly
#   allowance on the Max $200 plan.
#
#   This hook detects such patterns BEFORE the command runs (PreToolUse)
#   and warns with a specific safer alternative. Set CC_TOOL_RESULT_BLOCK=1
#   to upgrade warning to a hard block.
#
#   Companion to large-read-guard.sh (which checks specific file sizes)
#   and output-explosion-detector.sh (which warns AFTER the burn happened).
#   This hook prevents the burn upfront.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIG:
#   CC_TOOL_RESULT_BLOCK=0      (default: warn only; set 1 to block)
#   CC_TOOL_RESULT_GUARD_SKIP=  (comma-separated patterns to skip, e.g. "find,ls")
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-tool-result-size-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [tool-result-size-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

BLOCK_MODE="${CC_TOOL_RESULT_BLOCK:-0}"
SKIP_PATTERNS="${CC_TOOL_RESULT_GUARD_SKIP:-}"

# Helper: emit warning or block based on mode
# Args: <id> <description> <suggested-alternative>
emit() {
    local id="$1" pattern="$2" suggest="$3"
    # Skip if user explicitly opted out of this id (comma-separated)
    if [ -n "$SKIP_PATTERNS" ] && echo "$SKIP_PATTERNS" | tr ',' '\n' | grep -qx "$id"; then
        return 0
    fi
    if [ "$BLOCK_MODE" = "1" ]; then
        echo "BLOCKED by tool-result-size-guard: $pattern is likely to produce oversized output." >&2
        echo "Safer alternative: $suggest" >&2
        echo "To override for this session: unset CC_TOOL_RESULT_BLOCK or set CC_TOOL_RESULT_GUARD_SKIP=$id" >&2
        exit 2
    fi
    echo "WARNING (tool-result-size-guard): $pattern is likely to produce large output." >&2
    echo "Safer alternative: $suggest" >&2
    echo "Set CC_TOOL_RESULT_BLOCK=1 to block, or CC_TOOL_RESULT_GUARD_SKIP=$id to suppress." >&2
}

# Pattern 1: find / or find ~ (root/home scans without -maxdepth or limit)
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\| | && |\| )\s*find\s+(/|~)([^a-zA-Z0-9_/-]|$)'; then
    if ! echo "$COMMAND" | grep -qE '\-maxdepth|\-quit|\| head|\| wc'; then
        emit "find" "find / or find ~ without -maxdepth or head/wc piping" \
             "find / -maxdepth 3 -name '<pattern>' | head -50"
    fi
fi

# Pattern 2: ls -R (recursive without limit)
if echo "$COMMAND" | grep -qE '(^|;|&&|\| )\s*ls\s+(-[a-zA-Z]*R[a-zA-Z]*)\b'; then
    if ! echo "$COMMAND" | grep -qE '\| head|\| tail|\| wc'; then
        emit "ls-r" "ls -R (recursive listing without limit)" \
             "ls -R <dir> | head -100  OR  find <dir> -maxdepth 2 -type f"
    fi
fi

# Pattern 3: tail -f (streaming, never returns in a Claude Code session)
if echo "$COMMAND" | grep -qE '(^|;|&&|\| )\s*tail\s+(-[a-zA-Z]*f[a-zA-Z]*)\b'; then
    emit "tail-f" "tail -f (streaming follow — does not return)" \
         "tail -n 100 <file>  (one-shot read of last 100 lines)"
fi

# Pattern 4: dmesg (system log, often >1MB)
if echo "$COMMAND" | grep -qE '(^|;|&&|\| )\s*(sudo\s+)?dmesg\b'; then
    if ! echo "$COMMAND" | grep -qE '\| head|\| tail|\| wc|-T\s'; then
        emit "dmesg" "dmesg without head/tail" \
             "dmesg | tail -100  OR  dmesg --time-format=iso | grep <pattern>"
    fi
fi

# Pattern 5: journalctl without -n
if echo "$COMMAND" | grep -qE '(^|;|&&|\| )\s*(sudo\s+)?journalctl\b'; then
    if ! echo "$COMMAND" | grep -qE '\-n\s+[0-9]|\-\-lines|\| head|\| tail|\| wc'; then
        emit "journalctl" "journalctl without -n or pipe to head/tail" \
             "journalctl -n 100  OR  journalctl --since '1 hour ago' | tail -200"
    fi
fi

# Pattern 6: git log without -n or --oneline
if echo "$COMMAND" | grep -qE '(^|;|&&|\| )\s*git\s+log\b'; then
    if ! echo "$COMMAND" | grep -qE '\-n\s*[0-9]|\-\-max-count|\-[0-9]+|\-\-oneline|\| head|\| tail'; then
        emit "git-log" "git log without -n / -<N> / --oneline limit" \
             "git log -20 --oneline  OR  git log -20"
    fi
fi

# Pattern 7: npm ls -a (full dependency tree) or pip list (without filter)
if echo "$COMMAND" | grep -qE '(^|;|&&|\| )\s*npm\s+(ls|list)\s+(-a|--all)\b'; then
    emit "npm-ls" "npm ls -a / npm ls --all (full recursive deps tree)" \
         "npm ls --depth=0  OR  npm ls <package>"
fi
if echo "$COMMAND" | grep -qE '(^|;|&&|\| )\s*pip\s+list\b' && \
   ! echo "$COMMAND" | grep -qE '\| grep|\| head|\| wc|\-\-format'; then
    emit "pip-list" "pip list without filter" \
         "pip list | grep <pattern>  OR  pip show <package>"
fi

# Pattern 8: docker logs without --tail
if echo "$COMMAND" | grep -qE '(^|;|&&|\| )\s*docker\s+logs\b'; then
    if ! echo "$COMMAND" | grep -qE '\-\-tail|\-n\s+[0-9]|\| head|\| tail'; then
        emit "docker-logs" "docker logs without --tail" \
             "docker logs --tail 200 <container>"
    fi
fi

exit 0
