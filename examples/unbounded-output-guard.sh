#!/bin/bash
# unbounded-output-guard.sh — Block commands that generate unbounded output
#                             before they run (PreToolUse)
#
# Solves: A single command like `yes`, `cat /dev/zero`, or `cat /dev/urandom`
#         produces output forever. When the agent captures that output to a
#         temp file, it fills the disk and hangs or crashes the session
#         (e.g. anthropics/claude-code#65789, #41737, #31858, #11155).
#
# Why a PreToolUse pattern check is needed:
#   Existing output guards (output-explosion-detector, tmp-output-size-guard)
#   are PostToolUse — they only measure output AFTER it is produced, so the
#   disk is already filling by the time they react. disk-space-guard is
#   PreToolUse but only blocks when free space is ALREADY low; a generator
#   that writes tens of GB in seconds blows past the threshold between checks.
#   This guard stops the known unbounded generators by command pattern,
#   regardless of current disk level.
#
# Detects (only when NOT bounded by head/timeout):
#   yes                          (infinite line generator)
#   cat /dev/zero|urandom|random (infinite byte stream)
#   base64 /dev/urandom          (infinite encoded stream)
#   ... < /dev/urandom           (infinite stream via redirection)
#
# Does NOT block (bounded forms are legitimate and common):
#   yes | head -n 5              (piped to head)
#   head -c 32 /dev/urandom      (head bounds the read)
#   timeout 1 yes                (time-bounded)
#   tr -dc 'a-z' < /dev/urandom | head -c 8   (piped to head)
#   echo yes                     (yes as an argument, not the command)
#
# Scope note: this fires on commands run through the Bash tool. The bang
#   form in #65789 (`!yes`, typed directly into Claude Code's own shell) does
#   NOT go through any tool, so no hook can intercept it — that case needs a
#   core output limit in Claude Code itself. This guard covers the Bash-tool
#   vector, which is the one that matters for autonomous agents.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Bounded forms are safe: head caps the byte/line count, timeout caps the time.
# Every common legitimate use of these generators pairs them with head or
# timeout, so their presence is a reliable signal that the output is bounded.
if echo "$COMMAND" | grep -qE '\b(head|timeout)\b'; then
    exit 0
fi

# `yes` in command position (start, or after a pipe/;/&) with no downstream bound.
# Requiring command position avoids matching `yes` used as an argument (echo yes).
if echo "$COMMAND" | grep -qE '(^|[;&|])[[:space:]]*yes([[:space:]]|$)'; then
    echo "BLOCKED: 'yes' produces infinite output with no bound." >&2
    echo "  Cap it, e.g. 'yes | head -n 5' or 'timeout 1 yes'." >&2
    exit 2
fi

# Infinite byte streams read via cat
if echo "$COMMAND" | grep -qE '\bcat\s+(-\S+\s+)*/dev/(zero|u?random)\b'; then
    echo "BLOCKED: 'cat /dev/zero|/dev/urandom|/dev/random' is an infinite stream." >&2
    echo "  This fills temp storage and can crash the session." >&2
    echo "  Use a bound, e.g. 'head -c 100 /dev/urandom'." >&2
    exit 2
fi

# base64 of an infinite device
if echo "$COMMAND" | grep -qE '\bbase64\s+(-\S+\s+)*/dev/(zero|u?random)\b'; then
    echo "BLOCKED: 'base64 /dev/urandom' encodes an infinite stream." >&2
    echo "  Bound the input first, e.g. 'head -c 48 /dev/urandom | base64'." >&2
    exit 2
fi

# Any command reading an infinite device via input redirection (tr/od/xxd/...)
if echo "$COMMAND" | grep -qE '<[[:space:]]*/dev/(zero|u?random)\b'; then
    echo "BLOCKED: reading /dev/zero|/dev/urandom|/dev/random with no bound." >&2
    echo "  Pipe through head, e.g. 'tr -dc a-z < /dev/urandom | head -c 8'." >&2
    exit 2
fi

exit 0
