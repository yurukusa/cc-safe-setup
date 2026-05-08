#!/bin/bash
# ================================================================
# windows-destructive-command-guard.sh — Block Windows-side
#                                          destructive command
#                                          escalation chains
# ================================================================
# PURPOSE:
#   The May 2026 Issue #56603 documented a catastrophic data-loss
#   incident: Claude Opus 4.7 escalated through five increasingly
#   destructive commands during routine git worktree cleanup,
#   ending at `cmd /c "rd /s /q \"<unicode-and-space-path>\""`
#   invoked from the PowerShell tool. The PowerShell-cmd-shell
#   quoting interaction parsed the argument differently than
#   intended; rd /s /q traversed the entire D: drive root and
#   silently deleted all unlocked files. SSD TRIM made the loss
#   irreversible — professional data recovery confirmed
#   unrecoverable.
#
#   The cc-safe-setup hook collection has rm-rf coverage on the
#   POSIX side but no equivalent for the Windows command surface.
#   This hook closes that gap: it inspects Bash-tool commands for
#   Windows-side destructive command shapes and blocks the chain
#   before the dangerous step executes.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIG:
#   WINDOWS_DESTRUCTIVE_BLOCK=1   (1 = block, 0 = warn-only)
#
# Born from: https://github.com/anthropics/claude-code/issues/56603
#   (May 6 2026 — Opus 4.7 cmd /c rd /s /q catastrophic data loss
#    via PowerShell quoting interaction on Unicode/space path)
# ================================================================

set -euo pipefail

BLOCK_MODE="${WINDOWS_DESTRUCTIVE_BLOCK:-1}"

# Read JSON input from stdin
INPUT=$(cat)

# Only act when the tool is Bash
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

# Extract the Bash command
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Detect Windows-side destructive command shapes.
# We look for the dangerous primitive AND for the contextual
# signals (drive-root target, recursive force flags, suppressed
# confirmation) that distinguish a routine cleanup from a
# whole-drive sweep.

DETECTED_PATTERNS=""

# Pattern 1: rd /s /q (or RD /S /Q, or rmdir /s /q) — recursive
# directory removal with force-quiet. Combined with /q, no
# confirmation prompt. The #56603 incident's terminal command.
if printf '%s' "$CMD" | grep -qiE '\b(rd|rmdir)\b[[:space:]]+(/[a-z][[:space:]]+){1,3}'; then
  if printf '%s' "$CMD" | grep -qiE '\b(rd|rmdir)\b[[:space:]]+(/s|/q)'; then
    DETECTED_PATTERNS="${DETECTED_PATTERNS}rd_recursive_quiet "
  fi
fi

# Pattern 2: cmd /c invocation — the shell-jump that produced the
# quoting interaction in #56603. Combined with rd/rmdir, this is
# the highest-risk shape because the second-level cmd parser may
# split the argument differently than the PowerShell first-level.
if printf '%s' "$CMD" | grep -qiE '\bcmd\b[[:space:]]+/c[[:space:]]+'; then
  if printf '%s' "$CMD" | grep -qiE '(rd|rmdir|del|erase)'; then
    DETECTED_PATTERNS="${DETECTED_PATTERNS}cmd_c_destructive "
  fi
fi

# Pattern 3: Remove-Item -Recurse -Force — PowerShell's recursive
# force removal. Step 4 in the #56603 escalation chain.
if printf '%s' "$CMD" | grep -qiE 'Remove-Item\b'; then
  if printf '%s' "$CMD" | grep -qiE '\-Recurse\b'; then
    if printf '%s' "$CMD" | grep -qiE '\-Force\b'; then
      DETECTED_PATTERNS="${DETECTED_PATTERNS}remove_item_recurse_force "
    fi
  fi
fi

# Pattern 4: del /s /q or erase /s /q — recursive file deletion.
if printf '%s' "$CMD" | grep -qiE '\b(del|erase)\b[[:space:]]+(/[a-z][[:space:]]+){1,3}'; then
  if printf '%s' "$CMD" | grep -qiE '\b(del|erase)\b[[:space:]]+(/s|/q)'; then
    DETECTED_PATTERNS="${DETECTED_PATTERNS}del_recursive_quiet "
  fi
fi

# Pattern 5: Format-Volume / Clear-Disk / Remove-PartitionAccessPath
# — disk-level destructive PowerShell cmdlets.
if printf '%s' "$CMD" | grep -qiE '(Format-Volume|Clear-Disk|Remove-Partition)\b'; then
  DETECTED_PATTERNS="${DETECTED_PATTERNS}disk_level_destructive "
fi

# If no destructive pattern detected, exit silently
[ -z "$DETECTED_PATTERNS" ] && exit 0
DETECTED_PATTERNS="${DETECTED_PATTERNS% }"

# Risk-elevating context signals — drive-root targets, escape-prone paths
RISK_NOTES=""

# Drive-root signal: target looks like "D:\" alone, "C:\" alone,
# or a path shorter than 6 characters after the colon. These are
# the highest-risk targets because a parsing error truncating to
# the drive root sweeps the whole drive.
if printf '%s' "$CMD" | grep -qiE '[A-Z]:\\?(\s|"|$)'; then
  RISK_NOTES="${RISK_NOTES}drive_root_target "
fi

# Unicode/space path signal: target contains escaped spaces or
# non-ASCII characters within quotes. The #56603 quoting
# interaction surfaced specifically on Unicode-and-space paths.
if printf '%s' "$CMD" | grep -qE '\\"|"[^"]*[[:space:]]'; then
  if printf '%s' "$CMD" | grep -qE '"[^"]*[^[:print:]]'; then
    RISK_NOTES="${RISK_NOTES}unicode_in_quoted_path "
  elif printf '%s' "$CMD" | grep -qE '"[^"]*[[:space:]]'; then
    RISK_NOTES="${RISK_NOTES}space_in_quoted_path "
  fi
fi

# Block path: emit the blocking message
if [ "$BLOCK_MODE" = "1" ]; then
  echo "BLOCKED: windows-destructive-command-guard: detected destructive Windows-side command pattern(s): ${DETECTED_PATTERNS}" >&2
  if [ -n "$RISK_NOTES" ]; then
    echo "  Risk-elevating context: ${RISK_NOTES% }" >&2
  fi
  echo "  May 2026 Issue #56603 cluster mitigation: Opus 4.7's escalation chain on Windows ended at cmd /c rd /s /q with quoting interaction sweeping the entire D: drive (SSD TRIM made loss irreversible)." >&2
  echo "  Safer alternatives:" >&2
  echo "    - For locked git worktrees: stop and tell the operator the lock blocker (VS Code, etc.) before escalating force flags." >&2
  echo "    - For path-quoting on Windows: avoid cmd /c from PowerShell; use Remove-Item with -LiteralPath and explicit -ErrorAction Stop." >&2
  echo "    - For specific files: list them by absolute path, do not rely on recursive sweeps." >&2
  echo "  To bypass for legitimate cleanup: export WINDOWS_DESTRUCTIVE_BLOCK=0 (warn-only mode)." >&2
  exit 2
fi

# Warn path
echo "WARNING: windows-destructive-command-guard: detected destructive Windows-side command pattern(s): ${DETECTED_PATTERNS}" >&2
if [ -n "$RISK_NOTES" ]; then
  echo "  Risk-elevating context: ${RISK_NOTES% }" >&2
fi
echo "  May 2026 Issue #56603: this command shape produced catastrophic data loss when a quoting interaction swept a whole drive. Verify the target path is bounded before proceeding." >&2

exit 0
