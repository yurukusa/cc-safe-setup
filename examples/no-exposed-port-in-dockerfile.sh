#!/bin/bash
# no-exposed-port-in-dockerfile.sh — Warn about exposing port 22 in Dockerfile
#
# Prevents: Exposing SSH port in containers (security risk).
#           Also warns about port 3306 (MySQL) and 5432 (PostgreSQL).
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

BASENAME=$(basename "$FILE")
case "$BASENAME" in
  Dockerfile|Dockerfile.*|*.dockerfile) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE" ] && exit 0

# Check for dangerous exposed ports
DANGEROUS_PORTS="22|3306|5432|27017|6379|11211"
EXPOSED=$(grep -iE "^EXPOSE\s+($DANGEROUS_PORTS)" "$FILE" | head -3)

if [ -n "$EXPOSED" ]; then
  echo "WARNING: Sensitive ports exposed in Dockerfile:" >&2
  echo "$EXPOSED" | sed 's/^/  /' >&2
  echo "  22=SSH, 3306=MySQL, 5432=PostgreSQL, 27017=MongoDB, 6379=Redis" >&2
fi

exit 0
