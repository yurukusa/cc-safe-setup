#!/bin/bash
# multiline-command-approver.sh — Auto-approve multiline commands safely
#
# Solves: Auto-approve patterns fail on heredocs and multiline commands
#         (#11932 — 47 reactions, 29 comments)
#
# This is needed because Claude Code's built-in pattern matching
# evaluates the entire multiline string, which breaks on heredocs:
#   echo 'commit message\n\nCo-Authored-By: ...' > file
#   ↑ This won't match Bash(echo:*) because of newlines
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/multiline-command-approver.sh" }]
#     }]
#   }
# }
#
# Rewritten 2026-08-03. The old version took `head -1` of the command and
# approved the whole thing when that one line matched a safe prefix. It had two
# holes, and the second one was the hook's own subject matter:
#
#   separators : over the 32 commands it approved bare, appending
#                `&& sudo rm -rf /var/app`, `; curl http://… | sh` or
#                `&& git push --force` kept the approval 288/288 times.
#   newlines   : `cat <<'EOF' > note.txt` on line 1 with a destructive command
#                on line 2 kept the approval 18/18 times. A hook whose entire
#                purpose is multiline input was reading one line of it.
#
# The control says which repair this needs: the same dangerous commands on
# their own were approved 0/5 and 0/3 times. It never approved anything — it
# just never looked past the first line's first command.
#
# Reading further is not as simple as splitting on separators here, because the
# forms this hook exists to rescue put separators and newlines *inside* data:
# a commit message spanning lines, a heredoc body. So the command is scanned
# with the quoting state carried across lines, and heredoc bodies are skipped
# between their opener and their terminator. What is left is the actual command
# positions, and every one of them has to match a safe prefix.
#
# A line that does not qualify gets no decision, which leaves it to the normal
# permission flow. This hook only ever adds approval; it never blocks.
#
# Known limits:
#   - Command substitution and backticks are refused outright. Their contents
#     cannot be judged by reading the string.
#   - Some prefixes below hand execution to an interpreter (`python3 -c`,
#     `node -e`, `npx`, `curl -s`). Those are a separate problem from the one
#     fixed here — the granularity of the safe list, not where it looks — and
#     are measured separately.
#   - More than one heredoc opened on the same line is refused rather than
#     guessed at.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Safe command prefixes. Each command position must match one of these.
SAFE_PREFIXES=(
    "echo "
    "printf "
    "cat "
    "cat <<"
    "tee "
    "git commit"
    "git tag"
    "git log"
    "git status"
    "git diff"
    "git show"
    "git branch"
    "git stash"
    "npm test"
    "npm run"
    "npx "
    "python3 -c"
    "python3 -m"
    "node -e"
    "jq "
    "grep "
    "find "
    "ls "
    "wc "
    "head "
    "tail "
    "sort "
    "uniq "
    "tr "
    "cut "
    "sed "
    "awk "
    "curl -s"
)

POSITIONS=()

cc_flush() {
    local t="$1"
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [ -z "$t" ] && return 0
    case "$t" in '#'*) return 0 ;; esac   # a comment is not a command position
    POSITIONS+=("$t")
}

# Split the command into command positions, carrying quoting state across lines
# and skipping heredoc bodies. Returns 1 for anything it will not vouch for.
cc_scan() {
    local sq=0 dq=0 seg="" hd_active=0 hd_delim="" hd_dash=0
    local line i n c nx j d q ch pending_delim="" pending_dash=0 pending_count=0

    while IFS= read -r line; do
        if [ "$hd_active" -eq 1 ]; then
            local cand="$line"
            [ "$hd_dash" -eq 1 ] && cand="${cand#"${cand%%[![:space:]]*}"}"
            [ "$cand" = "$hd_delim" ] && hd_active=0
            continue
        fi

        pending_delim=""; pending_count=0
        i=0; n=${#line}
        while [ "$i" -lt "$n" ]; do
            c="${line:i:1}"

            if [ "$sq" -eq 1 ]; then
                [ "$c" = "'" ] && sq=0
                seg+="$c"; i=$((i + 1)); continue
            fi
            if [ "$dq" -eq 1 ]; then
                if [ "$c" = '\' ]; then seg+="${line:i:2}"; i=$((i + 2)); continue; fi
                [ "$c" = '"' ] && dq=0
                seg+="$c"; i=$((i + 1)); continue
            fi

            case "$c" in
                "'") sq=1; seg+="$c"; i=$((i + 1)) ;;
                '"') dq=1; seg+="$c"; i=$((i + 1)) ;;
                '\') seg+="${line:i:2}"; i=$((i + 2)) ;;
                '`') return 1 ;;
                '$')
                    [ "${line:i+1:1}" = "(" ] && return 1
                    seg+="$c"; i=$((i + 1)) ;;
                ';'|'&'|'|')
                    cc_flush "$seg"; seg=""; i=$((i + 1)) ;;
                '#')
                    # `#` opens a comment only at the start of a word
                    if [ -z "${seg//[[:space:]]/}" ] || [ "${line:i-1:1}" = " " ] || [ "${line:i-1:1}" = $'\t' ]; then
                        i="$n"
                    else
                        seg+="$c"; i=$((i + 1))
                    fi ;;
                '<')
                    if [ "${line:i+1:1}" = "<" ]; then
                        j=$((i + 2)); d=""; q=""
                        if [ "${line:j:1}" = "-" ]; then pending_dash=1; j=$((j + 1)); else pending_dash=0; fi
                        while [ "${line:j:1}" = " " ] || [ "${line:j:1}" = $'\t' ]; do j=$((j + 1)); done
                        ch="${line:j:1}"
                        if [ "$ch" = "'" ] || [ "$ch" = '"' ]; then q="$ch"; j=$((j + 1)); fi
                        while [ "$j" -lt "$n" ]; do
                            ch="${line:j:1}"
                            if [ -n "$q" ]; then
                                if [ "$ch" = "$q" ]; then j=$((j + 1)); break; fi
                            else
                                case "$ch" in ' '|$'\t'|';'|'&'|'|'|'>'|'<') break ;; esac
                            fi
                            d+="$ch"; j=$((j + 1))
                        done
                        [ -z "$d" ] && return 1
                        pending_count=$((pending_count + 1))
                        [ "$pending_count" -gt 1 ] && return 1
                        pending_delim="$d"
                        seg+="<<"; i="$j"
                    else
                        seg+="$c"; i=$((i + 1))
                    fi ;;
                *) seg+="$c"; i=$((i + 1)) ;;
            esac
        done

        if [ "$sq" -eq 1 ] || [ "$dq" -eq 1 ]; then
            # the newline is part of the string, not the end of a command
            seg+=$'\n'
        else
            cc_flush "$seg"; seg=""
            if [ -n "$pending_delim" ]; then
                hd_delim="$pending_delim"; hd_dash="$pending_dash"; hd_active=1
            fi
        fi
    done <<EOF
$COMMAND
EOF

    # an unterminated quote means the string was not what it looked like
    { [ "$sq" -eq 1 ] || [ "$dq" -eq 1 ]; } && return 1
    # an unterminated heredoc swallows the rest of the input as body. bash does
    # treat it as data, so approving would not actually be wrong — but that
    # rests on a subtlety, and refusing costs nothing.
    [ "$hd_active" -eq 1 ] && return 1
    cc_flush "$seg"
    return 0
}

cc_scan || exit 0
[ "${#POSITIONS[@]}" -eq 0 ] && exit 0

for seg in "${POSITIONS[@]}"; do
    matched=0
    for prefix in "${SAFE_PREFIXES[@]}"; do
        if [[ "$seg" == "$prefix"* ]]; then matched=1; break; fi
    done
    [ "$matched" -eq 1 ] || exit 0
done

jq -n '{
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "multiline-command-approver: every command position matches a safe prefix"
    }
}'
exit 0
