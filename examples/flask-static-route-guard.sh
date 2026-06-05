#!/bin/bash
# ================================================================
# flask-static-route-guard.sh — Warn when a catch-all static
# route would expose .env / .git / source / db files to the web
#
# Solves: Claude routinely recommends a Flask catch-all static
# route that serves the application's own directory, so anyone can
# request /.env, /.git/config, /app.py, /data.db over the public
# web and receive secrets, source, and databases. Reported in
# anthropics/claude-code#65517.
#
# The dangerous shape (all three together):
#   1. a catch-all route capturing an arbitrary path  (<path:...>)
#   2. a send_from_directory()/send_file() call
#   3. serving from the app/module dir or cwd  (dirname(__file__),
#      os.getcwd(), '.') with no static-subdir scoping and no
#      dotfile guard
#
# This is a WARNING, not a block — Claude can still write the code,
# but the operator (and Claude) see the exposure and the fix before
# it ships. Heuristic by design; it stays quiet when a mitigation
# (a dedicated static/ subdir, secure_filename, or an explicit
# dotfile/.env rejection) is present.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Edit|Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/flask-static-route-guard.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
# Only Python files can host a Flask route. Skip anything else.
case "$FILE" in
  *.py) ;;
  "" ) ;;          # some Edit payloads omit file_path; still scan content
  *) exit 0 ;;
esac

# Content of the write: Write uses .content, Edit uses .new_string.
CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)
[[ -z "$CONTENT" ]] && exit 0

# 1. catch-all path capture (Flask's <path:...> converter)
echo "$CONTENT" | grep -qE '<path:[A-Za-z_][A-Za-z0-9_]*>' || exit 0

# 2. a file-serving call
echo "$CONTENT" | grep -qE 'send_from_directory\(|send_file\(' || exit 0

# 3. served base is the app dir or cwd (the exposure), not a scoped subdir
echo "$CONTENT" | grep -qE "dirname\(__file__\)|abspath\(__file__\)|os\.getcwd\(\)|send_from_directory\([[:space:]]*['\"]\.?['\"]" || exit 0

# Suppress when a clear mitigation is present:
#  - serving from a dedicated static/templates/public/assets subdir
#  - secure_filename() sanitisation
#  - an explicit rejection of dotfiles / .env
if echo "$CONTENT" | grep -qE "secure_filename\(|send_from_directory\(.*['\"](static|templates|public|assets|dist|build)['\"]|os\.path\.join\(.*['\"](static|templates|public|assets|dist|build)['\"]"; then
  exit 0
fi
if echo "$CONTENT" | grep -qE "startswith\(['\"]\.['\"]\)|['\"]\.env['\"]|['\"]\.git['\"]|\babort\(40[34]\)" ; then
  # The code already reasons about dotfiles / blocks paths — assume guarded.
  exit 0
fi

echo "WARNING: This Flask catch-all route serves the app's own directory to the web." >&2
echo "Anyone can request /.env, /.git/config, /*.py, or /*.db and receive secrets," >&2
echo "source code, and databases (anthropics/claude-code#65517)." >&2
echo "Fix: serve only a dedicated subdirectory and reject dotfiles, e.g." >&2
echo "  STATIC_DIR = os.path.join(os.path.dirname(__file__), 'static')" >&2
echo "  if not path or path.startswith('.') or '..' in path: abort(404)" >&2
echo "  return send_from_directory(STATIC_DIR, path)" >&2
echo "Never serve the directory that contains .env, .git, or source files." >&2

exit 0
