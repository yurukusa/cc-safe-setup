#!/bin/bash
# rg-replace-flag-detector.sh — Warn when Claude reaches for `rg -r` thinking it means recursive
#
# Solves: anthropics/claude-code#62016 — Claude's "grep -r" muscle memory leads it
#         to invoke `rg -rn`, which ripgrep parses as `--replace=n`. Every match is
#         silently rewritten to the literal `n` in stdout, exit 0, no error. Claude
#         then reads its own corrupted output, misattributes the garbage to an
#         "external cause" (post-processing layer, compression), and burns cycles
#         debugging a self-inflicted flag bug.
#
# How it works: PreToolUse hook on Bash that scans the proposed command for the
#   `rg -r[a-z]` pattern (and variants like `rg -rn`, `rg -rln`, `rg --replace`
#   without TEXT). Emits a stderr advisory pointing to the correct flag
#   (`-l` for line numbers is wrong too; line numbers are `-n`; recursive search
#   is the default for ripgrep, so no `-r` needed at all). Default mode is
#   advisory (exit 0 with stderr); strict mode (env var CC_RG_REPLACE_DETECTOR_MODE=strict)
#   blocks the call (exit 2).
#
# This is the Cluster-4 hook from the 2026-05-25 customer pain audit
# (~/ops/customer-pain-audit-2026-05-25-post-launch-cluster.md). It catches
# the tool-flag self-deception pattern at the boundary where the corrupted
# output would otherwise enter the model's context.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/rg-replace-flag-detector.sh" }]
#     }]
#   }
# }
#
# Configuration:
#   CC_RG_REPLACE_DETECTOR_DISABLE=1 — skip the check entirely
#   CC_RG_REPLACE_DETECTOR_MODE=strict — exit 2 (hard block) instead of exit 0 (advisory)

# Read stdin first so the upstream writer never sees EPIPE, even when disabled.
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-rg-replace-flag-detector-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [rg-replace-flag-detector]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat 2>/dev/null || true)

[ "${CC_RG_REPLACE_DETECTOR_DISABLE:-0}" = "1" ] && exit 0
[ -z "$INPUT" ] && exit 0

# Only fire on Bash tool calls.
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Detect rg with -r or --replace flag.
# Patterns to catch:
#   rg -r <TEXT>
#   rg -rn / rg -rln (recursive + line numbers — but rg -r is --replace, not recursive)
#   rg -r=<TEXT>
#   rg --replace=<TEXT>
#   rg --replace <TEXT>
# Patterns to skip (no false positive):
#   rg -e <PATTERN> (extended regex, different flag)
#   rg --regexp=<PATTERN>
#   rg -i / --ignore-case
DETECTED=""

# Approach: confirm `rg` is invoked, then look for any short-flag token containing
# `r` anywhere in the rg invocation (separated by whitespace, not embedded in a
# long flag like `--regexp`).
#
# Step 1: confirm rg appears as a command (start of line, after pipe/semicolon,
# or after a word boundary like xargs).
if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]|;&]|xargs[[:space:]]+)rg([[:space:]]|$)'; then
    # Step 2: look for any short-flag token (single -, not --) containing r.
    # This matches `-r`, `-rn`, `-rln`, `-rH`, `-erR`, etc. but NOT `--regexp` or `--replace=X`.
    if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]])-[a-zA-Z]*r[a-zA-Z]*([[:space:]]|$)'; then
        DETECTED="short-flag"
    fi
    # Step 3: explicitly match --replace as a long flag.
    if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]])--replace([=[:space:]]|$)'; then
        DETECTED="long-flag"
    fi
fi

[ -z "$DETECTED" ] && exit 0

cat >&2 <<EOF
<system-reminder>
rg-replace-flag-detector caught a likely flag-misuse pattern.

Command: $COMMAND

The flag \`-r\` in ripgrep means \`--replace=TEXT\`, NOT recursive. Recursive
search is the default for ripgrep. If you intended \`grep -rn\` muscle memory:

  WRONG:   rg -rn "pattern" path/         # rewrites every match to literal "n"
  RIGHT:   rg -n "pattern" path/          # line numbers, recursive by default
  ALSO:    rg "pattern" path/             # line numbers via default config
  ALSO:    rg --line-number "pattern" .   # explicit long form

If you actually meant to replace text in output, ignore this warning. Otherwise
the resulting stdout is silently corrupted (exit 0, no error) and reading it
back will misattribute the garbage to an external cause.

Source: anthropics/claude-code#62016
EOF

# Strict mode blocks; default mode advises.
if [ "${CC_RG_REPLACE_DETECTOR_MODE:-advisory}" = "strict" ]; then
    exit 2
fi

exit 0
