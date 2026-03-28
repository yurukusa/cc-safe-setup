#!/bin/bash
# cloud-cli-guard.sh — Block destructive GCP/Azure CLI operations
#
# Solves: Claude Code running destructive cloud operations via gcloud/az CLI.
#         Deleting VMs, storage, or databases in cloud environments can
#         cause irreversible data loss and significant costs.
#
# Note: AWS is covered by aws-production-guard.sh
#
# Detects:
#   gcloud compute instances delete
#   gcloud sql instances delete
#   gcloud storage rm
#   gcloud projects delete
#   az vm delete
#   az storage account delete
#   az sql db delete
#   az group delete
#
# Does NOT block:
#   gcloud compute instances list/describe
#   az vm list/show
#   gcloud/az read-only operations
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block destructive gcloud operations
if echo "$COMMAND" | grep -qE '\bgcloud\s+.*(delete|destroy|remove|reset)\b'; then
    echo "BLOCKED: Destructive Google Cloud operation detected." >&2
    echo "  Command: $COMMAND" >&2
    echo "  Use 'gcloud ... describe' or 'gcloud ... list' to check first." >&2
    exit 2
fi

# Block destructive az (Azure) operations
if echo "$COMMAND" | grep -qE '\baz\s+.*(delete|destroy|remove)\b'; then
    echo "BLOCKED: Destructive Azure operation detected." >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

exit 0
