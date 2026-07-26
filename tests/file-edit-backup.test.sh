#!/bin/bash
# Tests for file-edit-backup.sh
#
# The interesting case is path 2: a file overwritten through Bash
# (redirection, tee, mv) used to slip past this hook entirely.
# Reported by a reader on 2026-07-17.
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/file-edit-backup.sh"
PASS=0; FAIL=0

WORK=$(mktemp -d)
export HOME="$WORK/home"
mkdir -p "$HOME"
BACKUPS="$HOME/.claude/file-backups"

# expect_backup <desc> <json> <basename-that-must-appear|NONE>
expect_backup() {
    local desc="$1" input="$2" want="$3"
    rm -rf "$BACKUPS" 2>/dev/null
    ( cd "$WORK" && printf '%s' "$input" | bash "$HOOK" >/dev/null 2>&1 )
    local found=0
    if [ "$want" != "NONE" ] && [ -d "$BACKUPS" ]; then
        ls "$BACKUPS" 2>/dev/null | grep -q "$want" && found=1
    fi
    if [ "$want" = "NONE" ]; then
        if [ ! -d "$BACKUPS" ] || [ -z "$(ls -A "$BACKUPS" 2>/dev/null)" ]; then
            echo "PASS: $desc"; ((PASS++))
        else
            echo "FAIL: $desc (expected no backup, got $(ls "$BACKUPS"))"; ((FAIL++))
        fi
    elif [ "$found" = "1" ]; then
        echo "PASS: $desc"; ((PASS++))
    else
        echo "FAIL: $desc (expected a backup matching '$want')"; ((FAIL++))
    fi
}

cd "$WORK" || exit 1
echo "original" > target.md
echo "original" > appended.md
echo "original" > teed.md
echo "original" > moved.md

# Path 1 — the Edit/Write tools (existing behaviour must not regress)
expect_backup "Write on an existing file is backed up" \
    "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$WORK/target.md\"}}" "target.md"

expect_backup "Write on a new file makes no backup" \
    "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$WORK/does-not-exist.md\"}}" "NONE"

# Path 2 — Bash. This is the hole the reader named.
expect_backup "Bash redirection > is backed up" \
    '{"tool_name":"Bash","tool_input":{"command":"echo new > target.md"}}' "target.md"

expect_backup "Bash append >> is backed up" \
    '{"tool_name":"Bash","tool_input":{"command":"echo more >> appended.md"}}' "appended.md"

expect_backup "Bash tee is backed up" \
    '{"tool_name":"Bash","tool_input":{"command":"cat src | tee teed.md"}}' "teed.md"

expect_backup "Bash tee -a is backed up" \
    '{"tool_name":"Bash","tool_input":{"command":"cat src | tee -a teed.md"}}' "teed.md"

expect_backup "Bash mv destination is backed up" \
    '{"tool_name":"Bash","tool_input":{"command":"mv src.txt moved.md"}}' "moved.md"

expect_backup "Bash redirection inside a chain is backed up" \
    '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && echo x > target.md"}}' "target.md"

# Must NOT fire on things that only look like writes
expect_backup "fd duplication >&2 makes no backup" \
    '{"tool_name":"Bash","tool_input":{"command":"echo hi >&2"}}' "NONE"

expect_backup "stderr redirect 2>&1 makes no backup" \
    '{"tool_name":"Bash","tool_input":{"command":"make 2>&1 | less"}}' "NONE"

expect_backup "writing to a device file makes no backup" \
    '{"tool_name":"Bash","tool_input":{"command":"echo x > /dev/null"}}' "NONE"

expect_backup "redirect to a file that does not exist makes no backup" \
    '{"tool_name":"Bash","tool_input":{"command":"echo x > brand-new.md"}}' "NONE"

expect_backup "a read-only command makes no backup" \
    '{"tool_name":"Bash","tool_input":{"command":"grep -r TODO ."}}' "NONE"

# The hook must never block: exit code is always 0
code=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo x > target.md"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$code" = "0" ]; then echo "PASS: never blocks (exit 0)"; ((PASS++)); else echo "FAIL: expected exit 0, got $code"; ((FAIL++)); fi

cd / && rm -rf "$WORK" 2>/dev/null

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
