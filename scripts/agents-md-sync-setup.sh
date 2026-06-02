#!/bin/bash
# ================================================================
# agents-md-sync-setup.sh — Safely set up CLAUDE.md <-> AGENTS.md
#   sync so a single edit keeps both in step. Solves the #6235 pain
#   at the source instead of only warning about drift.
# ================================================================
# PURPOSE:
#   anthropics/claude-code#6235 (5,268 reactions, 13+ months open,
#   the single largest feature request in the Claude Code tracker)
#   asks Claude Code to read AGENTS.md as a fallback to CLAUDE.md.
#   Codex, Cursor, Amp, Aider and others converge on AGENTS.md;
#   Claude Code reads CLAUDE.md. Operators end up hand-syncing two
#   files, and they drift.
#
#   cc-safe-setup already ships two DETECTION hooks:
#     - agents-md-sync-checker.sh   (SessionStart: reports drift)
#     - agents-md-edit-drift-warner.sh (PostToolUse: warns at edit)
#   Both tell you that the files are out of sync. Neither sets up
#   the sync. This script closes that gap: it inspects the current
#   state and performs the one safe action that removes future
#   drift — replacing one file with a relative symlink to the other,
#   so other agents read AGENTS.md, Claude Code reads CLAUDE.md, and
#   one edit updates both.
#
#   Hooks cannot do this safely (they fire mid-session and must not
#   mutate the repo), so this is a standalone, operator-run script.
#
# UPSTREAM REFERENCES:
#   #6235 (read AGENTS.md as a fallback to CLAUDE.md)
#
# USAGE:
#   bash scripts/agents-md-sync-setup.sh            # dry-run: print the plan only
#   bash scripts/agents-md-sync-setup.sh --apply    # perform the plan (with backups)
#   bash scripts/agents-md-sync-setup.sh --help
#
# SAFETY (this is a safety toolkit — it never loses your content):
#   - Dry-run is the DEFAULT. Nothing is modified without --apply.
#   - Before replacing any real file with a symlink, the original is
#     moved to <file>.bak-<timestamp> (never deleted, never rm'd).
#   - If both files exist with DIFFERENT content, the script REFUSES
#     to modify anything and prints how to reconcile. It never merges
#     or overwrites differing instructions.
#   - On filesystems without symlink support (e.g. some Windows
#     setups), set CC_AGENTS_SYNC_MODE=copy to use a one-way copy plus
#     a printed git pre-commit reminder instead of a symlink.
#
# CONFIGURATION (env vars):
#   CC_AGENTS_SYNC_DIR        Directory to operate in (default: cwd).
#   CC_AGENTS_SYNC_CANONICAL  Which file holds the real content and is
#                             the symlink target: "claude" (default) or
#                             "agents". The other becomes the symlink.
#   CC_AGENTS_SYNC_MODE       "symlink" (default) or "copy".
#   CC_AGENTS_SYNC_TIMESTAMP  Override the backup timestamp (tests).
# ================================================================

set -u

DIR="${CC_AGENTS_SYNC_DIR:-.}"
CANONICAL="${CC_AGENTS_SYNC_CANONICAL:-claude}"
MODE="${CC_AGENTS_SYNC_MODE:-symlink}"
APPLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        -h|--help)
            sed -n '2,57p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
    esac
done

CLAUDE="$DIR/CLAUDE.md"
AGENTS="$DIR/AGENTS.md"

# Decide which file is canonical (holds content) and which is the link.
if [ "$CANONICAL" = "agents" ]; then
    SRC="$AGENTS"; SRC_NAME="AGENTS.md"
    LINK="$CLAUDE"; LINK_NAME="CLAUDE.md"
else
    SRC="$CLAUDE"; SRC_NAME="CLAUDE.md"
    LINK="$AGENTS"; LINK_NAME="AGENTS.md"
fi

say()  { echo "$@"; }
plan() { if [ "$APPLY" -eq 1 ]; then echo "  APPLYING: $*"; else echo "  PLAN (dry-run): $*"; fi; }

# --- State 0: neither file exists ---
if [ ! -e "$CLAUDE" ] && [ ! -e "$AGENTS" ]; then
    say "No CLAUDE.md or AGENTS.md found in $DIR."
    say "Create your instructions in CLAUDE.md first, then re-run to mirror it to AGENTS.md."
    exit 0
fi

# --- State 1: already synced (same inode, i.e. one is a link to the other) ---
if [ -e "$CLAUDE" ] && [ -e "$AGENTS" ] && [ "$CLAUDE" -ef "$AGENTS" ]; then
    say "Already synced: CLAUDE.md and AGENTS.md resolve to the same file. Nothing to do."
    exit 0
fi

# --- State 5: both exist with DIFFERENT content -> refuse to modify ---
if [ -e "$CLAUDE" ] && [ -e "$AGENTS" ] && ! cmp -s "$CLAUDE" "$AGENTS"; then
    csize=$(wc -c < "$CLAUDE" 2>/dev/null | tr -d ' ')
    asize=$(wc -c < "$AGENTS" 2>/dev/null | tr -d ' ')
    say "CLAUDE.md ($csize bytes) and AGENTS.md ($asize bytes) exist with DIFFERENT content."
    say "Refusing to modify either file — that would lose one set of instructions."
    say ""
    say "Reconcile first, then re-run:"
    say "  1. Decide which file is correct (or merge them by hand into one)."
    say "  2. Make the other identical, or delete it."
    say "  3. Re-run this script to replace the duplicate with a symlink."
    say ""
    say "  diff CLAUDE.md AGENTS.md   # review the differences"
    exit 0
fi

# At this point either only one file exists, or both exist with identical content.
# In both cases the plan is: ensure SRC holds the content and LINK points to it.

# If only the LINK-named file exists (and SRC does not), flip roles so we keep the
# real file and create the missing one as the link — never discard existing content.
if [ ! -e "$SRC" ] && [ -e "$LINK" ]; then
    tmp="$SRC"; SRC="$LINK"; LINK="$tmp"
    tmp="$SRC_NAME"; SRC_NAME="$LINK_NAME"; LINK_NAME="$tmp"
fi

TS="${CC_AGENTS_SYNC_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

say "Source of truth: $SRC_NAME   ->   link: $LINK_NAME   (mode: $MODE)"

if [ "$MODE" = "copy" ]; then
    plan "copy $SRC_NAME to $LINK_NAME (one-way; symlinks unavailable)"
    if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
        plan "back up existing $LINK_NAME to $(basename "$LINK").bak-$TS"
    fi
    if [ "$APPLY" -eq 1 ]; then
        [ -e "$LINK" ] && [ ! -L "$LINK" ] && mv "$LINK" "$LINK.bak-$TS"
        cp "$SRC" "$LINK"
        say "Done. $LINK_NAME is now a COPY of $SRC_NAME."
        say "Copies drift. Add a git pre-commit hook that fails when they differ, or re-run after edits."
    fi
    exit 0
fi

# symlink mode
plan "replace $LINK_NAME with a relative symlink -> $SRC_NAME"
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
    plan "back up existing $LINK_NAME to $(basename "$LINK").bak-$TS"
fi
if [ "$APPLY" -eq 1 ]; then
    [ -e "$LINK" ] && [ ! -L "$LINK" ] && mv "$LINK" "$LINK.bak-$TS"
    [ -L "$LINK" ] && rm -f "$LINK"   # only removes an existing symlink, never a real file
    ( cd "$DIR" && ln -s "$(basename "$SRC")" "$(basename "$LINK")" )
    say "Done. $LINK_NAME -> $SRC_NAME. One edit to $SRC_NAME now updates both."
fi
exit 0
