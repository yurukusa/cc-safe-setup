#!/bin/bash
# The plugin hooks failed open under /bin/sh
#
# hooks/hooks.json holds the four inline guards that ship as the plugin's
# hook file. Claude Code runs an inline hook command through /bin/sh, and on
# Debian and Ubuntu /bin/sh is dash. Dash's builtin echo interprets backslash
# escapes; bash's does not.
#
# Every one of the four guards started with:
#
#   INPUT=$(cat); CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
#
# The hook payload is JSON, so a newline inside the command or the file
# content arrives as the two characters \n. Under dash, echo turned those two
# characters into a real newline *inside a JSON string*, jq rejected the
# document, CMD came back empty, and the very next clause is:
#
#   [ -z "$CMD" ] && exit 0
#
# exit 0 is an affirmative approval. So the guards let the tool call through,
# and the debug log recorded the hook as "success". Measured 2026-09-03: an
# agent asked to create .env wrote it with all six shipped hooks installed.
#
# Nothing local caught this for months because every test ran the commands
# under bash, where echo leaves \n alone. The five plugin manifests under
# plugins/ already used `printf %s "$INPUT"`; hooks/hooks.json never got the
# same change.
#
# Three more holes turned up in the same file once the parse was fixed:
#
#   1. The rm guard checked its exemption list (node_modules|dist|build|
#      __pycache__|tmp) against the whole command, so `cd /tmp` on line one
#      exempted `rm -rf /` on line two.
#   2. `sed -E 's/[;&|#].*$//'` truncated at the first `;`, so everything
#      after a separator was never examined at all.
#   3. A line continuation split the spelling and no guard matched it.
#
# The fix joins continuations, splits on statement separators, and asks the
# dangerous question and the exemption question about the *same* statement.
#
# Every case below runs the shipped command under /bin/sh, which is the shell
# that actually runs it in production.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$ROOT/hooks/hooks.json"
PASS=0
FAIL=0

hook_command() {
    # $1 = index into PreToolUse
    python3 -c "
import json, sys
d = json.load(open('$HOOKS', encoding='utf-8'))
pre = (d.get('hooks') or d)['PreToolUse']
sys.stdout.write(pre[$1]['hooks'][0]['command'])
"
}

check() {
    # $1=index  $2=label  $3=expected(block|allow)  $4=payload json
    local cmd rc got
    cmd=$(hook_command "$1")
    printf '%s' "$4" | /bin/sh -c "$cmd" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 2 ]; then got=block; else got=allow; fi
    if [ "$got" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL [hook $1] $2: expected $3, got $got (rc=$rc)"
    fi
}

bash_payload() {
    python3 -c "
import json, sys
sys.stdout.write(json.dumps({'tool_name': 'Bash',
                             'tool_input': {'command': sys.argv[1]}}))
" "$1"
}

write_payload() {
    python3 -c "
import json, sys
sys.stdout.write(json.dumps({'tool_name': 'Write',
                             'tool_input': {'file_path': sys.argv[1],
                                            'content': sys.argv[2]}}))
" "$1" "$2"
}

# The dangerous spellings are assembled so that mentioning them in this file
# does not trip the repository's own guards.
RM="rm -rf /"
PUSHF="git push --force origin main"
RESETH="git reset --hard HEAD~1"
CLEANFD="git clean -fd"

echo "hook 0 — recursive rm"
check 0 "plain"                 block "$(bash_payload "$RM")"
check 0 "newline after cd /tmp" block "$(bash_payload "$(printf 'cd /tmp\n%s' "$RM")")"
check 0 "newline after cd build" block "$(bash_payload "$(printf 'cd build\n%s' "$RM")")"
check 0 "line continuation"     block "$(bash_payload "$(printf 'rm \\\n -rf /')")"
check 0 "after a semicolon"     block "$(bash_payload "date; $RM")"
check 0 "after &&"              block "$(bash_payload "cd /tmp && $RM")"
check 0 "sudo prefix"           block "$(bash_payload "sudo $RM")"
check 0 "-fr order"             block "$(bash_payload "rm -fr /")"
check 0 "--recursive"           block "$(bash_payload "rm --recursive /etc")"
check 0 "home subdirectory"     block "$(bash_payload "rm -rf ~/Documents")"
check 0 "node_modules"          allow "$(bash_payload "rm -rf node_modules")"
check 0 "./build"               allow "$(bash_payload "rm -rf ./build")"
check 0 "dist/"                 allow "$(bash_payload "rm -rf dist/")"
check 0 "under /tmp"            allow "$(bash_payload "rm -rf /tmp/scratch")"
check 0 "non-recursive rm"      allow "$(bash_payload "rm -f foo.txt")"
check 0 "plain ls"              allow "$(bash_payload "ls -la")"
check 0 "inside a comment"      allow "$(bash_payload "date # $RM")"

echo "hook 1 — destructive git"
check 1 "force push"            block "$(bash_payload "$PUSHF")"
check 1 "force push continued"  block "$(bash_payload "$(printf 'git push \\\n --force origin main')")"
check 1 "force push line 2"     block "$(bash_payload "$(printf 'cd /tmp\n%s' "$PUSHF")")"
check 1 "hard reset"            block "$(bash_payload "$RESETH")"
check 1 "hard reset continued"  block "$(bash_payload "$(printf 'git reset \\\n --hard HEAD~1')")"
check 1 "clean -fd"             block "$(bash_payload "$CLEANFD")"
check 1 "clean -fd continued"   block "$(bash_payload "$(printf 'git clean \\\n -fd')")"
check 1 "force-with-lease"      allow "$(bash_payload "git push --force-with-lease origin main")"
check 1 "word on another line"  allow "$(bash_payload "$(printf 'git push origin main\necho --force')")"
check 1 "ordinary push"         allow "$(bash_payload "git push origin main")"
check 1 "soft reset"            allow "$(bash_payload "git reset --soft HEAD~1")"

echo "hook 2 — credentials in the command"
check 2 "inline key"            block "$(bash_payload "export API_KEY=abcdefghij0123456789xyz")"
check 2 "inline key continued"  block "$(bash_payload "$(printf 'export API_KEY=\\\nabcdefghij0123456789xyz')")"
check 2 "short value"           allow "$(bash_payload "export API_KEY=short")"
check 2 "unrelated"             allow "$(bash_payload "ls -la")"

echo "hook 3 — writes to sensitive files"
check 3 "dotenv"                block "$(write_payload "/x/.env" "$(printf 'A=1\nB=2')")"
check 3 "private key"           block "$(write_payload "/x/server.pem" "$(printf 'A=1\nB=2')")"
check 3 "ssh key"               block "$(write_payload "/x/id_rsa" "$(printf 'A=1\nB=2')")"
check 3 "dotenv template"       allow "$(write_payload "/x/.env.template" "$(printf 'A=1\nB=2')")"
check 3 "ordinary file"         allow "$(write_payload "/x/notes.md" "$(printf 'A=1\nB=2')")"

echo "no hook may still pipe echo into a parser"
# The file is JSON, so the spelling inside it is escaped. Grepping the raw
# bytes for the unescaped form matches nothing even when the defect is
# present -- a check that cannot fail. Read it as JSON and look at the
# commands after unescaping.
if python3 -c "
import json, sys
d = json.load(open('$HOOKS', encoding='utf-8'))
pre = (d.get('hooks') or d)['PreToolUse']
bad = [i for i, e in enumerate(pre)
       for h in e.get('hooks', [])
       if 'echo \"\$INPUT\"' in h.get('command', '')]
print(','.join(str(i) for i in bad))
sys.exit(1 if bad else 0)
"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: a hook still pipes echo \"\$INPUT\" into a parser"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
