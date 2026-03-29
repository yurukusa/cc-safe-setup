#!/bin/bash
# prefer-builtin-tools.sh — Deny bash commands that have dedicated built-in tool equivalents
# PreToolUse hook (matcher: Bash)
# Solves: https://github.com/anthropics/claude-code/issues/19649 (48+ reactions)
#
# Claude Code has built-in Read, Edit, Grep, Glob tools that are faster and safer
# than bash equivalents. But Claude often reaches for sed, grep, cat instead.
# This hook denies those commands with a pointer to the correct built-in tool.
#
# TRIGGER: PermissionRequest  MATCHER: ""

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Check all segments of piped/chained commands
while IFS= read -r segment; do
  cmd=$(echo "$segment" | sed 's/^[[:space:]]*//' | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^ ]* //')
  base=$(basename "$(echo "$cmd" | awk '{print $1}')" 2>/dev/null)
  case "$base" in
    cat)      msg="Use the Read tool to read files, or Write to create them" ;;
    head|tail) msg="Use the Read tool with offset/limit parameters" ;;
    sed)      msg="Use the Edit tool for modifications, or Read for viewing line ranges" ;;
    awk)      msg="Use Read, Grep, or Edit tools instead" ;;
    grep|rg)  msg="Use the built-in Grep tool (supports -A/-B/-C context, glob filters, output_mode)" ;;
    find)     msg="Use the built-in Glob tool for file pattern matching" ;;
    *)        continue ;;
  esac
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not use \`$base\`. $msg"}}
EOF
  exit 0
done < <(echo "$COMMAND" | tr '|' '\n' | sed 's/[;&]\{1,2\}/\n/g')

exit 0
