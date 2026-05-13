#!/bin/bash
# code-freeze-respect-guard.sh — Block destructive operations when an explicit code freeze is declared
#
# Prevents the structural pattern observed in HN 47911524 (2026-04-26, 860 points, 1,032 comments)
# where an AI agent received an explicit "code freeze" signal in CLAUDE.md / README / a memory file,
# acknowledged the signal, then executed a destructive operation (production database deletion).
#
# The pattern matches the broader "silent override of operator's persistent intent" failure mode
# documented across multiple Tier-1 incidents (Amazon Kiro, Claude Cowork, PocketOS, etc).
#
# This hook detects:
#   1. Code freeze signal in operator-controlled files (CLAUDE.md, README.md, FREEZE.md, .freeze, memory/*)
#   2. Destructive Bash command (rm -rf, git reset --hard, DROP DATABASE, etc)
#
# When both are present, the hook blocks execution with exit 2.
#
# Designed as a *secondary* hook, complementary to destructive-guard and block-database-wipe.
# The primary value: catches destructive operations that bypass per-operation matchers because
# they use vendor-specific APIs (Railway CLI, AWS CLI, etc) where the destructive intent is
# obvious from the freeze context but not from the command pattern alone.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/code-freeze-respect-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Regex parts (use POSIX character classes since \s and \b are not portable in -E)
FREEZE_PATTERN='code[[:space:]]*freeze|deployment[[:space:]]*freeze|do[[:space:]]+not[[:space:]]+deploy|do[[:space:]]+not[[:space:]]+destroy|do[[:space:]]+not[[:space:]]+delete|hold[[:space:]]+all|凍結|停止中|本番[[:space:]]*停止'

# Step 1: Detect freeze signal from operator-controlled files
FREEZE_DETECTED=0
FREEZE_SOURCE=""

for f in CLAUDE.md README.md FREEZE.md .freeze; do
    if [ -f "$f" ]; then
        if grep -qiE "$FREEZE_PATTERN" "$f" 2>/dev/null; then
            FREEZE_DETECTED=1
            FREEZE_SOURCE="$f"
            break
        fi
    fi
done

# Check memory/ directory for freeze keywords
if [ "$FREEZE_DETECTED" -eq 0 ] && [ -d "memory" ]; then
    MEMORY_HIT=$(find memory -maxdepth 2 -type f \( -name "*.md" -o -name "*.txt" \) -exec grep -liE "$FREEZE_PATTERN" {} \; 2>/dev/null | head -1)
    if [ -n "$MEMORY_HIT" ]; then
        FREEZE_DETECTED=1
        FREEZE_SOURCE="$MEMORY_HIT"
    fi
fi

# Check ~/.claude/ for freeze keywords
if [ "$FREEZE_DETECTED" -eq 0 ] && [ -d "$HOME/.claude" ]; then
    for f in "$HOME/.claude/CLAUDE.md" "$HOME/.claude/FREEZE.md" "$HOME/.claude/.freeze"; do
        if [ -f "$f" ]; then
            if grep -qiE "$FREEZE_PATTERN" "$f" 2>/dev/null; then
                FREEZE_DETECTED=1
                FREEZE_SOURCE="$f"
                break
            fi
        fi
    done
fi

# No freeze signal - hook does not block
[[ "$FREEZE_DETECTED" -eq 0 ]] && exit 0

# Step 2: Detect destructive command
DESTRUCTIVE=0
DESTRUCTIVE_REASON=""

# Filesystem destruction (rm with destructive flags)
if echo "$COMMAND" | grep -qiE '(^|[[:space:]])rm[[:space:]]+(-[rRfF]+[[:space:]]|--recursive|--force)'; then
    DESTRUCTIVE=1
    DESTRUCTIVE_REASON="rm with destructive flags"
fi

# Database destruction
if echo "$COMMAND" | grep -qiE 'DROP[[:space:]]+(DATABASE|TABLE|SCHEMA)|TRUNCATE[[:space:]]+TABLE|DELETE[[:space:]]+FROM[[:space:]]+[a-zA-Z_]+[[:space:]]*(;|$)'; then
    DESTRUCTIVE=1
    DESTRUCTIVE_REASON="SQL destructive command"
fi

# Git destructive operations
if echo "$COMMAND" | grep -qiE 'git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+clean[[:space:]]+-[fdx]+|git[[:space:]]+push[[:space:]]+--force|git[[:space:]]+push[[:space:]]+-f([[:space:]]|$)'; then
    DESTRUCTIVE=1
    DESTRUCTIVE_REASON="git destructive command"
fi

# Vendor-specific destructive APIs
if echo "$COMMAND" | grep -qiE 'railway[[:space:]]+(volume|service|database)[[:space:]]+delete|aws[[:space:]]+(s3|rds|ec2)[[:space:]]+(rm|delete-)|gcloud[[:space:]]+[a-z]+[[:space:]]+delete|kubectl[[:space:]]+delete[[:space:]]+(pv|pvc|namespace)'; then
    DESTRUCTIVE=1
    DESTRUCTIVE_REASON="vendor destructive API"
fi

# Deployment commands
if echo "$COMMAND" | grep -qiE '(vercel|netlify|fly)[[:space:]]+deploy|kubectl[[:space:]]+apply|terraform[[:space:]]+apply|ansible-playbook'; then
    DESTRUCTIVE=1
    DESTRUCTIVE_REASON="deployment command"
fi

# No destructive operation - hook does not block
[[ "$DESTRUCTIVE" -eq 0 ]] && exit 0

# Allow override via env var
if [ "${CFRG_ALLOW:-0}" = "1" ]; then
    exit 0
fi

# Both freeze + destructive: block
echo "BLOCKED: code freeze is in effect, but the proposed command is destructive." >&2
echo "  Freeze source: $FREEZE_SOURCE" >&2
echo "  Destructive reason: $DESTRUCTIVE_REASON" >&2
echo "  Command: $COMMAND" >&2
echo "" >&2
echo "  This hook prevents the structural pattern from HN 47911524 (production DB" >&2
echo "  deletion after operator-declared freeze). To override, either:" >&2
echo "    1. Remove the freeze signal from $FREEZE_SOURCE, or" >&2
echo "    2. Set CFRG_ALLOW=1 for this session" >&2
echo "" >&2

exit 2
