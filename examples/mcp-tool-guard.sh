#!/bin/bash
#
# mcp-tool-guard.sh — Guard destructive / side-effecting MCP tool calls.
#
# TRIGGER: PreToolUse
# MATCHER: ".*"   (fires on every tool; the hook self-filters to mcp__ tools.
#                  NOTE: the previous "Bash" matcher was wrong — a Bash matcher
#                  never sees an mcp__ tool name, so the hook never fired.)
#
# Why this exists: an MCP tool can perform a destructive action whose tool NAME
#   looks harmless. The clearest case is browser automation: a model in an
#   auto-approve mode calls e.g. mcp__playwright__browser_click on a "delete"
#   confirmation button and removes production data with no prompt (anthropics/
#   claude-code#65563). The tool name ("browser_click") contains no destructive
#   word, so name-based detection alone misses it.
#
# CONFIG (all opt-in; defaults preserve the original warn-only behavior):
#   CC_MCP_WARN_ALL=1            Log every MCP tool call.
#   CC_MCP_BLOCKED_TOOLS="a,b"   Hard-block (exit 2) MCP tools matching these.
#   CC_MCP_PROD_HOSTS="h1,h2"    Deny any MCP call whose input references these
#                                 hosts/paths. Reliable for browser navigate
#                                 (the target URL is in tool_input) — keeps an
#                                 "investigation" from reaching production.
#   CC_MCP_AUTOMATION_GUARD=off|warn|ask|block   (default: warn)
#                                 How to treat automation tools (click/navigate/
#                                 fill/type/...) while a permission mode is
#                                 auto-approving. warn=stderr note; ask=prompt;
#                                 block=exit 2. Addresses #65563's root cause.
#   CC_MCP_AUTOMATION_TOOLS="click,navigate,fill,type,press,submit,upload"
#                                 Tool-name substrings treated as automation.
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-mcp-tool-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [mcp-tool-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
echo "$TOOL" | grep -q '^mcp__' || exit 0
MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)
INPUT_BLOB=$(echo "$INPUT" | jq -r '.tool_input | tostring' 2>/dev/null)
if [ "${CC_MCP_WARN_ALL:-0}" = "1" ]; then
    echo "NOTE: MCP tool call: $TOOL" >&2
fi
BLOCKED="${CC_MCP_BLOCKED_TOOLS:-}"
if [ -n "$BLOCKED" ]; then
    IFS=',' read -ra PATTERNS <<< "$BLOCKED"
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs)  # trim whitespace
        if [[ "$TOOL" == *"$pattern"* ]]; then
            echo "BLOCKED: MCP tool $TOOL matches blocked pattern: $pattern" >&2
            exit 2
        fi
    done
fi

# Deny any MCP call that references a configured production host/path. For
# browser navigate tools the destination URL is in tool_input, so this reliably
# stops an "investigation" session from reaching production data.
PROD="${CC_MCP_PROD_HOSTS:-}"
if [ -n "$PROD" ] && [ -n "$INPUT_BLOB" ]; then
    IFS=',' read -ra HOSTS <<< "$PROD"
    for h in "${HOSTS[@]}"; do
        h=$(echo "$h" | xargs)
        [ -z "$h" ] && continue
        if printf '%s' "$INPUT_BLOB" | grep -qiF "$h"; then
            printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"MCP tool %s targets a production host (%s). Investigate against staging/local, not production."}}\n' "$TOOL" "$h"
            exit 0
        fi
    done
fi

# #65563: while a permission mode is auto-approving, an automation tool can
# perform a destructive UI action (e.g. clicking a delete button) that the tool
# name does not reveal. Escalate such tools so a click cannot auto-run.
GUARD="${CC_MCP_AUTOMATION_GUARD:-warn}"
if [ "$GUARD" != "off" ]; then
    case "$MODE" in
        acceptEdits|bypassPermissions|auto|dontAsk)
            AUTOM="${CC_MCP_AUTOMATION_TOOLS:-click,navigate,fill,type,press,submit,upload}"
            IFS=',' read -ra ATOOLS <<< "$AUTOM"
            for a in "${ATOOLS[@]}"; do
                a=$(echo "$a" | xargs)
                [ -z "$a" ] && continue
                if [[ "$TOOL" == *"$a"* ]]; then
                    case "$GUARD" in
                        # CAUTION: under bypassPermissions an "ask" decision is
                        # silently auto-approved (#77212) — the very mode this
                        # branch fires in. Use CC_MCP_AUTOMATION_GUARD=block to
                        # actually enforce under auto-approve modes.
                        ask)
                            printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Confirm MCP automation action %s — permission mode %s is auto-approving."}}\n' "$TOOL" "$MODE"
                            exit 0 ;;
                        block)
                            echo "BLOCKED: MCP automation tool $TOOL under auto-approve mode $MODE. Re-run in default mode so the action is confirmed." >&2
                            exit 2 ;;
                        *)
                            echo "WARNING: MCP automation tool $TOOL is running under auto-approve mode $MODE — a UI action could change data without a prompt." >&2 ;;
                    esac
                    break
                fi
            done
            ;;
    esac
fi

case "$TOOL" in
    *delete*|*remove*|*drop*|*destroy*|*purge*)
        echo "WARNING: Potentially destructive MCP tool: $TOOL" >&2
        ;;
    *send_email*|*send_message*|*post*|*publish*)
        echo "WARNING: MCP tool with external side effects: $TOOL" >&2
        ;;
esac
exit 0
