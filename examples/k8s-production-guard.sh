#!/bin/bash
# k8s-production-guard.sh — Block destructive Kubernetes operations on production
#
# Solves: Claude running kubectl delete, scale-to-zero, or rollback on
#         production namespaces/clusters without explicit confirmation.
#
# How it works: PreToolUse hook on Bash that detects kubectl/helm commands
#   targeting production contexts/namespaces and blocks destructive operations.
#
# CONFIG:
#   CC_K8S_PROD_CONTEXTS="prod:production:live" (colon-separated)
#   CC_K8S_PROD_NAMESPACES="production:prod:default" (colon-separated)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check kubectl/helm commands
echo "$COMMAND" | grep -qE '(kubectl|helm)\s' || exit 0

# Production indicators
PROD_CTX="${CC_K8S_PROD_CONTEXTS:-prod:production:live}"
PROD_NS="${CC_K8S_PROD_NAMESPACES:-production:prod}"

# Destructive kubectl operations
DESTRUCT_KUBECTL='delete\s+(deploy|pod|svc|namespace|pv|statefulset|daemonset|job|cronjob|ingress|secret|configmap)|scale\s+.*--replicas=0|drain\s|cordon\s|taint\s.*NoSchedule|rollout\s+undo'

# Destructive helm operations
DESTRUCT_HELM='helm\s+(uninstall|delete|rollback|reset)'

# Check if command is destructive
IS_DESTRUCTIVE=false
if echo "$COMMAND" | grep -qE "$DESTRUCT_KUBECTL"; then
    IS_DESTRUCTIVE=true
fi
if echo "$COMMAND" | grep -qE "$DESTRUCT_HELM"; then
    IS_DESTRUCTIVE=true
fi

$IS_DESTRUCTIVE || exit 0

# Check if targeting production
IS_PROD=false

# Check --context flag
IFS=':' read -ra CTXS <<< "$PROD_CTX"
for ctx in "${CTXS[@]}"; do
    if echo "$COMMAND" | grep -qE -- "--context[= ]$ctx"; then
        IS_PROD=true
        break
    fi
done

# Check -n/--namespace flag
IFS=':' read -ra NSS <<< "$PROD_NS"
for ns in "${NSS[@]}"; do
    if echo "$COMMAND" | grep -qE -- "(-n|--namespace)[= ]$ns"; then
        IS_PROD=true
        break
    fi
done

if $IS_PROD; then
    echo "BLOCKED: Destructive Kubernetes operation on production." >&2
    echo "  Command: $COMMAND" >&2
    echo "  Run this manually if you're sure." >&2
    exit 2
fi

# Not targeting production explicitly — warn but allow
echo "NOTE: Destructive k8s operation (not targeting a known prod namespace)." >&2
exit 0
