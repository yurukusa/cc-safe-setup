#!/bin/bash
# agents-md-loader.sh — Detect AGENTS.md in the project tree at session start
# and surface its contents to Claude Code as a system-reminder, so the agent
# reads it alongside (or in place of) CLAUDE.md.
#
# Addresses: anthropics/claude-code#6235 (Feature Request: Support AGENTS.md),
# the highest-engagement feature request on the tracker (6,358 reactions),
# closed as completed on 2026-08-17.
#
# DOES CLAUDE CODE READ AGENTS.md NOW? Measured on v2.1.233, 2026-08-21: NO.
# The issue is closed, but AGENTS.md is still not loaded into the model's
# context the way CLAUDE.md is. The official CHANGELOG.md (5,693 lines, up
# to 2.1.238) does not mention AGENTS.md anywhere.
#
# This is easy to get wrong, so here is the method. Asking `claude -p` for a
# token planted in AGENTS.md is NOT a valid test: the agent will often find the
# file on its own with ls/cat and answer correctly, which looks identical to
# native loading. Stream the transcript instead and look at the tool calls:
#
#   claude -p "<question>" --output-format stream-json --verbose
#
#   CLAUDE.md planted ... answered with no file read  -> loaded into context
#   AGENTS.md planted ... agent ran `ls` then `cat`   -> NOT loaded; it looked
#
# So whether the agent sees AGENTS.md depends on whether it happens to go
# looking, which is not something you can rely on — and it costs tool calls
# every session when it does.
#
# This hook makes it deterministic instead: a SessionStart hook that
# detects AGENTS.md (in cwd or any parent up to git root), reads its
# contents (subject to a size cap to protect the context budget), and
# emits a <system-reminder> so the agent reads it the same way it reads
# CLAUDE.md.
#
# Precedence: the AGENTS.md specification specifies "closest file wins"
# for monorepos with nested AGENTS.md files. This hook follows the same
# rule — it walks upward from cwd and uses the first AGENTS.md found.
#
# Coexistence with CLAUDE.md: this hook does NOT replace CLAUDE.md.
# Both files load. If both exist, both are surfaced to the agent. The
# operator's CLAUDE.md takes precedence on Claude-specific conventions;
# AGENTS.md provides the vendor-neutral context.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_AGENTS_MD_MAX_BYTES        default 16384 (16 KiB) — file size cap
#                                  to protect context budget; AGENTS.md
#                                  larger than this is truncated and a
#                                  warning is appended.
#   CC_AGENTS_MD_SEARCH_PARENTS   default "1" — walk up to git root looking
#                                  for AGENTS.md. Set "0" to check only cwd.
#   CC_AGENTS_MD_LOADER_DISABLE   set to "1" to disable the hook entirely.
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "SessionStart": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/agents-md-loader.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_AGENTS_MD_LOADER_DISABLE:-0}" = "1" ] && exit 0

MAX_BYTES="${CC_AGENTS_MD_MAX_BYTES:-16384}"
SEARCH_PARENTS="${CC_AGENTS_MD_SEARCH_PARENTS:-1}"

# Find AGENTS.md by walking up from cwd. Stop at:
#   - first AGENTS.md found, OR
#   - filesystem root, OR
#   - top of git working tree (if inside one), OR
#   - $HOME, whichever comes first.

find_agents_md() {
    local dir="$PWD"
    local git_root=""

    git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)

    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -f "$dir/AGENTS.md" ]; then
            printf '%s\n' "$dir/AGENTS.md"
            return 0
        fi
        # Stop at git root if found.
        [ -n "$git_root" ] && [ "$dir" = "$git_root" ] && return 1
        # Stop at $HOME.
        [ "$dir" = "$HOME" ] && return 1
        # If SEARCH_PARENTS is disabled, only check cwd.
        [ "$SEARCH_PARENTS" = "0" ] && return 1
        dir=$(dirname "$dir")
    done
    return 1
}

AGENTS_MD_PATH=$(find_agents_md)
[ -z "$AGENTS_MD_PATH" ] && exit 0  # No AGENTS.md → silent no-op.

# Read the file with a byte cap. If the file is larger than MAX_BYTES,
# truncate and append a notice so the agent knows.
FILE_SIZE=$(wc -c < "$AGENTS_MD_PATH" 2>/dev/null || echo 0)
TRUNCATED=""

if [ "$FILE_SIZE" -gt "$MAX_BYTES" ]; then
    CONTENT=$(head -c "$MAX_BYTES" "$AGENTS_MD_PATH" 2>/dev/null)
    TRUNCATED="

[NOTE: AGENTS.md is $FILE_SIZE bytes; truncated to $MAX_BYTES bytes by agents-md-loader. Increase CC_AGENTS_MD_MAX_BYTES or read the full file with the Read tool if you need the rest.]"
else
    CONTENT=$(cat "$AGENTS_MD_PATH" 2>/dev/null)
fi

[ -z "$CONTENT" ] && exit 0

# Detect whether CLAUDE.md is also present (sibling or parent) so the
# reminder can name the coexistence.
CLAUDE_MD_SIBLING=""
PROJECT_DIR=$(dirname "$AGENTS_MD_PATH")
[ -f "$PROJECT_DIR/CLAUDE.md" ] && CLAUDE_MD_SIBLING="$PROJECT_DIR/CLAUDE.md"

# Emit the system-reminder on stderr (SessionStart hooks use stderr for
# context-augmenting reminders; exit 0 = non-blocking).

cat >&2 <<EOF
<system-reminder>
AGENTS.md detected at $AGENTS_MD_PATH ($FILE_SIZE bytes).

AGENTS.md is the vendor-neutral "README for agents" convention adopted by
Codex, Cursor, Aider, Zed, VS Code, Devin, JetBrains Junie, Amp, Gemini CLI,
GitHub Copilot, Windsurf, and 10+ other coding agents. Claude Code does
not yet natively read this file (see anthropics/claude-code#6235). This
hook surfaces its contents to you in the same way native CLAUDE.md loading
would.

The repository operator has chosen to keep cross-vendor context in
AGENTS.md so the same content serves every agent that visits the repo.
Treat the content below as project context with the same authority you
treat CLAUDE.md content.
$( [ -n "$CLAUDE_MD_SIBLING" ] && printf '%s\n' "
NOTE: CLAUDE.md is also present at $CLAUDE_MD_SIBLING. Both files are
in scope. CLAUDE.md takes precedence on Claude-Code-specific conventions
(hook configurations, slash commands, model-specific behaviour). AGENTS.md
governs cross-vendor project context (build commands, code style, test
instructions, security considerations).")

--- BEGIN $AGENTS_MD_PATH ---
$CONTENT$TRUNCATED
--- END $AGENTS_MD_PATH ---
</system-reminder>
EOF

exit 0
