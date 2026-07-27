#!/bin/bash
# ================================================================
# multi-vendor-concurrent-warner.sh — Warn when another AI coding
#   CLI (Codex, Gemini, Cursor, Aider, Amp, ...) is running at the
#   same time as Claude Code, so concurrent edits to the same repo
#   do not silently collide.
# ================================================================
# PURPOSE:
#   A growing number of operators run several AI coding tools in
#   parallel — Claude Code plus Codex, Gemini CLI, Cursor's agent,
#   Aider, Amp, and others — pointed at the same repository. Two
#   failure modes follow, and neither tool can see the other:
#     1. Conflicting edits. Two agents edit the same file; one
#        overwrites the other, or the repo lands in a broken state
#        (reported: dozens of type errors after a parallel run).
#     2. Cost is invisible. Each vendor bills separately; the
#        combined spend across tools is not shown in any one tool,
#        and parallel runs multiply it (operators report 3-5x).
#
#   Every other concurrency hook in cc-safe-setup bounds Claude
#   Code's OWN subagents (max-concurrent-agents, parallel-edit-guard,
#   subagent-budget-guard, ...). None of them can see a SEPARATE
#   vendor's process. This hook fills that gap: at session start it
#   checks the process table for other AI CLIs and, if it finds one,
#   prints a one-time advisory so the operator coordinates scope and
#   watches combined cost.
#
# UPSTREAM / CONTEXT:
#   The multi-vendor parallel-operation pattern (Claude Code + Codex
#   + Gemini + Grok) is a real and growing operator workflow. This
#   hook is advisory only — it never blocks and never inspects the
#   other tool; it only notes that it is running.
#
# TRIGGER: SessionStart   (also safe as PreToolUse)
#
# CONFIGURATION (env vars):
#   CC_MULTI_VENDOR_PROCS    Space-separated process names to treat
#                            as other AI CLIs. Default covers the
#                            common ones. Claude's own process is
#                            never matched.
#   CC_MULTI_VENDOR_PS       Override the command used to list
#                            process names (default: ps -eo comm=).
#   CC_MULTI_VENDOR_PS_OUTPUT  Pre-supplied process listing (tests).
# ================================================================

set -u

# Read and discard stdin (hook protocol); this hook does not use it.
cat > /dev/null 2>&1 || true

DEFAULT_PROCS="codex gemini cursor-agent cursor-agent-cli aider amp ampcode grok cline continue goose qwen"
PROCS="${CC_MULTI_VENDOR_PROCS:-$DEFAULT_PROCS}"

# Obtain the list of running process names.
if [ -n "${CC_MULTI_VENDOR_PS_OUTPUT:-}" ]; then
    PS_LIST="$CC_MULTI_VENDOR_PS_OUTPUT"
else
    PS_CMD="${CC_MULTI_VENDOR_PS:-ps -eo comm=}"
    PS_LIST="$($PS_CMD 2>/dev/null)"
fi

[ -z "$PS_LIST" ] && exit 0

# Match each candidate as a whole basename token so "cursor-agent"
# does not match unrelated names. We compare against the basename of
# each process entry to tolerate full paths in some ps formats.
FOUND=""
while IFS= read -r raw; do
    [ -z "$raw" ] && continue
    name="${raw##*/}"          # basename
    name="${name%% *}"          # strip args if present
    for p in $PROCS; do
        if [ "$name" = "$p" ]; then
            case " $FOUND " in
                *" $p "*) : ;;          # already recorded
                *) FOUND="$FOUND $p" ;;
            esac
        fi
    done
done <<EOF
$PS_LIST
EOF

FOUND="${FOUND# }"
[ -z "$FOUND" ] && exit 0

MSG="DETECTED: another AI coding CLI appears to be running alongside Claude Code: ${FOUND}.
Running multiple AI tools against the same repository at once has two failure modes that neither tool can see on its own:
  - Conflicting edits: two agents change the same file; one silently overwrites the other, or the repo lands half-edited.
  - Combined cost is invisible: each vendor bills separately, so no single tool shows your total spend, and parallel runs multiply it.
Operator-side mitigations:
  1. Give each tool a disjoint scope (different directories or files) and commit frequently so collisions surface in git, not at runtime.
  2. Track spend per vendor separately; assume the combined monthly cost, not any single tool's number.
  3. Prefer a clear lead tool for edits and use the others for read-only review while both are live.
This hook is advisory only — it does not read or stop the other tool. The session continues normally."

if command -v jq > /dev/null 2>&1; then
    jq -n --arg msg "$MSG" '
    {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": $msg
        }
    }'
else
    echo "$MSG" >&2
fi
exit 0
