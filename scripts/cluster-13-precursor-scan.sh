#!/bin/bash
# ================================================================
# cluster-13-precursor-scan.sh — Standalone scanner for the Cluster 13A
#   extended-thinking wedge precursor (thinking: "" + non-empty signature)
#   across every Claude Code transcript in your project tree.
# ================================================================
#
# PURPOSE:
#   Cluster 13 (Extended-Thinking Session Wedging) wedges sessions when
#   the transcript persists thinking blocks with `thinking: ""` + retained
#   `signature` — on next resume the API returns 400 and the session is
#   permanently broken. PR #469's loop-guard hook BLOCKS resume per-session;
#   this script gives you the fleet-wide view: which sessions on disk
#   carry the precursor, how many blocks each carries, which ones are at
#   highest risk under /loop or autonomous resume.
#
#   For operators running headless agent fleets, scheduled jobs, or any
#   pipeline that resumes sessions programmatically, this scan answers
#   "which of my saved sessions will brick on the next resume."
#
# UPSTREAM REFERENCES:
#   #63147 (canonical case, 33 reactions, @jdrolls root cause analysis)
#   PR #445 (extended-thinking-resume-warning.sh, per-session advisory)
#   PR #469 (extended-thinking-loop-guard.sh, per-session BLOCK)
#   PR #470 (cluster-13-extended-thinking-wedge-diagnostic.html, 5Q widget)
#   Field guide: https://gist.github.com/yurukusa/8c6be069f602399238356a9c9b719a45
#
# USAGE:
#   bash scripts/cluster-13-precursor-scan.sh                # scan default ~/.claude/projects/
#   bash scripts/cluster-13-precursor-scan.sh /path/to/dir   # scan custom dir
#   bash scripts/cluster-13-precursor-scan.sh --json         # machine-readable JSON output
#   bash scripts/cluster-13-precursor-scan.sh --top 10       # show top 10 highest-risk files
#   bash scripts/cluster-13-precursor-scan.sh --recovery     # print JSONL-strip recovery jq command per file
#   bash scripts/cluster-13-precursor-scan.sh --threshold 50 # only flag files with ≥50 precursor blocks
#   bash scripts/cluster-13-precursor-scan.sh --quiet        # exit code only, no output
#
# BEHAVIOR:
#   - Walks the transcript directory tree.
#   - For each .jsonl, counts assistant content blocks where
#     `type == "thinking"` AND `thinking == ""` AND `signature` is non-empty.
#   - Default sort: descending by precursor count.
#   - Prints a per-file summary, then a total, then risk-band breakdown
#     (low / med / high / critical) keyed to PR #469 thresholds.
#   - Exit codes:
#       0 — scan completed (regardless of findings)
#       2 — at least one transcript has precursor count ≥ THRESHOLD
#       3 — usage error (bad flag, missing directory)
#   - Read-only. Does not modify any transcript. Recovery commands are
#     printed for the operator to run manually after backup.
#
# CONFIGURATION (env vars):
#   CC_CLUSTER13_SCAN_DIR        Default scan directory
#                                (default: ~/.claude/projects/)
#   CC_CLUSTER13_SCAN_THRESHOLD  Threshold for exit code 2 + risk band
#                                (default: 1 — any precursor triggers)
#   CC_CLUSTER13_SCAN_TOP        Default number of top-risk files shown
#                                (default: 20)
#
# REQUIREMENTS:
#   jq (already used by cc-safe-setup hooks); bash 4+; standard POSIX tools.
#   Tested on Linux (Ubuntu, Fedora), macOS, WSL2.
#
# WHY READ-ONLY:
#   Cluster 13's recovery requires JSONL editing that's not safe to
#   automate without operator review — the in-place strip needs to leave
#   uuid/parentUuid chains intact and the right placeholder format. This
#   tool surfaces the situation; the operator runs the recovery.
#
# ================================================================

set -uo pipefail

# ---- Argument parsing ----

SCAN_DIR="${CC_CLUSTER13_SCAN_DIR:-$HOME/.claude/projects}"
THRESHOLD="${CC_CLUSTER13_SCAN_THRESHOLD:-1}"
TOP_N="${CC_CLUSTER13_SCAN_TOP:-20}"
OUTPUT_JSON=0
SHOW_RECOVERY=0
QUIET=0
CUSTOM_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json) OUTPUT_JSON=1; shift ;;
        --top) TOP_N="$2"; shift 2 ;;
        --threshold) THRESHOLD="$2"; shift 2 ;;
        --recovery) SHOW_RECOVERY=1; shift ;;
        --quiet) QUIET=1; shift ;;
        --help|-h)
            cat <<EOF
cluster-13-precursor-scan.sh — Scan transcripts for the Cluster 13A wedge precursor.

Usage:
  $0 [DIR] [flags]

Flags:
  --json              Machine-readable JSON output (one record per file with precursor).
  --top N             Show top N highest-risk files (default $TOP_N).
  --threshold N       Flag (exit 2) when any file has ≥N precursor blocks (default $THRESHOLD).
  --recovery          Print JSONL-strip recovery jq command per flagged file.
  --quiet             Exit code only, no stdout.
  --help              This message.

Env vars: CC_CLUSTER13_SCAN_DIR, CC_CLUSTER13_SCAN_THRESHOLD, CC_CLUSTER13_SCAN_TOP

Reference: https://gist.github.com/yurukusa/8c6be069f602399238356a9c9b719a45
EOF
            exit 0
            ;;
        -*)
            echo "Unknown flag: $1" >&2
            echo "Run with --help for usage." >&2
            exit 3
            ;;
        *)
            if [ -z "$CUSTOM_DIR" ]; then
                CUSTOM_DIR="$1"
                shift
            else
                echo "Unexpected positional argument: $1" >&2
                exit 3
            fi
            ;;
    esac
done

[ -n "$CUSTOM_DIR" ] && SCAN_DIR="$CUSTOM_DIR"

if [ ! -d "$SCAN_DIR" ]; then
    [ "$QUIET" -eq 0 ] && echo "Scan directory not found: $SCAN_DIR" >&2
    exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
    [ "$QUIET" -eq 0 ] && echo "jq is required but not installed." >&2
    exit 3
fi

# ---- Scan ----

# tmpfile holds per-file results so we can sort/format them later.
TMPFILE=$(mktemp -t cluster-13-scan.XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

TOTAL_FILES=0
PRECURSOR_FILES=0
TOTAL_PRECURSOR_BLOCKS=0
SCAN_START_TIME=$(date -u +%FT%TZ)

# Find all jsonl files. Use process substitution to keep counter
# updates in the current shell.
while IFS= read -r f; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    # Count empty-thinking + non-empty-signature blocks.
    # fromjson? tolerates malformed lines.
    COUNT=$(jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "thinking" and ((.thinking // "") | length) == 0 and ((.signature // "") | length) > 0) | (.signature | length)' "$f" 2>/dev/null | wc -l)
    if [ "$COUNT" -gt 0 ]; then
        PRECURSOR_FILES=$((PRECURSOR_FILES + 1))
        TOTAL_PRECURSOR_BLOCKS=$((TOTAL_PRECURSOR_BLOCKS + COUNT))
        # Compute file size in KB and last-modified time for context.
        SIZE_KB=$(du -k "$f" 2>/dev/null | awk '{print $1}')
        MTIME=$(date -r "$f" -u +%FT%TZ 2>/dev/null || echo "?")
        printf '%d\t%s\t%s\t%s\n' "$COUNT" "$f" "${SIZE_KB:-?}" "$MTIME" >> "$TMPFILE"
    fi
done < <(find "$SCAN_DIR" -type f -name '*.jsonl' 2>/dev/null)

# ---- Output ----

# JSON output mode.
if [ "$OUTPUT_JSON" -eq 1 ]; then
    {
        echo '{'
        echo '  "scan_start": "'"$SCAN_START_TIME"'",'
        echo '  "scan_dir": "'"$SCAN_DIR"'",'
        echo '  "threshold": '"$THRESHOLD"','
        echo '  "total_files": '"$TOTAL_FILES"','
        echo '  "precursor_files": '"$PRECURSOR_FILES"','
        echo '  "total_precursor_blocks": '"$TOTAL_PRECURSOR_BLOCKS"','
        echo '  "files": ['
        FIRST=1
        sort -nr "$TMPFILE" | head -n "$TOP_N" | while IFS=$'\t' read -r count path size_kb mtime; do
            [ "$FIRST" -eq 1 ] && FIRST=0 || echo '    ,'
            printf '    {"path": "%s", "precursor_count": %s, "size_kb": "%s", "mtime": "%s"}\n' "$path" "$count" "$size_kb" "$mtime"
        done
        echo '  ]'
        echo '}'
    }
    # Decide exit code from threshold.
    if [ "$PRECURSOR_FILES" -gt 0 ]; then
        MAX=$(sort -nr "$TMPFILE" | head -1 | awk '{print $1}')
        [ "$MAX" -ge "$THRESHOLD" ] && exit 2
    fi
    exit 0
fi

# Quiet mode — exit code only.
if [ "$QUIET" -eq 1 ]; then
    if [ "$PRECURSOR_FILES" -gt 0 ]; then
        MAX=$(sort -nr "$TMPFILE" | head -1 | awk '{print $1}')
        [ "$MAX" -ge "$THRESHOLD" ] && exit 2
    fi
    exit 0
fi

# Human output.
cat <<EOF
Cluster 13A precursor scan
==========================
scan dir:      $SCAN_DIR
threshold:     $THRESHOLD precursor block(s) per file → flag
files scanned: $TOTAL_FILES
files w/ precursor: $PRECURSOR_FILES
total precursor blocks: $TOTAL_PRECURSOR_BLOCKS

EOF

if [ "$PRECURSOR_FILES" -eq 0 ]; then
    echo "No precursor found. None of the scanned transcripts carry the Cluster 13A shape."
    echo ""
    echo "Note: precursor is the on-disk shape that *can* fire the 400 on resume."
    echo "Healthy sessions can also persist thinking blocks empty-but-signed —"
    echo "the precursor is the necessary condition, not the sufficient one."
    exit 0
fi

# Risk-band breakdown.
HIGH_COUNT=0
MED_COUNT=0
LOW_COUNT=0
while IFS=$'\t' read -r count path size_kb mtime; do
    if [ "$count" -ge 100 ]; then
        HIGH_COUNT=$((HIGH_COUNT + 1))
    elif [ "$count" -ge 10 ]; then
        MED_COUNT=$((MED_COUNT + 1))
    else
        LOW_COUNT=$((LOW_COUNT + 1))
    fi
done < "$TMPFILE"

cat <<EOF
Risk band breakdown
-------------------
  critical (≥100 blocks): $HIGH_COUNT files
  warning  ( 10–99 blocks): $MED_COUNT files
  watch    (  1–9  blocks): $LOW_COUNT files

Top $TOP_N highest-risk files
EOF
printf -- '------------------------\n'

# Per-file detail.
sort -nr "$TMPFILE" | head -n "$TOP_N" | while IFS=$'\t' read -r count path size_kb mtime; do
    # Trim project slug from absolute path for readability.
    DISPLAY_PATH=$(echo "$path" | sed -E "s|^$HOME/\.claude/projects/||")
    printf '%6d blocks · %5s KB · %s\n         %s\n' "$count" "$size_kb" "$mtime" "$DISPLAY_PATH"
    if [ "$SHOW_RECOVERY" -eq 1 ]; then
        cat <<EOF
         Recovery (backup first, then run):
           cp '$path' '$path.bak'
           jq -c 'if .type == "assistant" then (.message.content |= map(if .type == "thinking" or .type == "redacted_thinking" then null else . end | values)) else . end' '$path.bak' > '$path'
         If the strip leaves any assistant message with empty content array,
         replace those with: {"type":"text","text":"[thinking]"} placeholder
         to keep arrays non-empty per @beemusicco's workaround in #63147.
EOF
    fi
done

cat <<EOF

Recommended actions
-------------------
  For each flagged session, before next resume:
    1. Stop any autonomous loop / scheduled job that would resume it.
    2. Decide: preserve context (JSONL strip) OR accept context loss (start fresh).
    3. If preserving: run the recovery command (with --recovery flag above) per file.
    4. If discarding: just delete the .jsonl OR /clear from inside.

  For preventing recurrence:
    - Install PR #469 loop-guard hook with CC_LOOP_GUARD_ENABLED=1
    - Or set CLAUDE_CODE_DISABLE_THINKING=1 / MAX_THINKING_TOKENS=0
      (per @cnighswonger's 2.1.148 binary disassembly, only these
       actually stop generation — DISABLE_INTERLEAVED_THINKING=1 does NOT)

References
----------
  Field guide: https://gist.github.com/yurukusa/8c6be069f602399238356a9c9b719a45
  Interactive 5Q diagnostic: https://yurukusa.github.io/cc-safe-setup/cluster-13-extended-thinking-wedge-diagnostic.html
  Loop-guard hook (PR #469): https://github.com/yurukusa/cc-safe-setup/pull/469
  Central case (#63147): https://github.com/anthropics/claude-code/issues/63147
EOF

# Threshold-based exit code.
MAX=$(sort -nr "$TMPFILE" | head -1 | awk '{print $1}')
[ "$MAX" -ge "$THRESHOLD" ] && exit 2
exit 0
