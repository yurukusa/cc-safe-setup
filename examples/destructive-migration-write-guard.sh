#!/bin/bash
# ================================================================
# destructive-migration-write-guard.sh — Catch a destructive
#   schema migration at the moment it is WRITTEN, before it is run
# ================================================================
# PURPOSE:
#   Every migration/schema guard in this repo (schema-migration-guard,
#   prisma-migrate-guard, drizzle-migrate-guard, django-migrate-guard,
#   rails-migration-guard, migration-safety, migration-verify-guard)
#   is a PreToolUse hook on *Bash* — it fires when the migration is
#   *executed*. subagent-blast-radius-guard fires on Edit|Write but
#   only for *sub-agent* writes and only keys off the file PATH, not
#   the content. So when the main agent (Accept Edits on) writes a
#   migration FILE that contains a destructive DDL, and that file is
#   later applied by a separate tool (Flyway, Liquibase, Alembic,
#   sqlx, a CI step), nothing inspects the destructive content at the
#   moment it is generated.
#
#   This hook closes that gap. It fires on Edit|Write (any thread —
#   main agent included), and when the file being written is a
#   migration / SQL file whose new content contains a destructive
#   operation (DROP COLUMN / DROP TABLE / ALTER ... DROP / TRUNCATE /
#   unqualified DELETE), it surfaces it — or, opt-in, blocks it —
#   before the dangerous migration file exists on disk.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"
#
# WHY THIS MATTERS:
#   #63763 (2026-05-29, unresolved) — asked only to change a one-to-one
#   relationship to one-to-many, Claude wrote a Flyway migration with
#   `ALTER TABLE ... DROP COLUMN demolition_officer_id` and NO data-
#   migration step. It was applied and a live column was lost. Accept
#   Edits was on, so the destructive file was written from the main
#   thread (subagent-blast-radius-guard would not fire), and the
#   Bash-time guards never saw the SQL because Flyway, not a shell
#   command, applied it. The only layer that could have caught it is
#   the write of the migration file itself. That is this hook.
#
# WHAT IT DOES:
#   * Looks only at writes to migration / SQL files (path heuristic
#     below). Everything else: exit 0.
#   * Extracts the new content (Write: .content; Edit: .new_string;
#     MultiEdit: every edits[].new_string) and scans it for
#     destructive DDL/DML.
#   * Applies CC_MIGRATION_WRITE_GUARD:
#       off   — do nothing (exit 0).
#       warn  — (default) print a warning to stderr, exit 0. The write
#               still happens; the operator sees what is going in.
#       block — exit 2 (block the write) when destructive content is
#               found. Use this in CI or for high-stakes repos.
#   * Recognises a same-file data-migration safeguard (an UPDATE /
#     INSERT ... SELECT / "backfill" / "data migration" alongside the
#     DROP) and downgrades the message accordingly — a DROP that is
#     paired with a backfill is the careful pattern, not the bug.
#
# CONFIG:
#   CC_MIGRATION_WRITE_GUARD     off | warn (default) | block
#   CC_MIGRATION_WRITE_PATHS     extra ERE (alternation) appended to the
#                                built-in migration-file path pattern.
#
# DESIGN NOTES:
#   * Default warn, not block: blocking a write can wedge legitimate
#     migration work and break headless/CI. Visibility is the safe
#     default; blocking is opt-in (matches subagent-blast-radius-guard
#     and memory-write-guard).
#   * Both threads, not just sub-agents: #63763 was a main-thread
#     write. The destructive-content risk is independent of who wrote
#     it, so this hook deliberately does not gate on agent_id.
#   * Edit|Write only (not Bash): destructive SQL run via a shell
#     command is already covered by schema-migration-guard et al. The
#     uncovered gap is the file write applied later by another tool.
#   * Fail-open on malformed input / missing jq: a safety hook must
#     never be the thing that breaks the session.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/63763
# ================================================================

set -u

INPUT=$(cat)

MODE="${CC_MIGRATION_WRITE_GUARD:-warn}"
[ "$MODE" = "off" ] && exit 0

# jq is required to read the structured tool input; without it, fail open.
command -v jq >/dev/null 2>&1 || exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Path heuristic: migration directories, or .sql files, or the common
# framework layouts (Flyway V/R/U prefixes, Alembic versions, Liquibase
# changelogs, Rails/Django/Prisma/Drizzle migration dirs).
MIGRATION_ERE='(^|/)migrations?/|(^|/)migrate/|(^|/)db/migrate/|\.sql$|(^|/)V[0-9].*__.*\.sql$|(^|/)alembic/versions/|(^|/)changelog/|(^|/)prisma/migrations/|(^|/)drizzle/'
if [ -n "${CC_MIGRATION_WRITE_PATHS:-}" ]; then
    MIGRATION_ERE="${MIGRATION_ERE}|${CC_MIGRATION_WRITE_PATHS}"
fi
printf '%s' "$FILE" | grep -qE "$MIGRATION_ERE" || exit 0

# Gather the content being written across Write / Edit / MultiEdit.
CONTENT=$(printf '%s' "$INPUT" | jq -r '
    [ .tool_input.content // empty,
      .tool_input.new_string // empty,
      ( .tool_input.edits // [] | map(.new_string // empty) | join("\n") )
    ] | join("\n")
' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

# Destructive DDL/DML. Mirrors schema-migration-guard's Bash-side regex
# so the write-time and run-time guards agree on what "destructive" means.
DESTRUCT=""
if printf '%s' "$CONTENT" | grep -qEi 'DROP[[:space:]]+(TABLE|COLUMN|INDEX|DATABASE|SCHEMA)'; then
    DESTRUCT="${DESTRUCT}DROP. "
fi
if printf '%s' "$CONTENT" | grep -qEi 'ALTER[[:space:]]+TABLE[^;]*DROP[[:space:]]'; then
    DESTRUCT="${DESTRUCT}ALTER ... DROP. "
fi
if printf '%s' "$CONTENT" | grep -qEi 'TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[A-Za-z_\"`]'; then
    DESTRUCT="${DESTRUCT}TRUNCATE. "
fi
# DELETE without a WHERE clause (whole-table delete).
if printf '%s' "$CONTENT" | grep -qEi 'DELETE[[:space:]]+FROM[[:space:]]+[A-Za-z_\"`][A-Za-z0-9_\".`]*[[:space:]]*;'; then
    DESTRUCT="${DESTRUCT}unqualified DELETE. "
fi

[ -z "$DESTRUCT" ] && exit 0

# Is a data-preservation step present in the same file content?
SAFEGUARD=0
if printf '%s' "$CONTENT" | grep -qEi 'INSERT[[:space:]]+INTO[^;]*SELECT|UPDATE[[:space:]]+[A-Za-z_].*SET|backfill|data[ _-]?migration|COPY[[:space:]]|CREATE[[:space:]]+TABLE[^;]*_backup'; then
    SAFEGUARD=1
fi

BASE=$(basename "$FILE")

emit() {
    echo "destructive-migration-write-guard: destructive schema change being written to $BASE" >&2
    echo "  File: $FILE" >&2
    echo "  Detected: $DESTRUCT" >&2
    if [ "$SAFEGUARD" -eq 1 ]; then
        echo "  A data-migration / backfill step appears in the same file — good. Confirm it runs BEFORE the drop and preserves the data you need." >&2
    else
        echo "  No data-migration / backfill step detected in this file." >&2
        echo "  Before this migration is applied:" >&2
        echo "    1. Back up the affected table(s)." >&2
        echo "    2. If the data must survive, add a backfill/move step that runs before the drop." >&2
        echo "    3. Write a reversible down-migration / rollback." >&2
        echo "    4. Apply on staging first; this file may be run later by Flyway/Liquibase/Alembic without another prompt." >&2
    fi
}

if [ "$MODE" = "block" ]; then
    echo "BLOCKED: refusing to write a destructive migration file ($BASE)." >&2
    emit
    echo "  Set CC_MIGRATION_WRITE_GUARD=warn to allow the write with a warning instead." >&2
    exit 2
fi

# warn (default)
emit
exit 0
