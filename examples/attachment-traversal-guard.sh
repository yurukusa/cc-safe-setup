#!/usr/bin/env bash
# ================================================================
# attachment-traversal-guard.sh — Block @../ attachment bypass
# ================================================================
# PURPOSE:
#   Block the `@../path` attachment syntax that bypasses
#   `permissions.deny` rules by reaching file content through
#   the harness's attachment-preprocessing pipeline rather than
#   the `Read`-tool authorization point.
#
#   Reported case (anthropics/claude-code#61148, v2.1.146):
#     settings.json: { "permissions": { "deny": ["Read(**/Security/**)"] } }
#     workspace:    D:\TestProject\Library.Devices
#     target:       D:\TestProject\Library\Security\KeyIV.cs  (outside workspace)
#
#     Read D:\...\KeyIV.cs              → Blocked ✓
#     Read @Library\Security\KeyIV.cs   → Blocked ✓ (workspace attachment)
#     Read @..\Library\Security\KeyIV.cs → BYPASSED ✗
#
#   The attachment-preprocessing pipeline normalizes `@../`
#   before the permission check runs, so the resolved path
#   never reaches the `Read`-tool authorization point. PreToolUse
#   hooks on `Read` also do not fire (per the reporter's
#   independent verification).
#
#   This UserPromptSubmit hook intercepts the literal `@../`
#   pattern in the raw user prompt before the harness expands
#   the attachment, closing the bypass surface on the operator
#   side while a runtime fix is pending.
#
# TRIGGER: UserPromptSubmit  MATCHER: ""
#
# BEHAVIOR:
#   - Reads the user prompt from stdin (`.prompt` field).
#   - If the prompt contains `@../` or `@..\` (Windows-style),
#     blocks with exit 2 and an explanatory stderr message.
#   - In advisory mode (CC_ATTACHMENT_TRAVERSAL_BLOCK=0),
#     warns but does not block.
#   - Does NOT match `@./` (current-directory attachment, which
#     stays inside workspace and is enforced by the standard
#     deny rule).
#
# CONFIG:
#   CC_ATTACHMENT_TRAVERSAL_BLOCK=1  (1 = block, 0 = warn-only; default 1)
#   CC_ATTACHMENT_TRAVERSAL_ALLOW_REGEX=""  (allow paths matching this regex)
#
# REFERENCES:
#   - anthropics/claude-code#61148 — original report
#   - RUSE Surface 1 articulation: synonymous edges of the same
#     deny-rule outcome reached through a parallel pipeline.
#
# DEPENDENCIES:
#   - jq (for parsing the hook input JSON)
#
# LIMITATIONS:
#   - Detects the literal `@../` pattern in the prompt text.
#     Does not catch obfuscated variants (e.g., `@..%2F`,
#     `@%2E%2E/`) — those are not known to be expanded by the
#     attachment preprocessor at time of writing but should be
#     added to the regex if a reproduction surfaces.
#   - Cannot defend against file content already injected into
#     context by a previous prompt in the same session.
# ================================================================

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
[ -z "$PROMPT" ] && exit 0

BLOCK_MODE="${CC_ATTACHMENT_TRAVERSAL_BLOCK:-1}"
ALLOW_REGEX="${CC_ATTACHMENT_TRAVERSAL_ALLOW_REGEX:-}"

# Match @../ or @..\ at any position in the prompt
TRAVERSAL_REGEX='@\.\.[/\\]'

if echo "$PROMPT" | grep -qE "$TRAVERSAL_REGEX"; then
  # If allow-regex is set and matches the offending segment, permit.
  if [ -n "$ALLOW_REGEX" ] && echo "$PROMPT" | grep -qE "$ALLOW_REGEX"; then
    exit 0
  fi

  cat >&2 <<EOF
attachment-traversal-guard: blocked @../ attachment syntax.

  This prompt contains the @../ attachment pattern, which bypasses
  permissions.deny rules by reaching file content through the
  attachment-preprocessing pipeline rather than the Read-tool
  authorization point.

  See anthropics/claude-code#61148 for the reproduction.

  If you intentionally need to attach a parent-directory file:
    1. Disable this hook for the session, or
    2. Set CC_ATTACHMENT_TRAVERSAL_ALLOW_REGEX to a pattern that
       matches the specific parent-directory file you intend to
       attach (e.g., '@\\.\\./allowed/specific\\.txt').

  To convert this hook to warn-only mode:
    CC_ATTACHMENT_TRAVERSAL_BLOCK=0
EOF

  if [ "$BLOCK_MODE" = "1" ]; then
    exit 2
  fi
fi

exit 0
