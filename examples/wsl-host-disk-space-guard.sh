#!/bin/bash
# ================================================================
# wsl-host-disk-space-guard.sh — Watch the WSL host (Windows C:) too
# ================================================================
# PURPOSE:
#   The bundled disk-space-guard.sh only inspects the working
#   directory's filesystem (`df .`). On WSL2 that misses the actual
#   choke point: the Windows host drive that backs ext4.vhdx.
#
#   Past incident (2026-05-04): WSL `/dev/sdd` had 162 GiB free, but
#   Windows `C:` was at 96% (38 GiB free out of 931 GiB). Claude Code
#   and Codex CLI both crashed with "getpwnam failed" / I/O errors
#   because the host could no longer extend ext4.vhdx.
#
#   This hook checks `/`, `/home`, and `/mnt/c`, blocks Bash/Write
#   when the host is critical, and warns earlier than that.
#
# TRIGGER: PreToolUse  MATCHER: "Write|Bash"
#
# CONFIG:
#   CC_HOST_DISK_WARN_PCT=90       /mnt/c warn at this percent used
#   CC_HOST_DISK_BLOCK_PCT=95      /mnt/c block at this percent used
#   CC_LINUX_DISK_WARN_PCT=85      /, /home warn at this percent used
#   CC_LINUX_DISK_BLOCK_PCT=95     /, /home block at this percent used
#   CC_HOST_DISK_DISABLE=1         disable this hook entirely
# ================================================================

[ "${CC_HOST_DISK_DISABLE:-0}" = "1" ] && exit 0

HOST_WARN="${CC_HOST_DISK_WARN_PCT:-90}"
HOST_BLOCK="${CC_HOST_DISK_BLOCK_PCT:-95}"
LINUX_WARN="${CC_LINUX_DISK_WARN_PCT:-85}"
LINUX_BLOCK="${CC_LINUX_DISK_BLOCK_PCT:-95}"

# Read percent used for a mount point, or empty if it does not exist.
# We check existence so this hook works on non-WSL hosts too.
pct_for() {
    local mount="$1"
    [ -d "$mount" ] || return 0
    df --output=pcent "$mount" 2>/dev/null | tail -1 | tr -d ' %'
}

avail_for() {
    local mount="$1"
    [ -d "$mount" ] || return 0
    df -h --output=avail "$mount" 2>/dev/null | tail -1 | tr -d ' '
}

block=0
warn_lines=""

check_linux() {
    local mount="$1"
    local pct
    pct=$(pct_for "$mount")
    [ -z "$pct" ] && return 0
    if [ "$pct" -ge "$LINUX_BLOCK" ]; then
        echo "BLOCKED: $mount is ${pct}% full ($(avail_for "$mount") free) — above ${LINUX_BLOCK}%." >&2
        echo "  Free space inside WSL before more writes:" >&2
        echo "    du -sh ~/.cache ~/.npm ~/.claude/debug ~/.local/share/Trash 2>/dev/null" >&2
        block=1
    elif [ "$pct" -ge "$LINUX_WARN" ]; then
        warn_lines="${warn_lines}WARNING: $mount is ${pct}% full ($(avail_for "$mount") free) — above ${LINUX_WARN}%."$'\n'
    fi
}

check_host() {
    local mount="$1"
    local pct
    pct=$(pct_for "$mount")
    [ -z "$pct" ] && return 0
    if [ "$pct" -ge "$HOST_BLOCK" ]; then
        echo "BLOCKED: Windows host $mount is ${pct}% full ($(avail_for "$mount") free) — above ${HOST_BLOCK}%." >&2
        echo "  WSL can no longer safely extend ext4.vhdx. Past incident crashed CC and Codex." >&2
        echo "  Recovery on Windows (admin PowerShell):" >&2
        echo "    wsl --shutdown" >&2
        echo "    Optimize-VHD -Path <ext4.vhdx> -Mode Full" >&2
        block=1
    elif [ "$pct" -ge "$HOST_WARN" ]; then
        warn_lines="${warn_lines}WARNING: Windows host $mount is ${pct}% full ($(avail_for "$mount") free) — above ${HOST_WARN}%."$'\n'
    fi
}

# /home is on the same vhdx as / on most WSL setups, but check both in
# case the user mounted /home separately.
check_linux /
[ "$(stat -c '%d' /home 2>/dev/null)" != "$(stat -c '%d' / 2>/dev/null)" ] && check_linux /home

# /mnt/c only exists on WSL.
check_host /mnt/c

if [ -n "$warn_lines" ]; then
    printf '%s' "$warn_lines" >&2
fi

[ "$block" -eq 1 ] && exit 2
exit 0
