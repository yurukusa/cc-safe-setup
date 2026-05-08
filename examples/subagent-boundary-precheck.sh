#!/bin/bash
# ================================================================
# subagent-boundary-precheck.sh — Warn when Task delegation lacks
#                                  explicit boundary statements
# ================================================================
# PURPOSE:
#   The May 2026 sub-agent cluster (#55488, #55653, #55660, #55666,
#   #55691) documented five axes where sub-agents acted outside
#   their intended boundary because the parent session never stated
#   the boundary explicitly: identity confusion (parent vs child),
#   tool-list inheritance, work-area ownership, settings.json
#   mutation, and permission escalation. Existing hooks address the
#   permission-escalation axis (subagent-permission-mode-guard);
#   axes 1–4 require the parent session to say "stay in this
#   directory, do not edit settings, work on this file pattern
#   only" before invoking the sub-agent.
#
#   This hook is a parent-side pre-flight: when Task is about to
#   be invoked, inspect the prompt parameter for explicit boundary
#   statements. If the prompt lacks any of the four boundary
#   declarations, emit a non-blocking warning so the operator can
#   either tighten the prompt or accept the looser invocation.
#
# TRIGGER: PreToolUse  MATCHER: "Task"
#
# CONFIG:
#   SUBAGENT_BOUNDARY_BLOCK=0   (0 = warn-only; set to 1 to block
#                                missing boundaries with exit 2)
#
# Born from: https://github.com/anthropics/claude-code/issues/55488
#   plus #55653 #55660 #55666 #55691
#   (May 1–3 2026 cluster — five axes of sub-agent boundary absence)
# ================================================================

set -euo pipefail

BLOCK_MODE="${SUBAGENT_BOUNDARY_BLOCK:-0}"

# Read JSON input from stdin
INPUT=$(cat)

# Only act when the tool is Task
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "Task" ] || exit 0

# Extract the sub-agent prompt
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Check for each of the four boundary declarations.
# Detection is keyword-based against the prompt text — operators
# state boundaries in many forms; the patterns below cover the
# most common phrasings. Intentionally permissive to avoid false
# positives: any reasonable phrasing of the boundary counts.

MISSING_AXES=""

# Axis 1: working directory / work area declaration
# Phrases like "work directory", "in <path>/<name>", "scope:", "stay in"
if ! printf '%s' "$PROMPT" | grep -qiE \
  '(work(ing)?[[:space:]]+(area|directory|dir|in)|stay[[:space:]]+in|scope[[:space:]]*[:=]|(under|in)[[:space:]]+\.?/|inside[[:space:]]+the[[:space:]]+(directory|dir|folder))'; then
  MISSING_AXES="${MISSING_AXES}work_directory "
fi

# Axis 2: file pattern / allowlist declaration
# Phrases like "files matching", "only edit", "allowlist", "*.md", path patterns
if ! printf '%s' "$PROMPT" | grep -qiE \
  '(file[s]?[[:space:]]+(matching|under|in)|allowlist|only[[:space:]]+(edit|read|modify|touch)|file[[:space:]]+pattern|glob|extension[s]?:|\*\.[a-z])'; then
  MISSING_AXES="${MISSING_AXES}file_pattern "
fi

# Axis 3: settings.json prohibition
# Phrases like "do not edit settings", "do not modify settings", "no settings"
if ! printf '%s' "$PROMPT" | grep -qiE \
  '(do[[:space:]]+not[[:space:]]+(edit|modify|change|touch)[[:space:]]+(parent[[:space:]]+)?settings|no[[:space:]]+settings\.json|settings\.json[[:space:]]+(off-limits|forbidden|excluded)|leave[[:space:]]+settings[[:space:]]+alone)'; then
  MISSING_AXES="${MISSING_AXES}settings_prohibition "
fi

# Axis 4: identity / role declaration (so child knows it is a child)
# Phrases like "you are a sub-agent", "report back", "as a delegated agent",
# "do not act as the parent", "report your findings"
if ! printf '%s' "$PROMPT" | grep -qiE \
  '(sub-?agent|delegated|report[[:space:]]+(back|your)|return[[:space:]]+(your[[:space:]]+)?(findings|results|output)|investigation[[:space:]]+only|read-?only[[:space:]]+investigation|do[[:space:]]+not[[:space:]]+act[[:space:]]+as)'; then
  MISSING_AXES="${MISSING_AXES}identity_role "
fi

# If all four axes are present, the prompt is well-formed; exit silently
[ -z "$MISSING_AXES" ] && exit 0

# Trim trailing space
MISSING_AXES="${MISSING_AXES% }"
MISSING_COUNT=$(echo "$MISSING_AXES" | wc -w | tr -d ' ')

# Block path: if BLOCK_MODE=1 and any axis is missing, exit 2
if [ "$BLOCK_MODE" = "1" ] && [ "$MISSING_COUNT" -gt 0 ]; then
  echo "BLOCKED: subagent-boundary-precheck: ${MISSING_COUNT} of 4 boundary axes missing in Task prompt: ${MISSING_AXES}" >&2
  echo "  May 2026 cluster mitigation (#55488 #55653 #55660 #55666 #55691): state each boundary explicitly before delegation." >&2
  echo "  Required boundary declarations:" >&2
  echo "    work_directory     — name the directory the sub-agent should stay in" >&2
  echo "    file_pattern       — name the file extensions or glob the sub-agent may touch" >&2
  echo "    settings_prohibition — explicitly tell the sub-agent not to edit parent settings.json" >&2
  echo "    identity_role      — name the sub-agent as a sub-agent, not as the parent" >&2
  echo "  To proceed without these declarations: export SUBAGENT_BOUNDARY_BLOCK=0 (warn-only mode)." >&2
  exit 2
fi

# Warn path: emit warning, allow the Task to proceed
if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "WARNING: subagent-boundary-precheck: ${MISSING_COUNT} of 4 boundary axes missing in Task prompt: ${MISSING_AXES}" >&2
  echo "  May 2026 cluster (#55488 #55653 #55660 #55666 #55691): sub-agents acted outside intended boundary because parent did not state the boundary." >&2
  echo "  To prevent: add explicit declarations for the missing axes to the Task prompt before delegation." >&2
fi

exit 0
