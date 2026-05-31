#!/bin/bash
# bg-permission-prompt-warner.sh — Warn operators dispatching `claude --bg` that
# background sessions stall on permission prompts even under acceptEdits
# (Cluster 24 candidate, axis 24A — non-interactive permission gap)
#
# Background:
#   Cluster 24 candidate axis 24A documents that `claude --bg` code-writing
#   sessions stall on permission prompts even when invoked with
#   `--permission-mode acceptEdits`. There is no non-interactive way to
#   answer the prompt from the shell, so unattended automation that depends
#   on `--bg` for fan-out blocks indefinitely on the first edit-permission
#   gate.
#
#   Anchor case:
#     #64271 — `claude --bg` code-writing sessions stall on permission
#              prompts with no non-interactive way to answer
#
#   The structural shape: the operator dispatches a background session
#   expecting it to run unattended, walks away, and returns to find the
#   session paused indefinitely on a permission prompt that no automation
#   layer can answer. The "background" framing implies the session can
#   run without supervision; the permission gate breaks that expectation.
#
#   Cluster 24 axes (4 sub-clusters):
#     24A — non-interactive permission gap (#64271, this hook)
#     24B — documentation gap: hook payload omits agent_id for bg sessions (#64272)
#     24C — resource-release gap: Windows daemon retains dir handle (#64273)
#     24D — result-delivery gap: iOS Dispatch / Advisor result not relayed
#           (#64242, #64244, #64250)
#
#   This hook is a SessionStart advisory that fires when:
#     - the parent process command line contains `--bg` or `--background`
#       (detected via /proc/$PPID/cmdline on Linux or `ps -o command` on
#       macOS), AND
#     - the operator has not already seen the advisory in this session
#
#   The advisory describes the four sub-cluster axes, names the operator-side
#   workaround for axis 24A (keep a terminal attached until the
#   non-interactive path lands), and links the field guide.
#
# When this hook does NOT emit anything:
#   - CC_BG_WARN_DISABLE=1
#   - CC_BG_WARN_QUIET=1
#   - the parent command line does not contain --bg / --background
#   - the parent command line cannot be read
#   - the advisory has already fired in this session
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/bg-permission-prompt-warner.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_BG_WARN_DISABLE=1            — never emit
#   CC_BG_WARN_QUIET=1              — silent (process but never write to stderr)
#   CC_BG_WARN_FORCE=1              — bypass parent-cmdline detection, always emit
#                                     (tests, or for operators who want the
#                                      advisory on every session-start)
#   CC_BG_WARN_PARENT_CMD=<cmd>     — parent command line override (tests)
#   CC_BG_WARN_STATE_DIR=<path>     — one-shot state dir override (default ~/.claude/state)
#   CC_BG_WARN_SESSION_ID=<id>      — session id override (tests)
#
# Design notes:
#   - Opt-out. Operators who use --bg regularly and have already absorbed
#     the limitation can disable. The default-on signal serves operators
#     who are about to be surprised by the permission gate.
#   - One-shot per session. The advisory fires once. Repeated firings
#     across sessions of long-running --bg pilots add no signal.
#   - Never blocks. Exit always 0. The advisory is informational.
#   - Parent detection is best-effort: /proc on Linux, ps on macOS,
#     fallback to env vars on platforms without either.

set -u

if [[ "${CC_BG_WARN_DISABLE:-0}" = "1" ]]; then
    exit 0
fi

STATE_DIR="${CC_BG_WARN_STATE_DIR:-$HOME/.claude/state}"
mkdir -p "$STATE_DIR" 2>/dev/null

SESSION_ID="${CC_BG_WARN_SESSION_ID:-${CLAUDE_SESSION_ID:-default}}"
GUARD_FILE="$STATE_DIR/bg-warn-${SESSION_ID}.fired"

if [[ -f "$GUARD_FILE" ]]; then
    exit 0
fi

# Detect parent command line. Order of attempts:
#   1) explicit override via env var (tests)
#   2) /proc/$PPID/cmdline (Linux)
#   3) ps -o command -p $PPID (macOS)
PARENT_CMD="${CC_BG_WARN_PARENT_CMD:-}"
if [[ -z "$PARENT_CMD" ]]; then
    if [[ -r "/proc/$PPID/cmdline" ]]; then
        # Replace NULs with spaces for grep
        PARENT_CMD=$(tr '\0' ' ' < "/proc/$PPID/cmdline" 2>/dev/null)
    elif command -v ps >/dev/null 2>&1; then
        PARENT_CMD=$(ps -o command= -p "$PPID" 2>/dev/null)
    fi
fi

# Decide whether to emit. CC_BG_WARN_FORCE bypasses parent-cmdline detection.
SHOULD_EMIT=0
if [[ "${CC_BG_WARN_FORCE:-0}" = "1" ]]; then
    SHOULD_EMIT=1
elif [[ -n "$PARENT_CMD" ]] && echo "$PARENT_CMD" | grep -qE -- '(--bg|--background)\b'; then
    SHOULD_EMIT=1
fi

if [[ "$SHOULD_EMIT" -ne 1 ]]; then
    exit 0
fi

# Mark one-shot guard.
touch "$GUARD_FILE" 2>/dev/null

if [[ "${CC_BG_WARN_QUIET:-0}" = "1" ]]; then
    exit 0
fi

cat >&2 <<EOF

────────────────────────────────────────────────────────────────────
  Background dispatch advisory — Cluster 24 axis 24A (--bg permission gap)
────────────────────────────────────────────────────────────────────
  Parent command line includes \`--bg\` / \`--background\`. This session
  appears to be running as a background-dispatched Claude Code session.

  The Cluster 24 axis 24A pattern: \`claude --bg\` code-writing sessions
  stall on permission prompts even under \`--permission-mode acceptEdits\`.
  There is no non-interactive way to answer the prompt from the shell,
  so unattended automation that depends on --bg blocks indefinitely on
  the first edit-permission gate.

  Anchor case: #64271.

  Recommended operator-side workaround until the non-interactive path
  lands upstream:

    1) Keep a terminal attached to the dispatcher process until the
       background session completes — the permission prompts surface
       there and can be answered manually.
    2) For long-running unattended automation, do not rely on --bg
       alone; combine with explicit non-interactive Bash invocations
       that bypass the edit-permission surface entirely.
    3) Audit your tool-call distribution. Tool calls that trigger
       edit-permission gates (Write, Edit, NotebookEdit) are the ones
       that stall; read-only tool calls (Read, Glob, Bash with safe
       commands) do not.

  Three sibling axes also documented in Cluster 24 candidate:

    24B — \`hooks.md\` does not articulate that background-dispatched
          sessions are top-level processes, so hook payloads omit
          \`agent_id\` (#64272). Use \`session_id\` as the primary
          correlator instead.

    24C — On Windows, the background daemon retains directory handles
          after \`claude rm\` (#64273). Sleep briefly or restart the
          per-user node daemon before retrying directory deletion.

    24D — Dispatch / iOS Dispatch / Advisor result-delivery surface
          signals "completed" but the result never reaches the
          orchestrator context (#64242, #64244, #64250). Verify with
          an explicit completion-marker check rather than trusting
          the UI signal.

  Field guide: cluster-tracker.html on GitHub Pages, search "Cluster 24".

  (This advisory fires once per session. To disable:
   export CC_BG_WARN_DISABLE=1)
────────────────────────────────────────────────────────────────────

EOF

exit 0
