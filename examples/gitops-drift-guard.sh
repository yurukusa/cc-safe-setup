#!/bin/bash
# gitops-drift-guard.sh — Warn when editing infrastructure files without PR
#
# Solves: Claude directly modifying Terraform, Kubernetes manifests, or
#         Helm values on the default branch instead of creating a PR.
#         In GitOps workflows, direct commits to main trigger immediate
#         infrastructure changes.
#
# How it works: PreToolUse hook on Edit/Write that checks if the target
#   file is an infrastructure file AND the current branch is main/master.
#   Warns that changes should go through a PR for review.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-gitops-drift-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [gitops-drift-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in Edit|Write) ;; *) exit 0 ;; esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Check if this is an infrastructure file
IS_INFRA=false
case "$FILE" in
    *.tf|*.tfvars) IS_INFRA=true ;;                    # Terraform
    */k8s/*.yaml|*/k8s/*.yml) IS_INFRA=true ;;         # Kubernetes manifests
    */helm/**/values*.yaml) IS_INFRA=true ;;            # Helm values
    */charts/**/*.yaml) IS_INFRA=true ;;                # Helm charts
    .github/workflows/*.yml) IS_INFRA=true ;;           # CI/CD workflows
    Dockerfile*|docker-compose*.yml) IS_INFRA=true ;;   # Docker
    */argocd/*.yaml) IS_INFRA=true ;;                   # ArgoCD
    */flux/*.yaml) IS_INFRA=true ;;                     # Flux
    ansible/*.yml|*/playbooks/*.yml) IS_INFRA=true ;;   # Ansible
esac

$IS_INFRA || exit 0

# Check if we're on a protected branch
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
case "$BRANCH" in
    main|master|production|release|release/*)
        echo "WARNING: Editing infrastructure file on protected branch '$BRANCH'." >&2
        echo "  File: $FILE" >&2
        echo "  In GitOps workflows, changes to $BRANCH trigger immediate deployment." >&2
        echo "  Consider creating a feature branch and PR instead." >&2
        # Warning only — change to exit 2 to block
        ;;
esac

exit 0
