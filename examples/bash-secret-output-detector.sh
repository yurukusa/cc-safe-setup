#!/bin/bash
# bash-secret-output-detector.sh — Warn when Bash output contains secrets
#
# Solves: Bash command output containing API keys, tokens, or credentials
#         enters the LLM context window and gets sent to the API provider
#         (#39882). PostToolUse hook that scans stdout for secret patterns.
#
# How it works: PostToolUse hook on Bash that checks command stdout for
#   patterns matching API keys, tokens, passwords, and connection strings.
#   When one matches, it prints a warning on stderr, so you see it in the
#   terminal. By default it does not interrupt the turn (exit 0).
#
# WHAT THIS DOES NOT DO BY DEFAULT: it does not put the warning in front of
#   the model. Until 2026-09-20 this hook wrote {"systemMessage": ...} to
#   stdout on exit 0 and the header said it warned the model. Measured on
#   2.1.278, PostToolUse matcher Bash, in a disposable HOME, judging by
#   whether a unique token in the message came back when the model was asked
#   to quote everything it had been shown:
#
#     nothing printed (control)                 not delivered
#     top-level {"systemMessage": ...}, exit 0   not delivered
#     stderr + exit 2 (positive control)         DELIVERED
#
#   The positive control is the point: the probe can see a delivered message,
#   so the middle row is not an artefact of how it was read. In that run the
#   model said in as many words that no hook output appeared, while quoting
#   the system reminders it had been given.
#
#   So on exit 0 the warning reaches you and not the model. If you want the
#   model to be told, set CC_SECRET_OUTPUT_BLOCK=1 below — that is the shape
#   measured as delivered. It is a blocking error: the tool has already run,
#   and Claude is told about it and can act on it.
#
# TRIGGER: PostToolUse
# MATCHER: "Bash"
#
# Environment:
#   CC_SECRET_OUTPUT_BLOCK=1  — exit 2 after warning, so the model is told.
#                               Default (unset) warns on stderr and exits 0.
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/bash-secret-output-detector.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty' 2>/dev/null)

[ -z "$STDOUT" ] && exit 0

# Secret patterns (high-confidence, low false-positive)
FOUND=""

# AWS keys
if echo "$STDOUT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
    FOUND="${FOUND}AWS access key, "
fi

# Generic API keys/tokens (long hex/base64 strings after key= or token=)
if echo "$STDOUT" | grep -qiE '(api[_-]?key|api[_-]?secret|auth[_-]?token|access[_-]?token|secret[_-]?key)\s*[:=]\s*\S{20,}'; then
    FOUND="${FOUND}API key/token, "
fi

# Connection strings with passwords
if echo "$STDOUT" | grep -qiE '(mysql|postgres|mongodb|redis)://[^:]+:[^@]+@'; then
    FOUND="${FOUND}database connection string, "
fi

# Private keys
# `--` is required: without it grep reads the leading dashes of the PEM
# header as options and dies with "unrecognized option", so this check
# silently never fired. The six existing checks in test.sh only assert
# exit 0, and this hook always exited 0, so they passed anyway.
# The same omission was found in ci-workflow-guard.sh and fixed in the same
# branch; a sweep of examples/ and hooks/ for a grep pattern starting with a
# dash found no third case.
if echo "$STDOUT" | grep -qE -- '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'; then
    FOUND="${FOUND}private key, "
fi

# JWT tokens
if echo "$STDOUT" | grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+'; then
    FOUND="${FOUND}JWT token, "
fi

# GitHub/GitLab tokens
if echo "$STDOUT" | grep -qE '(ghp|gho|ghs|ghr|glpat)_[A-Za-z0-9]{30,}'; then
    FOUND="${FOUND}GitHub/GitLab token, "
fi

if [ -n "$FOUND" ]; then
    FOUND="${FOUND%, }"
    # stderr, not stdout: a {"systemMessage": ...} object on stdout is dropped
    # here (measured 2026-09-20, table in the header). stderr at least reaches
    # the terminal, and with BLOCK=1 it reaches the model too.
    echo "⚠ SECRET DETECTED in command output: ${FOUND}." >&2
    echo "  Do NOT repeat, log, or include these values in any output." >&2
    echo "  They are already in the context window and should be treated as redacted." >&2
    if [ "${CC_SECRET_OUTPUT_BLOCK:-0}" = "1" ]; then
        exit 2
    fi
fi

exit 0
