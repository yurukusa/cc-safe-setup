#!/bin/bash
# ================================================================
# binary-read-detector.sh — Surface image / PDF / binary path
# references in user prompts before they reach the vision dispatch
# bus that bypasses PreToolUse hooks
# ================================================================
# PURPOSE:
#   Issue #62639 documented that PreToolUse hooks do not fire when
#   the Read tool reads image, PDF, or other binary files. The
#   model receives the content via a vision-routing dispatch path
#   that bypasses the hook bus entirely. Three related places
#   exhibit the same gap:
#
#     1. Read on .png / .jpg / .webp / .gif / .heic — PreToolUse
#        skipped, content goes straight to vision input
#     2. Read on .pdf — same skip; model receives parsed content
#        but no hook event fires
#     3. Image attachments via `claude --image` or drag-and-drop
#        in the desktop app — UserPromptSubmit fires but does not
#        carry the image path in tool_input in a hook-readable
#        schema
#
#   This means PreToolUse cannot be a security boundary against
#   prompt-injection-via-image attacks while the dispatch gap
#   exists: an attacker who gets the model to Read a poisoned
#   image bypasses every PreToolUse defense installed.
#
#   The earliest hook surface that DOES fire for these cases is
#   UserPromptSubmit. This hook scans the prompt text for binary
#   path references and surfaces them to the operator with the
#   articulated risk and operator-side options.
#
# WHO THIS PROTECTS:
#   Operators relying on PreToolUse hooks to gate file access,
#   especially those running Claude Code on machines where
#   ~/Downloads/ or similar directories may contain untrusted
#   image content (attachments from email, browser downloads).
#
# DETECTION:
#   UserPromptSubmit. Scan the prompt for path-like substrings
#   that end in a binary extension. Default extensions:
#     png, jpg, jpeg, gif, webp, heic, pdf, mp4, mov, mp3, wav,
#     zip, tar, gz, bin, exe, dll, so, dylib, doc, docx, xls,
#     xlsx, ppt, pptx
#   If matches found, emit an advisory naming the matched paths
#   and articulating the bypass risk.
#
# OUTPUT:
#   stderr advisory naming matched paths and articulating that:
#     - PreToolUse hooks WILL NOT fire when these are Read
#     - Hook-installed policies cannot be enforced against them
#     - Operator should verify the content is trusted before
#       proceeding (or pre-process to text out-of-band)
#   Exit 0 always (advisory, not blocking) so the prompt still
#   proceeds. The operator decides whether to continue.
#
# CONFIGURATION:
#   CC_BINARY_READ_DISABLE  — set to 1 to disable entirely
#   CC_BINARY_READ_BLOCK    — set to 1 to block (exit 2) instead
#                             of advisory pass-through
#   CC_BINARY_READ_EXTENSIONS — colon-separated extension list
#                             override (without dots)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/62639
#
# TRIGGER: UserPromptSubmit
# MATCHER: "" (all)
# ================================================================

set -u

INPUT=$(cat 2>/dev/null || echo "{}")

[ "${CC_BINARY_READ_DISABLE:-0}" = "1" ] && exit 0

DEFAULT_EXTS='png:jpg:jpeg:gif:webp:heic:pdf:mp4:mov:mp3:wav:zip:tar:gz:bin:exe:dll:so:dylib:doc:docx:xls:xlsx:ppt:pptx'
EXTS="${CC_BINARY_READ_EXTENSIONS:-$DEFAULT_EXTS}"

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // .user_message // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Build extension alternation pattern: \.(png|jpg|jpeg|...)\b
EXT_ALT=$(printf '%s' "$EXTS" | tr ':' '|')
PATTERN="\\.($EXT_ALT)(\\s|\$|['\"]|/|\\)|,|\\.|;)"

# Find all matching path-like substrings.
MATCHES=$(printf '%s' "$PROMPT" | grep -oiE "[A-Za-z0-9_./~-]+\\.($EXT_ALT)" | sort -u | head -10)

[ -z "$MATCHES" ] && exit 0

MSG="Binary path reference detected in prompt — PreToolUse hooks will NOT fire when Claude reads these:

$(printf '%s' "$MATCHES" | sed 's/^/  - /')

Issue #62639 documented that the Read tool dispatches image, PDF, and other binary content through a vision-routing path that bypasses the PreToolUse hook bus. Operator-installed PreToolUse policies cannot block, redirect, or audit these reads.

What this means for your hook policy:
- Any 'block reads outside this directory' rule does not apply
- Any 'audit-log every file read' rule misses these
- Prompt-injection-via-image attacks bypass every PreToolUse defense

Operator-side options:
1. Verify the file is trusted before proceeding. If it came from email, browser download, or external chat, treat it as untrusted
2. Pre-process to text out-of-band (e.g., 'tesseract image.png out' or 'pdftotext file.pdf -') and reference the text file instead. Text reads DO fire PreToolUse
3. For audit trails, install a PostToolUse hook — PostToolUse fires for binary reads (with empty tool_response.content for images) so the read is at least recorded
4. For policy enforcement, the only reliable layer is the OS (macOS Quarantine, Linux AppArmor profile, FUSE wrapper). PreToolUse cannot be a security boundary against this dispatch path

To disable this advisory:
  CC_BINARY_READ_DISABLE=1

To block instead of advise (exit 2 to prevent the prompt from running):
  CC_BINARY_READ_BLOCK=1

Related: cc-safe-setup Cluster 1 (Sub-Agent Observability), hook-bus completeness sub-pattern."

echo "[binary-read-detector] $MSG" >&2

if [ "${CC_BINARY_READ_BLOCK:-0}" = "1" ]; then
    exit 2
fi

exit 0
