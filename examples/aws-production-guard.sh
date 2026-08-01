#!/bin/bash
# aws-production-guard.sh — Block dangerous AWS CLI operations
#
# Prevents: Accidental deletion of production resources.
#           Blocks: aws s3 rm --recursive, aws ec2 terminate-instances,
#           aws rds delete-db-instance, aws cloudformation delete-stack
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|PowerShell"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-aws-production-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [aws-production-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check AWS CLI commands
echo "$COMMAND" | grep -qE '^\s*aws\s' || exit 0

# Block destructive operations
BLOCKED_PATTERNS=(
  "s3.*rm.*--recursive"
  "s3.*rb\s"
  "ec2.*terminate-instances"
  "rds.*delete-db"
  "cloudformation.*delete-stack"
  "lambda.*delete-function"
  "dynamodb.*delete-table"
  "iam.*delete-user"
  "iam.*delete-role"
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "aws\s+$pattern"; then
    echo "BLOCKED: Destructive AWS operation detected." >&2
    echo "  Pattern: $pattern" >&2
    echo "  Use the AWS Console for destructive operations." >&2
    exit 2
  fi
done

exit 0
