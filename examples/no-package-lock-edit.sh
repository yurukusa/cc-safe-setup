#!/bin/bash
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in */package-lock.json|*/yarn.lock|*/pnpm-lock.yaml|*/Cargo.lock)
    echo "BLOCKED: Manual lockfile edits. Use package manager instead." >&2
    exit 2 ;; esac
exit 0
