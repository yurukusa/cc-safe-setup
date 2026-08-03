#!/bin/bash
# write-overwrite-confirm judged an overwrite by size alone, so the accident in
# issue #78273 passed silently: the agent read FIVE lines of a hand-built file,
# confirmed it had content, then replaced the whole file with its own analysis.
# The replacement was not smaller, so the size check never fired. The original
# was not in git and could not be recovered.
#
# Check 2 asks the other question — was the content being destroyed ever read —
# using the coverage recorded by examples/record-read-coverage.sh.
#
# The controls matter as much as the failing case. A guard that fires on every
# overwrite is the failure mode read-before-edit.sh already had while its
# recorder was missing, so these tests pin down when it must stay silent:
#   - the whole file was read
#   - the file is new, or small
#   - the replacement keeps the existing content
#   - no recorder is installed (no coverage information exists)

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/examples/write-overwrite-confirm.sh"
REC="$ROOT/examples/record-read-coverage.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
PASS=0; FAIL=0

mk_file() {  # mk_file <path> <lines>
  local p="$1" n="$2" i
  : > "$p"
  for ((i = 1; i <= n; i++)); do printf 'original line %d\n' "$i" >> "$p"; done
}

payload() {  # payload <tool> <file> <content>
  python3 -c '
import json,sys
print(json.dumps({"tool_name": sys.argv[1],
                  "tool_input": {"file_path": sys.argv[2], "content": sys.argv[3]}}))' "$@"
}

read_payload() {  # read_payload <file> <offset> <limit>
  python3 -c '
import json,sys
ti={"file_path": sys.argv[1]}
if int(sys.argv[2]): ti["offset"]=int(sys.argv[2])
if int(sys.argv[3]): ti["limit"]=int(sys.argv[3])
print(json.dumps({"tool_name":"Read","tool_input":ti}))' "$@"
}

check() {  # check <label> <expect-fire:0|1> <log> <write-json> [env...]
  local label="$1" expect="$2" log="$3" json="$4"; shift 4
  local out fired
  out=$(printf '%s' "$json" | env CC_READ_LOG="$log" "$@" bash "$HOOK" 2>&1 >/dev/null)
  if printf '%s' "$out" | grep -q 'never read'; then fired=1; else fired=0; fi
  if [ "$fired" = "$expect" ]; then
    PASS=$((PASS + 1)); printf '  ok   %s\n' "$label"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s (expected fire=%s, got %s)\n' "$label" "$expect" "$fired"
    printf '%s\n' "$out" | sed 's/^/       /' | head -4
  fi
}

# ---- the accident: five lines read, whole file replaced -------------------
F="$WORK/math.txt"; LOG="$WORK/log1"
mk_file "$F" 200
printf '%s' "$(read_payload "$F" 1 5)" | CC_READ_LOG="$LOG" bash "$REC" >/dev/null 2>&1
NEW=$(python3 -c 'print("\n".join("analysis line %d" % i for i in range(1,221)))')
check "#78273: read 5 of 200 lines, replaced all 200" 1 "$LOG" "$(payload Write "$F" "$NEW")"

# ---- same write, but the file was actually read in full ------------------
LOG2="$WORK/log2"
printf '%s' "$(read_payload "$F" 0 0)" | CC_READ_LOG="$LOG2" bash "$REC" >/dev/null 2>&1
check "control: whole file read first" 0 "$LOG2" "$(payload Write "$F" "$NEW")"

# ---- read in pages that together cover the file --------------------------
LOG3="$WORK/log3"
printf '%s' "$(read_payload "$F" 1 100)"   | CC_READ_LOG="$LOG3" bash "$REC" >/dev/null 2>&1
printf '%s' "$(read_payload "$F" 101 100)" | CC_READ_LOG="$LOG3" bash "$REC" >/dev/null 2>&1
check "control: read as two pages covering the whole file" 0 "$LOG3" "$(payload Write "$F" "$NEW")"

# ---- pages that leave a hole --------------------------------------------
LOG4="$WORK/log4"
printf '%s' "$(read_payload "$F" 1 50)"    | CC_READ_LOG="$LOG4" bash "$REC" >/dev/null 2>&1
printf '%s' "$(read_payload "$F" 150 51)"  | CC_READ_LOG="$LOG4" bash "$REC" >/dev/null 2>&1
check "pages with a gap in the middle still count as unread" 1 "$LOG4" "$(payload Write "$F" "$NEW")"

# ---- the replacement keeps every existing line ---------------------------
LOG5="$WORK/log5"
printf '%s' "$(read_payload "$F" 1 5)" | CC_READ_LOG="$LOG5" bash "$REC" >/dev/null 2>&1
KEEP=$(cat "$F"; printf 'appended line\n')
check "control: replacement keeps all existing lines" 0 "$LOG5" "$(payload Write "$F" "$KEEP")"

# ---- small file ----------------------------------------------------------
S="$WORK/small.txt"; LOG6="$WORK/log6"
mk_file "$S" 5
printf '%s' "$(read_payload "$S" 1 1)" | CC_READ_LOG="$LOG6" bash "$REC" >/dev/null 2>&1
check "control: file below the minimum line count" 0 "$LOG6" "$(payload Write "$S" "replaced")"

# ---- new file ------------------------------------------------------------
check "control: file does not exist yet" 0 "$WORK/log1" "$(payload Write "$WORK/brand-new.txt" "$NEW")"

# ---- no recorder installed ----------------------------------------------
check "control: no read log at all stays silent" 0 "$WORK/absent-log" "$(payload Write "$F" "$NEW")"

# ---- blocking mode returns exit 2 ---------------------------------------
printf '%s' "$(payload Write "$F" "$NEW")" | \
  env CC_READ_LOG="$WORK/log1" CC_WRITE_OVERWRITE_BLOCK=1 bash "$HOOK" >/dev/null 2>&1
if [ "$?" = "2" ]; then
  PASS=$((PASS + 1)); echo "  ok   CC_WRITE_OVERWRITE_BLOCK=1 refuses the write (exit 2)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL CC_WRITE_OVERWRITE_BLOCK=1 did not exit 2"
fi

# ---- the label must match what the run actually does --------------------
OUT=$(printf '%s' "$(payload Write "$F" "$NEW")" | env CC_READ_LOG="$WORK/log1" bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$OUT" | grep -q 'WARNING: overwriting' && ! printf '%s' "$OUT" | grep -q 'BLOCKED'; then
  PASS=$((PASS + 1)); echo "  ok   warn mode says WARNING, not BLOCKED"
else
  FAIL=$((FAIL + 1)); echo "  FAIL warn mode mislabels its own verdict"
fi

# ---- the original size check still works --------------------------------
OUT=$(printf '%s' "$(payload Write "$F" "tiny")" | env CC_READ_LOG="$WORK/log2" bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$OUT" | grep -q 'File shrinking from'; then
  PASS=$((PASS + 1)); echo "  ok   original shrink warning is unchanged"
else
  FAIL=$((FAIL + 1)); echo "  FAIL original shrink warning regressed"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
