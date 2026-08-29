#!/bin/bash
# Tests for two gaps measured on Claude Code 2.1.246 (2026-08-29):
#   1. sensitive-file-read-guard let id_rsa.bak / id_rsa_old through, because
#      the private-key pattern was anchored with a bare "$". A backup of a key
#      is exactly as sensitive as the key.
#   2. credential-file-cat-guard covered .pypirc and .npmrc but not
#      .git-credentials, which stores "https://user:token@host" in plain text.
# Both guards must keep passing the files they were always meant to pass, so
# the allow cases below are as important as the block cases.
#
# Run: bash tests/test-private-key-backup-and-git-credentials.sh
set -uo pipefail

READ_HOOK="$(dirname "$0")/../examples/sensitive-file-read-guard.sh"
CAT_HOOK="$(dirname "$0")/../examples/credential-file-cat-guard.sh"
PASS=0 FAIL=0

run_read() {
    local desc="$1" expected_exit="$2" path="$3"
    local actual_exit
    echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"${path}\"}}" \
        | bash "$READ_HOOK" >/dev/null 2>/dev/null
    actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"; FAIL=$((FAIL + 1))
    fi
}

run_cat() {
    local desc="$1" expected_exit="$2" cmd="$3"
    local actual_exit
    echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":${cmd}}}" \
        | bash "$CAT_HOOK" >/dev/null 2>/dev/null
    actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"; FAIL=$((FAIL + 1))
    fi
}

echo "Testing private-key backups and .git-credentials"
echo "==============================================="

# --- BLOCK: private key backups ---
run_read "id_rsa.bak blocks"            2 "/home/u/.ssh/id_rsa.bak"
run_read "id_rsa_old blocks"            2 "/home/u/.ssh/id_rsa_old"
run_read "id_rsa.orig blocks"           2 "/home/u/.ssh/id_rsa.orig"
run_read "id_rsa.save blocks"           2 "/home/u/.ssh/id_rsa.save"
run_read "id_rsa-copy blocks"           2 "/home/u/.ssh/id_rsa-copy"
run_read "id_ed25519.backup blocks"     2 "/home/u/.ssh/id_ed25519.backup"
run_read "id_ecdsa.2 blocks"            2 "/home/u/.ssh/id_ecdsa.2"

# --- BLOCK: the three that survived the first widening ---
# Found by audit/boundary.sh after the first fix looked complete. Each one is
# the same file to whoever reads it and a different string to the matcher.
run_read "id_rsa~ (editor backup) blocks" 2 "/home/u/.ssh/id_rsa~"
run_read "id_rsa.old.2 (two suffixes) blocks" 2 "/home/u/.ssh/id_rsa.old.2"
run_read "id_rsa with trailing space blocks"  2 "/home/u/.ssh/id_rsa "
run_read "ID_RSA (uppercased) blocks"     2 "/home/u/.ssh/ID_RSA"
run_read "id_ed25519~ blocks"             2 "/home/u/.ssh/id_ed25519~"
# ...and the public key must survive all of that, trailing space included.
run_read "id_rsa.pub with trailing space allows" 0 "/home/u/.ssh/id_rsa.pub "

# --- BLOCK: the original cases must not regress ---
run_read "id_rsa still blocks"          2 "/home/u/.ssh/id_rsa"
run_read "id_ed25519 still blocks"      2 "/home/u/.ssh/id_ed25519"
run_read "aws credentials still blocks" 2 "/home/u/.aws/credentials"

# --- ALLOW: public keys and everything else must still pass ---
run_read "id_rsa.pub allows"            0 "/home/u/.ssh/id_rsa.pub"
run_read "id_ed25519.pub allows"        0 "/home/u/.ssh/id_ed25519.pub"
run_read "ssh config allows"            0 "/home/u/.ssh/config"
run_read "known_hosts allows"           0 "/home/u/.ssh/known_hosts"
run_read "project file allows"          0 "/home/u/app/README.md"
# A filename that merely starts with a key name is not a key.
run_read "id_rsa_generator.py allows"   0 "/home/u/tools/id_rsa_generator.py"
run_read "id_rsa.md allows"             0 "/home/u/docs/id_rsa.md"

# --- BLOCK: .git-credentials ---
run_cat "cat ~/.git-credentials blocks"  2 '"cat ~/.git-credentials"'
run_cat "head .git-credentials blocks"   2 '"head -1 /home/u/.git-credentials"'
run_cat "grep in .git-credentials blocks" 2 '"grep github /home/u/.git-credentials"'

# --- BLOCK: the original cases must not regress ---
run_cat "cat ~/.npmrc still blocks"      2 '"cat ~/.npmrc"'
run_cat "cat ~/.netrc still blocks"      2 '"cat ~/.netrc"'
run_cat "cat ~/.pypirc still blocks"     2 '"cat ~/.pypirc"'

# --- ALLOW: ordinary reads must still pass ---
run_cat "cat README.md allows"           0 '"cat README.md"'
run_cat "cat .git/config allows"         0 '"cat .git/config"'
run_cat "git config --list allows"       0 '"git config --list"'

echo
echo "=========================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
