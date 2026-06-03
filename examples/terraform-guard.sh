#!/bin/bash
# terraform-guard.sh — Warn before terraform/tofu destroy/apply
# Covers OpenTofu (`tofu`), the drop-in fork, and the `apply -destroy` form,
# which is the same teardown as `destroy` (a Terraform destroy has wiped a
# production database in the wild — DataTalks, and the class in
# anthropics/claude-code#27063).
# TRIGGER: PreToolUse  MATCHER: "Bash"
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
