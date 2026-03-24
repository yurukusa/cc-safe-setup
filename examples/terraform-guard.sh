#!/bin/bash
# terraform-guard.sh — Warn before terraform destroy/apply
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\bterraform\s+destroy\b'; then
    echo "BLOCKED: terraform destroy is irreversible" >&2
    exit 2
fi
if echo "$COMMAND" | grep -qE '\bterraform\s+apply\b' && ! echo "$COMMAND" | grep -q '\-auto-approve'; then
    echo "NOTE: terraform apply detected. Review the plan carefully." >&2
fi
exit 0
