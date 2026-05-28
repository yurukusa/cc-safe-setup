#!/bin/bash
# cowork-claude-md-load-checker.sh — Surface ~/.claude/CLAUDE.md at SessionStart
#
# Solves: #62859 — Cowork (Claude desktop app) does NOT load ~/.claude/CLAUDE.md
#         at session start. Users who keep safety-critical standing instructions
#         (e.g. "Always ask before write operations to MCP tools") in
#         ~/.claude/CLAUDE.md lose those guardrails whenever they open a Cowork
#         session, because Cowork only honors part of the ~/.claude/ directory.
#         Related: #50669 (Cowork loads only 3/27 personal skills).
#
# WHO THIS PROTECTS:
#   CLI users who also use Cowork on the same machine. The hook runs in the
#   CLI (where hooks DO fire), and:
#     (a) confirms ~/.claude/CLAUDE.md is loaded in this CLI session by
#         echoing a short header + the file's first lines to stderr at
#         SessionStart;
#     (b) reminds the operator that the same file will NOT auto-load in
#         Cowork, so they should paste it manually when switching surfaces.
#
#   Cowork itself ignores ~/.claude/, so the hook cannot run inside Cowork.
#   The protection is the operator-side awareness this hook builds in CLI.
#
# HOW IT WORKS:
#   On SessionStart, if ~/.claude/CLAUDE.md exists and is non-trivial
#   (>= CC_COWORK_MD_MIN_BYTES, default 50 bytes), print a warning block to
#   stderr with the first N bytes of the file and a one-line note linking
#   to #62859. Always exit 0 (advisory only).
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# CONFIGURATION:
#   CC_COWORK_MD_PATH=path       override file (default ~/.claude/CLAUDE.md)
#   CC_COWORK_MD_MIN_BYTES=N     skip if file smaller than N (default 50)
#   CC_COWORK_MD_MAX_CHARS=N     truncate display at N (default 1500)
#   CC_COWORK_MD_QUIET=1         suppress the reminder line about Cowork
#   CC_COWORK_MD_LOG=path        append load events (default off)
#
# USAGE:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/cowork-claude-md-load-checker.sh"
#       }]
#     }]
#   }
# }

MD_PATH="${CC_COWORK_MD_PATH:-$HOME/.claude/CLAUDE.md}"
MIN_BYTES="${CC_COWORK_MD_MIN_BYTES:-50}"
MAX_CHARS="${CC_COWORK_MD_MAX_CHARS:-1500}"

# Drain stdin (SessionStart hooks may or may not receive payload)
INPUT=$(cat 2>/dev/null || true)

if [ ! -f "$MD_PATH" ]; then
    exit 0
fi

ACTUAL_SIZE=$(wc -c < "$MD_PATH" 2>/dev/null || echo 0)
if [ "$ACTUAL_SIZE" -lt "$MIN_BYTES" ]; then
    exit 0
fi

CONTENT=$(head -c "$MAX_CHARS" "$MD_PATH" 2>/dev/null)

cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[cowork-claude-md-load-checker] SessionStart — surfacing ${MD_PATH}
Addresses #62859: Cowork (Claude desktop app) does NOT load
~/.claude/CLAUDE.md at session start. This hook runs in CLI only
and re-states the file's contents so the rules remain in context.
These are standing instructions that apply across all projects.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CONTENT}
EOF

if [ "$ACTUAL_SIZE" -gt "$MAX_CHARS" ]; then
    echo "" >&2
    echo "[...truncated at ${MAX_CHARS} chars of ${ACTUAL_SIZE}. Full file: ${MD_PATH}]" >&2
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

if [ -z "${CC_COWORK_MD_QUIET:-}" ]; then
    cat >&2 <<'EOF'
[cowork-claude-md-load-checker] Reminder: if you switch to Cowork on the same
machine, the file above will NOT auto-load there. Paste it manually into the
Cowork chat until #62859 is resolved.
EOF
fi

if [ -n "${CC_COWORK_MD_LOG:-}" ]; then
    mkdir -p "$(dirname "$CC_COWORK_MD_LOG")" 2>/dev/null
    echo "$(date -Iseconds) file=${MD_PATH} size=${ACTUAL_SIZE}" >> "$CC_COWORK_MD_LOG"
fi

exit 0
