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
#   gcloud storage rm / gcloud storage rb   (objects / buckets — #70024)
#   gsutil rm / gsutil rb                    (legacy GCS removal, incl. gsutil -m rm)
#   gcloud projects delete
#   az vm delete
#   az storage account delete
#   az sql db delete
#   az group delete
#   az ad group delete   (the irreversible deletion in #69397)
#
# Does NOT block:
#   gcloud compute instances list/describe
#   az vm list/show
#   gcloud/az read-only operations
#
# TRIGGER: PreToolUse  MATCHER: "Bash|PowerShell"
#   On Windows, az/gcloud commonly run through the PowerShell tool,
#   which is separate from Bash in Claude Code. A Bash-only matcher
#   never fires on the PowerShell tool, so the irreversible
#   `az ad group delete` in #69397 ran with no permission prompt.
#   Register with matcher "Bash|PowerShell"; both tools populate
#   tool_input.command.

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

# Block cloud-storage object/bucket removal via the `rm`/`rb` subcommands.
# The gcloud check above keys on delete|destroy|remove|reset, but Google Cloud
# Storage removal uses the literal subcommand `rm` (objects) and `rb` (buckets) —
# `gcloud storage rm` / `gsutil rm` — none of which contain "remove". Without this
# branch those slip past the guard entirely (and rm-safety-net only fires on a
# command that *starts* with `rm`, not on `gcloud storage rm`). #70024: an agent
# ran `gcloud storage rm -r` after a failed `mv` and destroyed the source objects.
if echo "$COMMAND" | grep -qE '\bgcloud\s+storage\s+(rm|rb)\b' \
   || echo "$COMMAND" | grep -qE '\bgsutil\s+(-[a-zA-Z]+\s+)*(rm|rb)\b'; then
    echo "BLOCKED: Destructive Google Cloud Storage removal detected." >&2
    echo "  Command: $COMMAND" >&2
    echo "  This deletes cloud objects/buckets irreversibly. Confirm the copy/move" >&2
    echo "  succeeded first ('gcloud storage ls' / 'cp'); never delete after an" >&2
    echo "  unverified transfer (#70024)." >&2
    exit 2
fi

# Block destructive az (Azure) operations
if echo "$COMMAND" | grep -qE '\baz\s+.*(delete|destroy|remove)\b'; then
    echo "BLOCKED: Destructive Azure operation detected." >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

exit 0
