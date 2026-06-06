#!/bin/bash
# Tests for false-disk-full-guard.sh
HOOK="examples/false-disk-full-guard.sh"
PASS=0 FAIL=0
ac() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
anc() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
ax() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2 != $3)"; fi; }

# Test 1: fabricated message + a dir with space → advisory fires, exit 0
MSG="Command output was lost: the temp filesystem at /tmp is full (0MB free). The child process's stdout/stderr writes failed with ENOSPC."
OUT=$(printf '{"tool_name":"Bash","tool_response":"%s"}' "$MSG" | bash "$HOOK" 2>&1); RC=$?
ax "fires exits 0" "$RC" 0
ac "warns false-positive" "$OUT" "false-disk-full-guard"
ac "tells not to rm/prune" "$OUT" "Do NOT run rm"

# Test 2: object-shaped tool_response (stdout field) → still detected
OUT=$(printf '{"tool_name":"Bash","tool_response":{"stdout":"%s","stderr":""}}' "$MSG" | bash "$HOOK" 2>&1)
ac "object response detected" "$OUT" "false-disk-full-guard"

# Test 3: normal command output → silent
OUT=$(printf '{"tool_name":"Bash","tool_response":"hello world\nexit 0"}' | bash "$HOOK" 2>&1); RC=$?
ax "normal exits 0" "$RC" 0
anc "normal stays silent" "$OUT" "false-disk-full-guard"

# Test 4: genuinely no-match empty payload → silent, exit 0
OUT=$(printf '{}' | bash "$HOOK" 2>&1); RC=$?
ax "empty exits 0" "$RC" 0
anc "empty silent" "$OUT" "false-disk-full-guard"

# Test 5: ENOSPC phrasing variant detected
MSG2="writes failed with ENOSPC"
OUT=$(printf '{"tool_name":"Bash","tool_response":"%s"}' "$MSG2" | bash "$HOOK" 2>&1)
ac "ENOSPC variant detected" "$OUT" "false-disk-full-guard"

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
