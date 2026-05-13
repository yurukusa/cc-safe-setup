#!/bin/bash
# ================================================================
# sandbox-denyread-fallback.sh — Substitute enforcement for
# sandbox.filesystem.denyRead while the documented setting fails silently
# ================================================================
# PROBLEM (anthropics/claude-code#58636, May 13 2026):
#   `sandbox.filesystem.denyRead` in `~/.claude/settings.json` is documented
#   to block Claude Code from reading files that match its glob patterns
#   (.env*, credentials.json, *.pem, etc.). In v2.1.128 the setting is
#   silently ignored — Claude Code reads the file, displays the contents
#   in the conversation, and transmits them to Anthropic servers in the
#   transcript. No warning. No permission prompt. Confirmed reproduction
#   on macOS Haiku 4.5.
#
#   The reporter's example exposed Firebase API keys, Gemini API keys, and
#   database passwords. Equivalent compliance impact for NIS2, ISO 27001,
#   SOC 2, HIPAA. Critical-severity by any reasonable scoring.
#
# HOW IT WORKS:
#   PreToolUse hook on the Read tool. Reads `denyRead` glob patterns from
#   the project's `.claude/settings.json` (if present) and from
#   `~/.claude/settings.json`, then matches each pattern against the
#   read target's path using a glob-to-regex translation that handles
#   the `**`, `*`, and `?` wildcards correctly.
#
#   If any pattern matches, exit 2 with a message that names the matched
#   pattern and points at the upstream issue. Read is blocked before
#   Claude Code ever sees the file's contents — the conversation transcript
#   stays clean.
#
# TRIGGER: PreToolUse  MATCHER: "Read"
#
# CONFIGURATION:
#   The hook reads patterns from sandbox.filesystem.denyRead in
#   .claude/settings.json (project) and ~/.claude/settings.json (user).
#   No environment variables are required.
#
# WHAT THIS DOES NOT CATCH:
#   - Bash `cat`, `head`, `tail`, `grep` reading the file. Use
#     credential-file-cat-guard.sh + dotenv-read-guard.sh for those paths.
#   - Sub-agents using Read with a different working directory. The hook
#     evaluates both relative and absolute forms but cannot read patterns
#     scoped to a deeper repo if the sub-agent was launched outside it.
#   - Writes / Edits / Globs / Greps to the same paths. This hook only
#     blocks Read. Pair with dotenv-read-guard.sh and
#     credential-file-cat-guard.sh for full coverage.

set -u

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only act on Read tool calls
if [ "$TOOL" != "Read" ]; then
    exit 0
fi

if [ -z "$FILE" ]; then
    exit 0
fi

# Gather denyRead patterns from project + user settings (in this order)
PATTERNS=""
for SETTINGS in ".claude/settings.json" "$HOME/.claude/settings.json"; do
    if [ -f "$SETTINGS" ]; then
        EXTRACTED=$(jq -r '.sandbox.filesystem.denyRead[]? // empty' "$SETTINGS" 2>/dev/null)
        if [ -n "$EXTRACTED" ]; then
            if [ -z "$PATTERNS" ]; then
                PATTERNS="$EXTRACTED"
            else
                PATTERNS="${PATTERNS}"$'\n'"$EXTRACTED"
            fi
        fi
    fi
done

# Allow tests to inject patterns directly without writing settings.json
if [ -n "${CC_SANDBOX_DENYREAD_PATTERNS:-}" ]; then
    PATTERNS="${CC_SANDBOX_DENYREAD_PATTERNS}"
fi

# No patterns configured — nothing to enforce
if [ -z "$PATTERNS" ]; then
    exit 0
fi

# Match patterns against the target path using a glob-to-regex translation
MATCH=$(printf '%s' "$PATTERNS" | python3 -c '
import os
import re
import sys


def glob_to_regex(pat):
    out = []
    i = 0
    while i < len(pat):
        if pat[i:i + 3] == "**/":
            out.append("(?:.*/)?")
            i += 3
        elif pat[i:i + 2] == "**":
            out.append(".*")
            i += 2
        elif pat[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pat[i] == "?":
            out.append("[^/]")
            i += 1
        elif pat[i] in ".^$+(){}|[]\\":
            out.append("\\" + pat[i])
            i += 1
        else:
            out.append(pat[i])
            i += 1
    return "^" + "".join(out) + "$"


target = sys.argv[1]
abs_target = os.path.abspath(target)
basename = os.path.basename(target)
patterns = [p.strip() for p in sys.stdin.read().split("\n") if p.strip()]

for pat in patterns:
    regex = re.compile(glob_to_regex(pat))
    if regex.match(target) or regex.match(abs_target) or regex.match(basename):
        print(pat)
        sys.exit(0)
' "$FILE")

if [ -n "$MATCH" ]; then
    cat >&2 <<EOF
BLOCKED: Read of "$FILE" matches sandbox.filesystem.denyRead pattern: $MATCH

This hook (sandbox-denyread-fallback.sh) enforces the documented
sandbox.filesystem.denyRead behavior locally, because the in-product
setting silently fails to block reads as of v2.1.128 (see
anthropics/claude-code#58636). Without this hook, Claude Code reads
the file, displays it in the response, and transmits the contents to
Anthropic servers in the conversation transcript.

If the read is legitimate, remove the matching pattern from
sandbox.filesystem.denyRead, or move the file outside the pattern.
Do not paste the file contents into the conversation manually — that
defeats the point of the deny rule.
EOF
    exit 2
fi

exit 0
