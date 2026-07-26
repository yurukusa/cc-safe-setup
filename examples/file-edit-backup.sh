#!/bin/bash
# file-edit-backup.sh — Auto-backup files before they are overwritten
#
# Solves: Claude Code overwrites important files and the changes are hard
#         to reverse. This creates a timestamped backup before each write,
#         so you can always recover the previous version.
#
# Real incidents:
#   #37478 — .bashrc overwritten without permission
#   #32938 — 11h of inference output deleted
#   #36339 — C:\Users directory wiped (NTFS junction traversal)
#
# Backups go to ~/.claude/file-backups/ with timestamps.
# Old backups (>7 days) are auto-cleaned to prevent disk bloat.
#
# Covers BOTH paths by which a file gets overwritten:
#   1. The Edit / Write tools       -> tool_input.file_path
#   2. Shell commands run via Bash  -> redirection (> >>), tee, mv
#
# Path 2 was reported by a reader (2026-07-17) as the biggest hole in this
# hook: an agent writing through Bash has the same destructive power as
# Write, but used to slip past this backup entirely. Extraction below is
# deliberately generous — a spurious backup costs one file copy, a missed
# one costs the file.
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write|Bash"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

BACKUP_DIR="$HOME/.claude/file-backups"

backup_one() {
    local target="$1"
    [ -z "$target" ] && return 0
    # Strip quotes left over from the command line
    target="${target%\"}"; target="${target#\"}"
    target="${target%\'}"; target="${target#\'}"
    case "$target" in
        /dev/*|/proc/*|/sys/*) return 0 ;;   # not real files
        "~"/*) target="$HOME/${target#\~/}" ;;
    esac
    [ ! -f "$target" ] && return 0           # new file, nothing to lose
    [ -L "$target" ] && return 0             # don't follow symlinks
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    local stamp safe
    stamp=$(date +%Y%m%d-%H%M%S)
    safe=$(printf '%s' "$target" | tr '/' '_' | sed 's/^_//')
    # `--` matters: an extracted path starting with "-" would otherwise be
    # read by cp as an option (e.g. a file literally named "-r").
    cp -- "$target" "${BACKUP_DIR}/${safe}.${stamp}" 2>/dev/null
}

if [ "$TOOL" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$COMMAND" ] && exit 0

    # 1. Redirection: > file and >> file.
    #    The [^&] guard keeps ">&2" and "2>&1" from being read as filenames.
    while read -r hit; do
        [ -n "$hit" ] && backup_one "$hit"
    done < <(printf '%s' "$COMMAND" \
        | grep -oE '>>?[[:space:]]*[^&|;[:space:]]+' \
        | sed -E 's/^>>?[[:space:]]*//')

    # 2. tee (with or without -a) — the operand is a destination
    while read -r hit; do
        [ -n "$hit" ] && backup_one "$hit"
    done < <(printf '%s' "$COMMAND" \
        | grep -oE '\btee[[:space:]]+(-a[[:space:]]+)?[^|;&[:space:]]+' \
        | sed -E 's/^tee[[:space:]]+(-a[[:space:]]+)?//')

    # 3. mv — the destination is overwritten silently when it already exists
    while read -r hit; do
        [ -n "$hit" ] && backup_one "$hit"
    done < <(printf '%s' "$COMMAND" \
        | grep -oE '\bmv[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^|;&[:space:]]+[[:space:]]+[^|;&[:space:]]+' \
        | awk '{print $NF}')
else
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    backup_one "$FILE"
fi

# Clean old backups (>7 days)
[ -d "$BACKUP_DIR" ] && find "$BACKUP_DIR" -type f -mtime +7 -delete 2>/dev/null

exit 0
