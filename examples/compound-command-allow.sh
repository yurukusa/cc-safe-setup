#!/bin/bash
# compound-command-allow.sh — Auto-approve compound commands when all parts are safe
#
# Solves: Permission prompts fire for compound commands like:
#         cd /path && git log    (#16561, 115 reactions)
#         echo foo | grep bar    (#28240, 84 reactions)
#         npm test && npm run build  (#30519, 58 reactions)
#
# How it works: Splits compound commands on &&, ||, ;, and |
#               Checks each component against a safe-command whitelist.
#               If ALL components are safe, auto-approves the entire command.
#               If ANY component is unsafe, passes through (no opinion).
#
# This extends cd-git-allow to handle arbitrary compound commands.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/compound-command-allow.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PermissionRequest  MATCHER: ""

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Strip comments (lines starting with #) to avoid false matches
CLEAN=$(echo "$COMMAND" | sed 's/#.*$//' | tr '\n' ' ')

# Split on &&, ||, ;, and | (but not || inside [[ ]])
# Simple approach: split on these operators and check each part
IFS_ORIG="$IFS"

# Replace compound operators with a delimiter
PARTS=$(echo "$CLEAN" | sed 's/\s*&&\s*/\n/g; s/\s*||\s*/\n/g; s/\s*;\s*/\n/g; s/\s*|\s*/\n/g')

ALL_SAFE=true

while IFS= read -r part; do
    # Trim whitespace
    part=$(echo "$part" | sed 's/^\s*//;s/\s*$//')
    [ -z "$part" ] && continue

    # Extract the base command (first word)
    BASE=$(echo "$part" | awk '{print $1}')

    # Check against safe command list
    case "$BASE" in
        # Navigation
        cd|pushd|popd|pwd)
            ;;
        # File reading
        cat|head|tail|less|more|wc|file|stat|du|df|ls|tree|find|which|whereis|type|realpath|readlink|basename|dirname)
            ;;
        # Text processing (read-only)
        grep|rg|ag|ack|sed|awk|sort|uniq|cut|tr|tee|xargs|column|fmt|fold|rev|nl|paste|join|comm)
            # sed with -i is NOT read-only
            if echo "$part" | grep -qE 'sed\s+.*-i'; then
                ALL_SAFE=false
                break
            fi
            ;;
        # Git (read-only operations)
        git)
            SUBCMD=$(echo "$part" | awk '{print $2}')
            case "$SUBCMD" in
                status|log|diff|show|branch|tag|remote|stash|ls-files|ls-tree|rev-parse|describe|shortlog|blame|config|worktree)
                    # git stash with push/pop/drop is not read-only
                    if echo "$part" | grep -qE 'git\s+stash\s+(push|pop|drop|apply|clear)'; then
                        ALL_SAFE=false
                        break
                    fi
                    ;;
                *)
                    ALL_SAFE=false
                    break
                    ;;
            esac
            ;;
        # Node.js/npm (read-only)
        node|npm|npx|yarn|pnpm)
            SUBCMD=$(echo "$part" | awk '{print $2}')
            case "$BASE" in
                npm)
                    case "$SUBCMD" in
                        ls|list|info|view|outdated|audit|explain|why|help|config|prefix|root)
                            ;;
                        test|run)
                            ;; # npm test/run are generally safe
                        *)
                            ALL_SAFE=false
                            break
                            ;;
                    esac
                    ;;
                node)
                    if echo "$part" | grep -qE 'node\s+-e\s'; then
                        if echo "$part" | grep -qE '(writeFile|fs\.write|unlink|rmdir|mkdirSync)'; then
                            ALL_SAFE=false
                            break
                        fi
                    elif echo "$part" | grep -qE 'node\s+-p\s'; then
                        : # node -p is safe (eval + print)
                    fi
                    ;;
                *)
                    ;; # npx, yarn, pnpm — allow for now
            esac
            ;;
        # Python (read-only)
        python|python3)
            if echo "$part" | grep -qE 'python3?\s+(-c|-m\s+(json|py_compile|compileall|ast|tokenize|dis|inspect))'; then
                : # Safe one-liners
            elif echo "$part" | grep -qE 'python3?\s+-m\s+pytest'; then
                : # pytest is safe
            else
                ALL_SAFE=false
                break
            fi
            ;;
        # Shell builtins (safe)
        echo|printf|true|false|test|\[|export|set|env|printenv|date|sleep|read|source|\.)
            ;;
        # System info
        uname|hostname|whoami|id|groups|uptime|free|top|ps|lsb_release|arch|nproc|getconf)
            ;;
        # JSON/YAML processing
        jq|yq)
            ;;
        # curl (GET only)
        curl)
            if echo "$part" | grep -qE '\s-X\s+(POST|PUT|PATCH|DELETE)'; then
                ALL_SAFE=false
                break
            fi
            ;;
        # mkdir is generally safe
        mkdir)
            ;;
        # touch is generally safe
        touch)
            ;;
        *)
            ALL_SAFE=false
            break
            ;;
    esac
done <<< "$PARTS"

IFS="$IFS_ORIG"

if [ "$ALL_SAFE" = true ]; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"All components of compound command are safe"}}'
    exit 0
fi

# Unsafe component found — no opinion, let default handler decide
exit 0
