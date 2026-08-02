#!/bin/bash
# terraform-guard.sh — Warn before terraform/tofu destroy/apply
# Covers OpenTofu (`tofu`), the drop-in fork, and the `apply -destroy` form,
# which is the same teardown as `destroy` (a Terraform destroy has wiped a
# production database in the wild — DataTalks, and the class in
# anthropics/claude-code#27063).
# TRIGGER: PreToolUse  MATCHER: "Bash|PowerShell"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-terraform-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [terraform-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\b(terraform|tofu)\s+destroy\b'; then
    echo "BLOCKED: terraform/tofu destroy is irreversible — it tears down managed infrastructure, including databases." >&2
    exit 2
fi
# `apply -destroy` runs the destroy plan; block it like a bare destroy.
if echo "$COMMAND" | grep -qE '\b(terraform|tofu)\s+apply\b' && echo "$COMMAND" | grep -qE '\-destroy\b'; then
    echo "BLOCKED: 'apply -destroy' is equivalent to terraform/tofu destroy (irreversible)." >&2
    exit 2
fi
if echo "$COMMAND" | grep -qE '\b(terraform|tofu)\s+apply\b' && ! echo "$COMMAND" | grep -q '\-auto-approve'; then
    echo "NOTE: terraform/tofu apply detected. Review the plan carefully." >&2
fi
exit 0
