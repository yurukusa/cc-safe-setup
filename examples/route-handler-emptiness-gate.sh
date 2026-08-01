#!/bin/bash
# route-handler-emptiness-gate.sh — Refuse Write/Edit when a route handler method
# body would ship with the surface form of a handler (auth + redirect + return)
# but with no data-mutation line (no save, update, create, insert, delete).
#
# Solves: anthropics/claude-code #61107 — "Opus 4.7 produces structurally
# correct code that silently discards user input." The four documented cases
# in that issue body share a shape: signature correct, auth check correct,
# redirect correct, the one line that materializes the side effect missing.
# A code review at a glance passes; the patient's reflection is silently
# discarded; the DELETE returns 200 with the row still present.
#
# RUSE Surface application: the operator's intent ("a route handler must
# materialize the request's effect on persistent state") is a wider semantic
# surface than any single deny rule or naming convention. The model honours
# the convention's named exemplars (handler signature, auth, redirect, route
# name) while skipping the rule's synonymous edge (the data-mutation line).
# This hook gates against the effect predicate (must contain a mutation),
# not against the surface convention (must look like a handler).
#
# TRIGGER: PreToolUse
# MATCHER: Write|Edit|MultiEdit
#
# SCOPE: PHP files only by default (the documented case is Laravel). Set
# CC_HANDLER_GATE_LANGUAGES to a comma-separated list to add languages
# (currently supported: php).
#
# MODE:
#   advisory (default) — emits a system-reminder, allows the write
#   strict             — exits 2, refuses the write
#
# CONFIGURATION:
#   CC_HANDLER_GATE_MODE       advisory | strict        (default: advisory)
#   CC_HANDLER_GATE_LANGUAGES  comma-separated list     (default: php)
#   CC_HANDLER_GATE_PATHS      regex of paths to gate   (default: /[Cc]ontrollers?/)
#   CC_HANDLER_GATE_DISABLE    set to "1" to disable    (default: unset)
#
# DETECTION HEURISTIC (PHP / Laravel):
#   A method body is flagged if ALL of:
#     - The method body contains at least one of:
#         auth(), Auth::, $request->user(), redirect(, return redirect(,
#         response()->json(, return response()
#     AND
#     - The method body contains NONE of:
#         ->save(, ::create(, ->update(, ::insert(, ->delete(, ::firstOrCreate(,
#         ::updateOrCreate(, ->fill(, DB::table(, DB::insert, DB::update,
#         DB::delete, Eloquent::, ->push(, ->associate(, ->detach(, ->sync(
#     AND
#     - The method body contains no PHP-side function call that names
#       something like Service, Repository, Action (heuristic for service-
#       layer pattern where the mutation is delegated)
#
# RELATED ISSUES:
#   anthropics/claude-code #61107 (@nvst18, 2026-05-21) — direct motivation
#   anthropics/claude-code #60226 (@suwayama, 2026-05-18) — structural parent
#   anthropics/claude-code #60977 (@beq00000, 2026-05-20) — RUSE articulation
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Write|Edit|MultiEdit",
#           "hooks": [{"type":"command","command":"~/.claude/hooks/route-handler-emptiness-gate.sh"}]
#         }
#       ]
#     }
#   }

set -euo pipefail

# Bail if disabled
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-route-handler-emptiness-gate-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [route-handler-emptiness-gate]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

if [ "${CC_HANDLER_GATE_DISABLE:-}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)

MODE="${CC_HANDLER_GATE_MODE:-advisory}"
LANGUAGES="${CC_HANDLER_GATE_LANGUAGES:-php}"
PATH_REGEX="${CC_HANDLER_GATE_PATHS:-/[Cc]ontrollers?/}"

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in
    Write|Edit|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Language and path gating
case "$FILE_PATH" in
    *.php) ;;
    *) exit 0 ;;
esac

# Only run if the path matches the configured controller-path regex
if ! echo "$FILE_PATH" | grep -qE "$PATH_REGEX"; then
    exit 0
fi

# Extract the content the model is about to write
CONTENT=$(echo "$INPUT" | jq -r '
    .tool_input.content //
    .tool_input.new_string //
    (if .tool_input.edits then (.tool_input.edits | map(.new_string) | join("\n")) else empty end) //
    empty
' 2>/dev/null)

[ -z "$CONTENT" ] && exit 0

# Detection: look for PHP method bodies and check each one.
# This is a regex-based heuristic; a full PHP AST is out of scope for a bash hook.
# The trade is documented in the methodology note — heuristic-with-false-positive-surface,
# not strict parsing.

# Extract candidate method bodies using a Python helper for reliability
FLAGGED=$(python3 - "$CONTENT" <<'PYEOF'
import sys, re

content = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()

# Find PHP method definitions: public/protected function name(...) { ... }
# We use a non-greedy match for the method body, but PHP can have nested braces,
# so we use a brace-counting approach.

method_re = re.compile(
    r'(public|protected|private)\s+function\s+(\w+)\s*\([^)]*\)\s*(?::\s*[\w\\]+\s*)?\{',
    re.MULTILINE
)

# Patterns that indicate "looks like a handler" (HTTP-shaped activity)
HANDLER_LIKE = [
    r'auth\(\)',
    r'Auth::',
    r'\$request->user\(\)',
    r'redirect\s*\(',
    r'response\(\)',
    r'return\s+view\(',
    r'->json\(',
]

# Patterns that indicate "data mutation actually happens"
MUTATION = [
    r'->save\(',
    r'::create\(',
    r'->update\(',
    r'::insert\(',
    r'->delete\(',
    r'::firstOrCreate\(',
    r'::updateOrCreate\(',
    r'->fill\(',
    r'DB::table\(',
    r'DB::insert',
    r'DB::update',
    r'DB::delete',
    r'->push\(',
    r'->associate\(',
    r'->detach\(',
    r'->sync\(',
    r'->touch\(',
    r'->forceDelete\(',
]

# Service/Action/Repository delegation pattern (mutation may be delegated)
SERVICE_DELEGATION = [
    r'\$\w*[Ss]ervice\b',
    r'\$\w*[Rr]epository\b',
    r'\$\w*[Aa]ction\b',
    r'\$\w*[Hh]andler\b',
    r'->dispatch\(',
    r'::dispatch\(',          # Job::dispatch() static call
    r'->execute\(',
    r'->perform\(',
    r'->store\(\s*\$',        # Service store with parameter
    r'->handle\(\s*\$',
    r'event\s*\(\s*new\s+',   # event(new MyEvent()) dispatches listeners
    r'->notify\(',            # Notification::send() / $user->notify(...)
    r'Notification::send\(',
    r'broadcast\s*\(',        # broadcast(new MyEvent())
]

# Exempt method names that legitimately don't mutate
READ_ONLY_NAMES = {
    'index', 'show', 'view', 'create', 'edit',  # standard CRUD read methods
    'get', 'list', 'find', 'search', 'fetch',
    '__construct', '__destruct', '__invoke', 'rules', 'authorize',
    'middleware', 'register', 'boot',
}

# Mutating method names where emptiness is suspicious
MUTATING_NAMES = {
    'store', 'update', 'destroy', 'delete',
    'patch', 'put', 'restore', 'archive',
    'attach', 'detach', 'sync', 'associate',
    'process', 'handle', 'execute', 'perform',
    'save', 'submit', 'send', 'publish',
}

def has_pattern(body, patterns):
    return any(re.search(p, body) for p in patterns)

def extract_body(text, start_pos):
    """Brace-match from text[start_pos] (which should be after the opening {)."""
    depth = 1
    i = start_pos
    while i < len(text) and depth > 0:
        # Skip strings naively
        c = text[i]
        if c == '"' or c == "'":
            quote = c
            i += 1
            while i < len(text) and text[i] != quote:
                if text[i] == '\\':
                    i += 2
                else:
                    i += 1
            i += 1
        elif c == '/' and i + 1 < len(text) and text[i+1] == '/':
            # line comment
            while i < len(text) and text[i] != '\n':
                i += 1
        elif c == '/' and i + 1 < len(text) and text[i+1] == '*':
            i += 2
            while i + 1 < len(text) and not (text[i] == '*' and text[i+1] == '/'):
                i += 1
            i += 2
        elif c == '{':
            depth += 1
            i += 1
        elif c == '}':
            depth -= 1
            i += 1
        else:
            i += 1
    return text[start_pos:i-1] if depth == 0 else text[start_pos:]

flags = []
for m in method_re.finditer(content):
    visibility = m.group(1)
    name = m.group(2)
    body_start = m.end()
    body = extract_body(content, body_start)

    # Skip very short bodies (likely abstract/interface stubs) and empty constructors
    if len(body.strip()) < 3:
        continue

    # Read-only method names are exempt
    if name in READ_ONLY_NAMES:
        continue

    # Method names that should mutate get extra scrutiny: flag emptiness if no mutation
    is_mutating_name = name in MUTATING_NAMES

    looks_like_handler = has_pattern(body, HANDLER_LIKE)
    has_mutation = has_pattern(body, MUTATION)
    has_service = has_pattern(body, SERVICE_DELEGATION)

    if is_mutating_name and not has_mutation and not has_service:
        flags.append({
            'method': name,
            'visibility': visibility,
            'reason': f'mutating-named method ({name!r}) has no data-mutation call and no service delegation'
        })
    elif looks_like_handler and not has_mutation and not has_service:
        # Handler-shape body without mutation: flag with lower severity
        flags.append({
            'method': name,
            'visibility': visibility,
            'reason': f'handler-shape method ({name!r}) has no data-mutation call and no service delegation'
        })

for f in flags:
    print(f"{f['visibility']}|{f['method']}|{f['reason']}")
PYEOF
)

if [ -z "$FLAGGED" ]; then
    exit 0
fi

# Build the warning message
{
    echo "⚠️ route-handler-emptiness-gate: detected $(echo "$FLAGGED" | wc -l) method(s) with handler shape but no data mutation:"
    echo ""
    echo "$FLAGGED" | while IFS='|' read -r vis name reason; do
        echo "  - $vis function $name(): $reason"
    done
    echo ""
    echo "Reference: anthropics/claude-code#61107 — the four documented failure cases in"
    echo "@nvst18's report share this shape (storeResearchReflection, destroy(),"
    echo "validate-without-capture, dead conditionals)."
    echo ""
    echo "File: $FILE_PATH"
    echo "Mode: $MODE"
    echo ""
    if [ "$MODE" = "strict" ]; then
        echo "Refusing write. To override for this turn, set CC_HANDLER_GATE_MODE=advisory."
    else
        echo "Allowing write (advisory). Set CC_HANDLER_GATE_MODE=strict to block."
        echo "If the method is intentionally a no-op (deprecated endpoint, soft-removal stub),"
        echo "add a comment or a noop() marker the model is more likely to inspect on review."
    fi
} >&2

if [ "$MODE" = "strict" ]; then
    exit 2
fi

exit 0
