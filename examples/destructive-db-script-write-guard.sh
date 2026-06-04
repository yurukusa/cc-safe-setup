#!/bin/bash
# ================================================================
# destructive-db-script-write-guard.sh — Catch a destructive
#   DB operation written into an application SCRIPT, before the
#   script is ever run
# ================================================================
# PURPOSE:
#   block-database-wipe, db-connect-guard and env-prod-guard are all
#   PreToolUse hooks on *Bash* — they scan the shell command. They
#   catch `psql ... DROP DATABASE`, `rails db:drop`, `mysql -h host`,
#   etc. They do NOT catch a destructive statement that lives inside
#   an application script and is launched by a generic runtime: when
#   the agent writes `cleanup.js` containing `DELETE FROM` for every
#   table and then runs `node cleanup.js`, the Bash command is just
#   `node cleanup.js` — no DROP/DELETE/host string for the Bash guards
#   to see. subagent-blast-radius-guard fires on Edit|Write but keys
#   off the file PATH (a root-level `cleanup.js` is not a "sensitive
#   path") and never reads the content.
#
#   This hook closes that gap. It fires on Edit|Write (any thread —
#   sub-agents included) and reads the script content being written.
#   If that content contains a destructive DB operation (unqualified
#   DELETE / TRUNCATE / DROP TABLE|DATABASE|SCHEMA), it surfaces it —
#   or, opt-in, blocks the write — before the script exists to be run.
#   When the same content also carries a production-looking DB target,
#   it says so (that combination is the one that loses real data).
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"
#
# WHY THIS MATTERS:
#   #64056 (2026-05-30, unresolved) — a sub-agent, to "test" reset
#   logic, wrote debug-check2.js containing `DELETE FROM` across every
#   table and ran it with node. The project's .env had production
#   (Aiven) credentials uncommented, the ad-hoc script loaded env on
#   its own (bypassing the repo's _test-only guardrail), and a real
#   customer's production database was lost. None of the Bash-time DB
#   guards saw it (the command was just `node ...`), and the path-based
#   sub-agent guard did not flag a root-level .js. The only layer that
#   could have caught it is the write of the script itself.
#
# WHAT IT DOES:
#   * Looks only at writes to executable/script files (.js .mjs .cjs
#     .ts .py .rb .php .go .java .sh .ps1 ...). SQL files / migrations
#     are intentionally left to destructive-migration-write-guard.
#   * Extracts the new content (Write .content; Edit .new_string;
#     MultiEdit edits[].new_string) and looks for destructive raw SQL:
#       - DELETE FROM <table> with no WHERE (whole-table delete)
#       - TRUNCATE
#       - DROP TABLE | DATABASE | SCHEMA
#   * If found, checks the same content for a production-looking target
#     (remote host / known managed-DB providers / a DB URL pulled from
#     the environment) and adds that to the message.
#   * Applies CC_DB_SCRIPT_WRITE_GUARD: off | warn (default) | block.
#   * If the write came from a sub-agent (agent_id present), says so —
#     sub-agent writes are the ones operators see too late (#64056 #4).
#
# CONFIG:
#   CC_DB_SCRIPT_WRITE_GUARD     off | warn (default) | block
#   CC_DB_SCRIPT_WRITE_EXT       extra ERE (alternation) of file
#                                extensions to also treat as scripts
#
# DESIGN NOTES:
#   * Default warn, not block: a write-blocking hook must not wedge
#     legitimate work or break headless/CI. Visibility is the safe
#     default; blocking is opt-in (matches the other write-time guards
#     in this repo).
#   * Requires an UNQUALIFIED delete (DELETE FROM ... ; with no WHERE)
#     so ordinary `DELETE FROM t WHERE ...` in normal code does not
#     trip it. Reduces false positives sharply.
#   * Both threads, not just sub-agents: the risk is in the content,
#     not the author. agent_id only changes the wording.
#   * Fail-open on malformed input / missing jq.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/64056
# ================================================================

set -u

INPUT=$(cat)

MODE="${CC_DB_SCRIPT_WRITE_GUARD:-warn}"
[ "$MODE" = "off" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Script/executable files only. SQL & migrations are handled by
# destructive-migration-write-guard, so skip them here.
case "$FILE" in
    *.sql) exit 0 ;;
esac
SCRIPT_ERE='\.(js|mjs|cjs|jsx|ts|tsx|py|rb|php|go|java|kt|cs|rs|sh|bash|ps1|pl)$'
if [ -n "${CC_DB_SCRIPT_WRITE_EXT:-}" ]; then
    SCRIPT_ERE="${SCRIPT_ERE}|${CC_DB_SCRIPT_WRITE_EXT}"
fi
printf '%s' "$FILE" | grep -qE "$SCRIPT_ERE" || exit 0

CONTENT=$(printf '%s' "$INPUT" | jq -r '
    [ .tool_input.content // empty,
      .tool_input.new_string // empty,
      ( .tool_input.edits // [] | map(.new_string // empty) | join("\n") )
    ] | join("\n")
' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

DESTRUCT=""
# Unqualified DELETE: DELETE FROM <name> with no WHERE before the
# statement terminator (; , end of quote, or end of line).
if printf '%s' "$CONTENT" | grep -qEi 'DELETE[[:space:]]+FROM[[:space:]]+[`"'"'"']?[A-Za-z_][A-Za-z0-9_.]*[`"'"'"']?[[:space:]]*(;|"|'"'"'|$)'; then
    DESTRUCT="${DESTRUCT}unqualified DELETE FROM (whole-table delete). "
fi
if printf '%s' "$CONTENT" | grep -qEi 'TRUNCATE([[:space:]]+TABLE)?[[:space:]]+[`"'"'"']?[A-Za-z_]'; then
    DESTRUCT="${DESTRUCT}TRUNCATE. "
fi
if printf '%s' "$CONTENT" | grep -qEi 'DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)[[:space:]]'; then
    DESTRUCT="${DESTRUCT}DROP TABLE/DATABASE/SCHEMA. "
fi

[ -z "$DESTRUCT" ] && exit 0

# Production-looking target in the same script? (the lethal combination)
PROD=0
if printf '%s' "$CONTENT" | grep -qiE 'aiven|\.rds\.amazonaws\.com|supabase\.co|neon\.tech|\.render\.com|planetscale|mongodb\+srv|amazonaws\.com|azure\.com|\.cloud:|DATABASE_URL|PROD_DATABASE|PRODUCTION'; then
    PROD=1
fi
# Does it pull a connection target from the environment rather than a
# hard-coded localhost? (the #64056 "loaded env on its own" pattern)
ENVCONN=0
if printf '%s' "$CONTENT" | grep -qiE 'process\.env\.[A-Z_]*(DB|DATABASE|PG|MYSQL|MONGO)|os\.environ\[[^]]*(DB|DATABASE)|getenv\([^)]*(DB|DATABASE)'; then
    ENVCONN=1
fi

AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
BASE=$(basename "$FILE")
WHO="this write"
[ -n "$AGENT_ID" ] && WHO="a sub-agent ($(printf '%s' "$AGENT_ID" | cut -c1-8))"

emit() {
    echo "destructive-db-script-write-guard: $WHO is writing a destructive DB operation into $BASE" >&2
    echo "  File: $FILE" >&2
    echo "  Detected: $DESTRUCT" >&2
    if [ "$PROD" -eq 1 ]; then
        echo "  ! The script also references a production-looking database target. This is the combination that loses real data (#64056)." >&2
    fi
    if [ "$ENVCONN" -eq 1 ]; then
        echo "  ! It builds the DB connection from environment variables, so it can hit whatever .env currently points at — including production." >&2
    fi
    echo "  Before this script is run:" >&2
    echo "    1. Never point an ad-hoc delete/reset script at a target loaded from .env; pin it to a local/test DB with an explicit test marker." >&2
    echo "    2. Add a WHERE clause, or guard the script so it refuses any non-localhost / non-_test target." >&2
    echo "    3. Back up first; destructive runs against live data are irreversible." >&2
}

if [ "$MODE" = "block" ]; then
    echo "BLOCKED: refusing to write a script containing a destructive DB operation ($BASE)." >&2
    emit
    echo "  Set CC_DB_SCRIPT_WRITE_GUARD=warn to allow the write with a warning instead." >&2
    exit 2
fi

emit
exit 0
