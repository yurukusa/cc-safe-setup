#!/bin/bash
# Tests for session-backup-on-start.sh
# Covers #41874 (silent JSONL deletion) and #59248 (orphan subagents)
HOOK="examples/session-backup-on-start.sh"
PASS=0 FAIL=0

assert_exit() {
    if [ "$2" -eq "$3" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $1 (exit $2, expected $3)"
    fi
}

assert_file_exists() {
    if [ -f "$2" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $1 (file missing: $2)"
    fi
}

assert_file_missing() {
    if [ ! -f "$2" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $1 (file unexpectedly present: $2)"
    fi
}

assert_dir_exists() {
    if [ -d "$2" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $1 (dir missing: $2)"
    fi
}

assert_dir_missing() {
    if [ ! -d "$2" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $1 (dir unexpectedly present: $2)"
    fi
}

# Set up an isolated HOME so we don't touch the real ~/.claude
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
export CC_SESSION_BACKUP_DIR="$TEST_HOME/.claude/session-backups"

setup_session_dir() {
    local jsonl_count="$1"
    local subagent_count="${2:-0}"
    rm -rf "$TEST_HOME/.claude"
    CWD=$(pwd)
    PROJECT_NAME=$(printf '%s' "$CWD" | sed 's|/|-|g; s|^-||')
    SESSION_DIR="$TEST_HOME/.claude/projects/$PROJECT_NAME"
    mkdir -p "$SESSION_DIR"
    for i in $(seq 1 "$jsonl_count"); do
        printf '{"sid":"s%d","content":"transcript %d"}\n' "$i" "$i" > "$SESSION_DIR/session-$i.jsonl"
    done
    for i in $(seq 1 "$subagent_count"); do
        mkdir -p "$SESSION_DIR/subagent-$i"
        printf '{"sid":"sub%d"}\n' "$i" > "$SESSION_DIR/subagent-$i/sub-trans.jsonl"
    done
}

get_dest_glob() {
    CWD=$(pwd)
    PROJECT_NAME=$(printf '%s' "$CWD" | sed 's|/|-|g; s|^-||')
    echo "$TEST_HOME/.claude/session-backups/$PROJECT_NAME"
}

# Test 1: No session dir — exits 0 with no error
rm -rf "$TEST_HOME/.claude"
OUT=$(bash "$HOOK" 2>&1)
RC=$?
assert_exit "no session dir exits 0" "$RC" 0

# Test 2: Empty session dir (no JSONL) — exits 0, no backup created
CWD=$(pwd)
PROJECT_NAME=$(printf '%s' "$CWD" | sed 's|/|-|g; s|^-||')
mkdir -p "$TEST_HOME/.claude/projects/$PROJECT_NAME"
OUT=$(bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty session dir exits 0" "$RC" 0
assert_dir_missing "no backup when no JSONL" "$(get_dest_glob)"

# Test 3: 3 JSONL files, no subagents — JSONLs are backed up, no subagents copied
setup_session_dir 3 0
unset CC_SESSION_BACKUP_SUBAGENTS
OUT=$(bash "$HOOK" 2>&1)
RC=$?
assert_exit "JSONL backup exits 0" "$RC" 0
DEST_GLOB=$(get_dest_glob)
BACKUP_DIR=$(ls -1d "$DEST_GLOB"/*/ 2>/dev/null | head -1)
assert_file_exists "session-1.jsonl backed up" "$BACKUP_DIR/session-1.jsonl"
assert_file_exists "session-2.jsonl backed up" "$BACKUP_DIR/session-2.jsonl"
assert_file_exists "session-3.jsonl backed up" "$BACKUP_DIR/session-3.jsonl"

# Test 4: With subagents but flag off — subagents NOT copied (default behavior)
setup_session_dir 1 2
unset CC_SESSION_BACKUP_SUBAGENTS
OUT=$(bash "$HOOK" 2>&1)
DEST_GLOB=$(get_dest_glob)
BACKUP_DIR=$(ls -1d "$DEST_GLOB"/*/ 2>/dev/null | head -1)
assert_file_exists "JSONL still backed up" "$BACKUP_DIR/session-1.jsonl"
assert_dir_missing "subagent-1 NOT backed up by default" "$BACKUP_DIR/subagent-1"

# Test 5: With subagents AND flag on — subagents ARE copied (#59248 defense)
setup_session_dir 1 2
export CC_SESSION_BACKUP_SUBAGENTS=1
OUT=$(bash "$HOOK" 2>&1)
DEST_GLOB=$(get_dest_glob)
BACKUP_DIR=$(ls -1d "$DEST_GLOB"/*/ 2>/dev/null | head -1)
assert_file_exists "JSONL backed up with subagent flag" "$BACKUP_DIR/session-1.jsonl"
assert_dir_exists "subagent-1 backed up when flag=1" "$BACKUP_DIR/subagent-1"
assert_dir_exists "subagent-2 backed up when flag=1" "$BACKUP_DIR/subagent-2"
assert_file_exists "subagent inner file preserved" "$BACKUP_DIR/subagent-1/sub-trans.jsonl"
unset CC_SESSION_BACKUP_SUBAGENTS

# Test 6: Output message reflects subagent count when flag on
setup_session_dir 1 2
export CC_SESSION_BACKUP_SUBAGENTS=1
OUT=$(bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "subagent dirs"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: output mentions subagent dirs (got: $OUT)"
fi
unset CC_SESSION_BACKUP_SUBAGENTS

# Test 7: Output message has NO subagent mention when flag off
setup_session_dir 1 2
unset CC_SESSION_BACKUP_SUBAGENTS
OUT=$(bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "subagent dirs"; then
    FAIL=$((FAIL+1))
    echo "FAIL: output should not mention subagent dirs (got: $OUT)"
else
    PASS=$((PASS+1))
fi

# Test 8: Pruning — KEEP=2, run 4 times, only 2 latest survive
setup_session_dir 1 0
export CC_SESSION_BACKUP_KEEP=2
unset CC_SESSION_BACKUP_SUBAGENTS
for i in 1 2 3 4; do
    sleep 1
    bash "$HOOK" >/dev/null 2>&1
done
DEST_GLOB=$(get_dest_glob)
BACKUP_COUNT=$(ls -1d "$DEST_GLOB"/*/ 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -eq 2 ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: pruning kept $BACKUP_COUNT backups, expected 2"
fi
unset CC_SESSION_BACKUP_KEEP

# Test 9: Timestamp directory format (YYYYMMDD-HHMMSS)
setup_session_dir 1 0
bash "$HOOK" >/dev/null 2>&1
DEST_GLOB=$(get_dest_glob)
LATEST=$(ls -1d "$DEST_GLOB"/*/ 2>/dev/null | head -1 | xargs basename 2>/dev/null)
if echo "$LATEST" | grep -qE '^[0-9]{8}-[0-9]{6}$'; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: timestamp format unexpected: $LATEST"
fi

# Cleanup
rm -rf "$TEST_HOME"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
