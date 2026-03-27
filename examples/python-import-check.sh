#!/bin/bash
# python-import-check.sh — Detect unused imports in Python files
#
# Prevents: Unused imports that trigger linter warnings and add
#           unnecessary dependencies. Claude often adds imports
#           during development and forgets to clean up.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

case "$FILE" in
  *.py) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE" ] && exit 0

# Quick check: find import lines and see if the imported name appears elsewhere
python3 -c "
import re, sys

with open('$FILE') as f:
    content = f.read()
    lines = content.split('\n')

imports = []
for line in lines:
    m = re.match(r'^import\s+(\w+)', line)
    if m: imports.append(m.group(1))
    m = re.match(r'^from\s+\S+\s+import\s+(.+)', line)
    if m:
        for name in m.group(1).split(','):
            name = name.strip().split(' as ')[-1].strip()
            if name and name != '*':
                imports.append(name)

unused = []
for imp in imports:
    # Count occurrences (excluding the import line itself)
    count = len(re.findall(r'\b' + re.escape(imp) + r'\b', content))
    if count <= 1:  # Only appears in the import line
        unused.append(imp)

if unused:
    print(f'Possibly unused imports in $FILE: {', '.join(unused[:5])}', file=sys.stderr)
" 2>&1

exit 0
