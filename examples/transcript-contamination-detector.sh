#!/bin/bash
# transcript-contamination-detector.sh — Detect synthetic entries injected
# into session transcript .jsonl files by the /resume contamination bug.
#
# Solves: #60802 — "/resume renders an unselected session's transcript and
# injects synthetic messages into its .jsonl (v2.1.139, Windows PowerShell)"
#
# In that case, /resume on Windows v2.1.139 contaminated *unselected* session
# .jsonl logs with two synthetic entries:
#
#   - user message: { isMeta: true, content: "Continue from where you left off." }
#   - assistant message: { model: "<synthetic>", content: "No response requested." }
#
# These entries appear in the .jsonl file of a session the user did NOT
# resume. The contaminated session's log no longer faithfully records what
# happened — a later audit would see message exchanges that never occurred.
#
# Related: #46603 (parentUuid chain breakage after compaction; different
# mechanism but same structural family — transcript log losing fidelity to
# the actual conversation).
#
# This hook runs on SessionStart and scans the user's per-project .jsonl
# logs for the synthetic markers. If any are found, it surfaces the count
# and file paths so the operator can decide whether to restore from backup
# or annotate the log.
#
# The hook does NOT block session start (exit 0 even when contamination is
# detected) because session-start blocking is too disruptive for a
# detection-only signal. It does emit a system-reminder for Claude to see.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_PROJECTS_DIR                 default ~/.claude/projects
#   CC_TRANSCRIPT_DETECTOR_DISABLE  set to "1" to skip
#   CC_TRANSCRIPT_DETECTOR_MAX      max .jsonl files to scan (default 200)
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "SessionStart": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/transcript-contamination-detector.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_TRANSCRIPT_DETECTOR_DISABLE:-0}" = "1" ] && exit 0

PROJECTS_DIR="${CC_PROJECTS_DIR:-$HOME/.claude/projects}"
MAX_FILES="${CC_TRANSCRIPT_DETECTOR_MAX:-200}"

# If no projects directory, nothing to scan.
[ ! -d "$PROJECTS_DIR" ] && exit 0

# The two synthetic markers from #60802. Match conservatively — require both
# the isMeta:true + the specific synthetic-model marker patterns.
USER_MARKER='"isMeta"[[:space:]]*:[[:space:]]*true.*Continue from where you left off'
ASSISTANT_MARKER='"model"[[:space:]]*:[[:space:]]*"<synthetic>".*No response requested'

# Collect .jsonl files, capped at MAX_FILES, most-recently-modified first.
mapfile -t FILES < <(
    find "$PROJECTS_DIR" -maxdepth 3 -type f -name '*.jsonl' \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn \
        | head -n "$MAX_FILES" \
        | awk '{ $1=""; sub(/^ /, ""); print }'
)

[ "${#FILES[@]}" -eq 0 ] && exit 0

CONTAMINATED=()
for f in "${FILES[@]}"; do
    # Both markers must be present on at least one line each (they don't
    # need to be on the same line — they're separate messages).
    if grep -Eq "$USER_MARKER" "$f" 2>/dev/null && grep -Eq "$ASSISTANT_MARKER" "$f" 2>/dev/null; then
        CONTAMINATED+=("$f")
    fi
done

[ "${#CONTAMINATED[@]}" -eq 0 ] && exit 0

# Contamination found. Build a feedback message for Claude.
# Limit output to first 5 paths to avoid wall-of-text.
SHOWN=()
for ((i = 0; i < ${#CONTAMINATED[@]} && i < 5; i++)); do
    SHOWN+=("${CONTAMINATED[$i]}")
done
EXTRA=$(( ${#CONTAMINATED[@]} - ${#SHOWN[@]} ))

cat >&2 <<EOF
<system-reminder>
TRANSCRIPT CONTAMINATION DETECTED — ${#CONTAMINATED[@]} session .jsonl file(s)
contain the synthetic-entry markers introduced by the /resume bug
documented in anthropics/claude-code#60802 (v2.1.139, originally Windows
PowerShell — may affect other platforms / versions).

Markers found (both must be present in a single .jsonl for it to be flagged):
  - user message with "isMeta": true + content "Continue from where you left off."
  - assistant message with "model": "<synthetic>" + content "No response requested."

These entries are NOT real conversation. They were injected when /resume was
invoked on a *different* session. The log of the affected file no longer
faithfully records what actually happened in that session.

Affected files (first 5):
EOF
for f in "${SHOWN[@]}"; do
    echo "  $f" >&2
done
if [ "$EXTRA" -gt 0 ]; then
    echo "  ... and $EXTRA more" >&2
fi
cat >&2 <<EOF

Recommended next actions for the operator (NOT for the model to perform
automatically):
  1. If an offline backup of the session .jsonl exists from before the
     /resume incident, restore the affected file from backup.
  2. Otherwise, append an editorial note to the affected session
     documenting that the synthetic entries were injected by the harness,
     not authored by the operator or the model.
  3. Avoid using /resume on multi-session projects on the affected version
     until the upstream fix lands. Workaround: open the desired session
     directly via the .jsonl path argument rather than the picker.

To disable this detector, set CC_TRANSCRIPT_DETECTOR_DISABLE=1.
</system-reminder>
EOF

# Exit 0 — detection-only, don't block session start.
exit 0
