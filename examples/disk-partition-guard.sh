#!/bin/bash
# disk-partition-guard.sh — Block disk partitioning and mount operations
#
# Solves: Claude Code running disk operations that can cause data loss
#         or system instability. Mounting/unmounting, partitioning, and
#         formatting are irreversible on production systems.
#
# Detects:
#   mount / umount           (filesystem mount operations)
#   fdisk / parted / gdisk   (partition table editors)
#   mkfs / mkswap            (filesystem/swap creation)
#   dd if=                   (raw disk writes)
#   swapon / swapoff         (swap management)
#
# Does NOT block:
#   df / lsblk / blkid       (read-only disk info)
#   mount (no args)          (list mounts)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block partition editors
if echo "$COMMAND" | grep -qE '\b(fdisk|parted|gdisk|cfdisk|sfdisk)\b'; then
    echo "BLOCKED: Disk partitioning tool detected." >&2
    echo "  Partitioning can cause irreversible data loss." >&2
    exit 2
fi

# Block filesystem creation
if echo "$COMMAND" | grep -qE '\b(mkfs|mkswap|mke2fs)\b'; then
    echo "BLOCKED: Filesystem creation/formatting detected." >&2
    exit 2
fi

# Block mount/umount with arguments
if echo "$COMMAND" | grep -qE '\bumount\b|\bumount\b'; then
    echo "BLOCKED: Unmounting filesystem can cause data loss." >&2
    exit 2
fi
if echo "$COMMAND" | grep -qE '\bmount\s+\S' && ! echo "$COMMAND" | grep -qE '\bmount\s*$'; then
    echo "BLOCKED: Mounting filesystem requires administrator oversight." >&2
    exit 2
fi

# Block dd (raw disk writes)
if echo "$COMMAND" | grep -qE '\bdd\s+if='; then
    echo "BLOCKED: Raw disk write (dd) detected." >&2
    exit 2
fi

# Block swap management
if echo "$COMMAND" | grep -qE '\b(swapon|swapoff)\b'; then
    echo "BLOCKED: Swap management operation detected." >&2
    exit 2
fi

exit 0
