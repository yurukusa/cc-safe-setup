#!/bin/bash
# Test for stale-temp-settings-detector.sh
#
# Verifies the hook warns when a /tmp/claude-settings-*.json
# file is owned by a different uid, and stays silent in the safe
# cases (no files / own files only / disabled / second run).

set -u

HOOK="$(dirname "$0")/../examples/stale-temp-settings-detector.sh"
[ ! -x "$HOOK" ] && chmod +x "$HOOK"

PASS=0
FAIL=0

LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR"

# Use a sandbox /tmp-equivalent we control. The hook hard-codes /tmp,
# so we need to redirect via a chroot-free approach: stub `find` and
# `stat` via PATH override.

STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT

CURRENT_UID=$(id -u)
FOREIGN_UID=$((CURRENT_UID + 1))

# Stub `find` and `stat` so we can simulate /tmp contents without
# actually touching /tmp.
make_stubs() {
    local listing="$1"   # newline-separated: path:uid:owner
    cat > "$STUB_DIR/find" <<'STUB'
#!/bin/bash
# Only respond to the hook's exact query. Pass other args through.
if [[ "$*" == *"/tmp -maxdepth 1 -name claude-settings-"* ]]; then
    LISTING_FILE="${STUB_LISTING_FILE:-}"
    [ -n "$LISTING_FILE" ] && [ -f "$LISTING_FILE" ] && cut -d: -f1 "$LISTING_FILE"
    exit 0
fi
exec /usr/bin/find "$@"
STUB
    chmod +x "$STUB_DIR/find"

    cat > "$STUB_DIR/stat" <<'STUB'
#!/bin/bash
# Parse: stat -c '%u' /path  →  fmt=%u, target=/path
fmt=""
target=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) fmt="$2"; shift 2 ;;
        *) target="$1"; shift ;;
    esac
done
LISTING_FILE="${STUB_LISTING_FILE:-}"
[ -z "$LISTING_FILE" ] && exit 1
while IFS=: read -r p u o; do
    [ "$p" = "$target" ] || continue
    case "$fmt" in
        '%u') echo "$u"; exit 0 ;;
        '%U') echo "$o"; exit 0 ;;
    esac
done < "$LISTING_FILE"
exit 1
STUB
    chmod +x "$STUB_DIR/stat"

    printf '%s\n' "$listing" > "$STUB_DIR/listing.txt"
}

run_case() {
    local name="$1"
    local listing="$2"
    local expect_warn="$3"   # "yes" or "no"
    local extra_env="${4:-}"

    make_stubs "$listing"

    local sess="stale-test-$(date +%s%N)-$$"
    local input
    input=$(jq -nc --arg sid "$sess" '{session_id:$sid}')

    local stderr rc
    stderr=$(echo "$input" | env -i HOME="$HOME" PATH="$STUB_DIR:/usr/bin:/bin" \
        STUB_LISTING_FILE="$STUB_DIR/listing.txt" $extra_env "$HOOK" 2>&1 >/dev/null)
    rc=$?

    local warned=no
    if echo "$stderr" | grep -q "stale-temp-settings-detector"; then
        warned=yes
    fi

    if [ "$rc" -ne 0 ]; then
        FAIL=$((FAIL+1))
        echo "FAIL: $name — exit $rc (expected 0)"
    elif [ "$warned" = "$expect_warn" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $name — warned=$warned, expected $expect_warn"
        echo "      stderr: $stderr"
    fi

    [ -f "$LOG_DIR/stale-temp-settings-warned-$sess" ] && rm -f "$LOG_DIR/stale-temp-settings-warned-$sess"
}

CURRENT_OWNER=$(id -un)
OTHER_OWNER="someone-else"

# Test 1: no settings files at all → silent
run_case "no settings files stays silent" "" no

# Test 2: own settings file only → silent
run_case "own settings file stays silent" \
    "/tmp/claude-settings-own.json:$CURRENT_UID:$CURRENT_OWNER" no

# Test 3: foreign settings file → warns
run_case "foreign settings file warns" \
    "/tmp/claude-settings-foreign.json:$FOREIGN_UID:$OTHER_OWNER" yes

# Test 4: mix of own and foreign → warns (foreign present)
LISTING="/tmp/claude-settings-own.json:$CURRENT_UID:$CURRENT_OWNER
/tmp/claude-settings-foreign.json:$FOREIGN_UID:$OTHER_OWNER"
run_case "mixed listing warns on the foreign one" "$LISTING" yes

# Test 5: disable env silences even with foreign file
run_case "disable env silences" \
    "/tmp/claude-settings-foreign.json:$FOREIGN_UID:$OTHER_OWNER" no \
    "STALE_TEMP_SETTINGS_DISABLE=1"

# Test 6: second run in same session is silent
make_stubs "/tmp/claude-settings-foreign.json:$FOREIGN_UID:$OTHER_OWNER"
SESS6="stale-test-twice-$(date +%s%N)-$$"
INPUT6=$(jq -nc --arg sid "$SESS6" '{session_id:$sid}')
FIRST=$(echo "$INPUT6" | env -i HOME="$HOME" PATH="$STUB_DIR:/usr/bin:/bin" STUB_LISTING_FILE="$STUB_DIR/listing.txt" "$HOOK" 2>&1 >/dev/null)
SECOND=$(echo "$INPUT6" | env -i HOME="$HOME" PATH="$STUB_DIR:/usr/bin:/bin" STUB_LISTING_FILE="$STUB_DIR/listing.txt" "$HOOK" 2>&1 >/dev/null)
if echo "$FIRST" | grep -q "stale-temp-settings-detector" \
   && ! echo "$SECOND" | grep -q "stale-temp-settings-detector"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: second run in same session not silenced"
    echo "      first:  $FIRST"
    echo "      second: $SECOND"
fi
[ -f "$LOG_DIR/stale-temp-settings-warned-$SESS6" ] && rm -f "$LOG_DIR/stale-temp-settings-warned-$SESS6"

# Test 7: malformed input (no session_id) → still safe
STDERR7=$(echo '{}' | env -i HOME="$HOME" PATH="$STUB_DIR:/usr/bin:/bin" STUB_LISTING_FILE="$STUB_DIR/listing.txt" "$HOOK" 2>&1 >/dev/null)
RC7=$?
if [ "$RC7" -eq 0 ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: malformed input should exit 0 (rc=$RC7)"
fi

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
