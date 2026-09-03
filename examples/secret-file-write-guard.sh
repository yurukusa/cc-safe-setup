#!/bin/bash
# ================================================================
# secret-file-write-guard.sh — Block writing to secret files via Bash
# ================================================================
# PURPOSE:
#   The bundled Write|Edit guard blocks writing to .env, private keys
#   and credential files. It cannot see the same write done through
#   Bash, because Bash hooks receive a command string, not a file_path.
#
#   So today the same intent stops or passes depending on the route:
#
#     Write tool  -> ~/app/.env          BLOCKED by the bundled guard
#     cp k.env ~/app/.env                passes
#     sed -i 's/A/B/' ~/app/.env         passes
#     printf '%s' "$K" >> ~/app/.env     passes
#     curl -s https://x/k -o ~/app/.env  passes
#
#   Measured on 2026-09-04 against all 914 example hooks: zero of them
#   target these forms. The private-key copy is covered by
#   ssh-key-protect.sh, and `git add .env` by dotenv-commit-guard.sh;
#   the write itself was not covered anywhere.
#
#   This matters more since 2026-08-14, when Claude Code began telling
#   some sessions to prefer Bash over the Read/Edit/Write tools
#   (feature flag bashActFirstEnabled; assignment is per session, so
#   "it does not happen here" is not evidence it does not happen).
#   In my own transcripts, file edits made through Bash went from
#   40.5% to 64.2% across that date, on a near-identical volume.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# DECISION: exit 2 = block. This is a "stop and confirm" guard, not a
#   ban: creating a .env from .env.example is allowed, and so is
#   reading. Only writes into a secret file are stopped.
# ================================================================

if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-secret-file-write-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [secret-file-write-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# A path that names a secret file. Templates are deliberately excluded:
# `cp .env.example .env` is how projects are normally set up.
SECRET='(\.env(\.[A-Za-z0-9_-]+)?|[A-Za-z0-9_.-]+\.(pem|key|p12|pfx)|id_rsa|id_ed25519|credentials|secrets?\.(json|ya?ml|txt)|\.netrc|\.npmrc)'
TEMPLATE='\.env\.(example|sample|template|dist)'

is_template_target() {
  # true when the ONLY secret-looking token being written to is a template
  printf '%s' "$1" | grep -qE "$TEMPLATE\s*$"
}

block() {
  echo "BLOCKED: writing to a secret file through Bash ($1). Check if this is intentional." >&2
  echo "         The bundled Write|Edit guard cannot see Bash writes; this hook covers that gap." >&2
  exit 2
}

# 1. Redirection into a secret file:  > .env   >> ~/app/.env   >| ~/app/.env
TARGET=$(printf '%s' "$COMMAND" | grep -oE '>>?\|?[[:space:]]*[^|;&[:space:]]+' | tail -1 | sed -E 's/^>>?\|?[[:space:]]*//')
if [ -n "$TARGET" ] && printf '%s' "$TARGET" | grep -qE "$SECRET" && ! printf '%s' "$TARGET" | grep -qE "$TEMPLATE"; then
  block "redirect"
fi

# 2. tee into a secret file
if printf '%s' "$COMMAND" | grep -qE "\btee\b([[:space:]]+-[A-Za-z]+)*[[:space:]]+[^|;&[:space:]]*$SECRET" \
   && ! printf '%s' "$COMMAND" | grep -qE "\btee\b[^|;&]*$TEMPLATE"; then
  block "tee"
fi

# 3. in-place edit:  sed -i ... .env   perl -i ... .env
if printf '%s' "$COMMAND" | grep -qE '\b(sed|perl)\b[^|;&]*[[:space:]]-i' \
   && printf '%s' "$COMMAND" | grep -qE "$SECRET" \
   && ! printf '%s' "$COMMAND" | grep -qE "$TEMPLATE"; then
  block "in-place edit"
fi

# 4. copy/move INTO a secret file (the destination is the last argument).
#    `cp .env.example .env` is how projects are set up, so the SOURCE is
#    checked too: copying a template into place is allowed, copying a real
#    secret file into a new location is not.
if printf '%s' "$COMMAND" | grep -qE '\b(cp|mv|install|rsync|scp)\b'; then
  FIRST=$(printf '%s' "$COMMAND" | sed -E 's/[|;&].*$//')
  DEST=$(printf '%s' "$FIRST" | awk '{print $NF}')
  SRC=$(printf '%s' "$FIRST" | awk 'NF>2 {print $(NF-1)}')
  if printf '%s' "$DEST" | grep -qE "$SECRET" && ! printf '%s' "$DEST" | grep -qE "$TEMPLATE"; then
    if ! printf '%s' "$SRC" | grep -qE "$TEMPLATE"; then
      block "copy/move into"
    fi
  fi
fi

# 5. write straight into a secret file via an option:
#    curl -o .env / wget -O .env / dd of=.env / openssl -out .env
# Longest option first: alternation is tried left to right, so `-o` placed
# before `-out` would match the `-o` of `-out` and capture "ut <path>".
OPT=$(printf '%s' "$COMMAND" | grep -oE '(--output-document|--output|-out|-o|-O)[[:space:]=]+[^|;&[:space:]]+|\bof=[^|;&[:space:]]+' | tail -1)
if [ -n "$OPT" ] && printf '%s' "$OPT" | grep -qE "$SECRET" && ! printf '%s' "$OPT" | grep -qE "$TEMPLATE"; then
  block "write via option"
fi

# 6. replace or empty a secret file without writing content into it:
#    truncate -s 0 .env / ln -sf other .env
if printf '%s' "$COMMAND" | grep -qE '\b(truncate|ln)\b'; then
  LAST=$(printf '%s' "$COMMAND" | sed -E 's/[|;&].*$//' | awk '{print $NF}')
  if printf '%s' "$LAST" | grep -qE "$SECRET" && ! printf '%s' "$LAST" | grep -qE "$TEMPLATE"; then
    block "truncate/symlink"
  fi
fi

# ── Known limits (deliberately not claimed as complete) ───────────
# A write performed *inside* an interpreter is invisible here, because the
# command string carries the program, not the file operation:
#     python3 -c "open('.env','w').write(k)"
#     node -e "require('fs').writeFileSync('.env', k)"
# The same is true of any wrapper script that decides the path at runtime.
# Measured on 2026-09-04 against 46 forms in total: 29 (12 that must block,
# 17 that must pass) plus 17 sibling forms. It stops every form except the
# two interpreter ones above, and raises no false positive on the 17 that
# must pass. That is a count, not a guarantee: forms absent from the table
# were never tested. If the interpreter route matters to you,
# pair this with permissions.deny on the paths themselves, which is enforced
# by the tool layer rather than by string matching.
exit 0
