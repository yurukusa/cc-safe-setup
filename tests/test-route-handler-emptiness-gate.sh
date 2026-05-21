#!/bin/bash
# test-route-handler-emptiness-gate.sh — tests for route-handler-emptiness-gate.sh
# Solves: validation of the hook that addresses anthropics/claude-code#61107
# (Opus 4.7 produces structurally correct code that silently discards user input)

set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/route-handler-emptiness-gate.sh"

if [ ! -x "$HOOK" ]; then
    echo "FATAL: hook not executable at $HOOK"
    exit 1
fi

PASS=0
FAIL=0

assert_exit() {
    local name="$1"
    local expected_exit="$2"
    local actual_exit="$3"
    if [ "$expected_exit" = "$actual_exit" ]; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

# Helper: build the JSON input that matches the harness shape
build_input() {
    local tool="$1"
    local file_path="$2"
    local content="$3"
    python3 -c "
import json, sys
print(json.dumps({
    'tool_name': sys.argv[1],
    'tool_input': {
        'file_path': sys.argv[2],
        'content': sys.argv[3],
    }
}))
" "$tool" "$file_path" "$content"
}

echo "=== route-handler-emptiness-gate tests ==="

# Case 1: storeResearchReflection — the canonical #61107 case
echo "[case 1] storeResearchReflection: auth + redirect, no save"
INPUT=$(build_input "Write" "/app/Http/Controllers/ResearchController.php" '<?php
class ResearchController extends Controller {
    public function storeResearchReflection(Request $request) {
        if (!auth()->check()) {
            return redirect()->route("login");
        }
        $request->validate(["reflection" => "required"]);
        return redirect()->route("research.index")->with("success", "Saved");
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "storeResearchReflection with no save → strict mode blocks" "2" "$EXIT"

# Case 2: storeResearchReflection — advisory mode allows but warns
echo "[case 2] storeResearchReflection: advisory mode"
OUT=$(echo "$INPUT" | "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "advisory mode allows but warns" "0" "$EXIT"

# Case 3: empty destroy() method
echo "[case 3] empty destroy() method"
INPUT=$(build_input "Write" "/app/Http/Controllers/UserController.php" '<?php
class UserController extends Controller {
    public function destroy($id) {
        // TODO
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "empty destroy() → strict mode blocks" "2" "$EXIT"

# Case 4: legitimate store() with save — should pass
echo "[case 4] legitimate store() with save call"
INPUT=$(build_input "Write" "/app/Http/Controllers/PostController.php" '<?php
class PostController extends Controller {
    public function store(Request $request) {
        $validated = $request->validate(["title" => "required"]);
        $post = Post::create($validated);
        return redirect()->route("posts.show", $post);
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "store() with create → passes" "0" "$EXIT"

# Case 5: legitimate destroy with delete — should pass
echo "[case 5] legitimate destroy with delete"
INPUT=$(build_input "Write" "/app/Http/Controllers/CommentController.php" '<?php
class CommentController extends Controller {
    public function destroy(Comment $comment) {
        $this->authorize("delete", $comment);
        $comment->delete();
        return redirect()->route("comments.index");
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "destroy() with delete → passes" "0" "$EXIT"

# Case 6: service-delegation pattern — should pass (service handles mutation)
echo "[case 6] service-delegation pattern"
INPUT=$(build_input "Write" "/app/Http/Controllers/OrderController.php" '<?php
class OrderController extends Controller {
    public function store(Request $request, OrderService $orderService) {
        $validated = $request->validate(["sku" => "required"]);
        $orderService->createOrder($validated);
        return redirect()->route("orders.index");
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "store() with service delegation → passes" "0" "$EXIT"

# Case 7: read-only method index() — exempt by name
echo "[case 7] read-only index() exempt"
INPUT=$(build_input "Write" "/app/Http/Controllers/PostController.php" '<?php
class PostController extends Controller {
    public function index() {
        $posts = Post::all();
        return view("posts.index", compact("posts"));
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "index() read-only exempt → passes" "0" "$EXIT"

# Case 8: read-only show() — exempt by name
echo "[case 8] read-only show() exempt"
INPUT=$(build_input "Write" "/app/Http/Controllers/PostController.php" '<?php
class PostController extends Controller {
    public function show($id) {
        $post = Post::findOrFail($id);
        return view("posts.show", compact("post"));
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "show() read-only exempt → passes" "0" "$EXIT"

# Case 9: non-PHP file — should exit early
echo "[case 9] non-PHP file ignored"
INPUT=$(build_input "Write" "/app/views/posts.blade.php.bak" 'some random content')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "non-PHP file → exits early" "0" "$EXIT"

# Case 10: non-controller path — should exit early
echo "[case 10] non-controller path ignored"
INPUT=$(build_input "Write" "/app/Models/User.php" '<?php class User { public function destroy() { /* no mutation */ } }')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "non-controller path → exits early" "0" "$EXIT"

# Case 11: disabled via env var
echo "[case 11] CC_HANDLER_GATE_DISABLE=1"
INPUT=$(build_input "Write" "/app/Http/Controllers/EmptyController.php" '<?php class Foo { public function store(Request $request) { return redirect()->back(); } }')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_DISABLE=1 CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "disabled via env → passes" "0" "$EXIT"

# Case 12: update() with ->update() call
echo "[case 12] update() with ->update() call"
INPUT=$(build_input "Edit" "/app/Http/Controllers/UserController.php" '<?php
class UserController extends Controller {
    public function update(Request $request, User $user) {
        $user->update($request->validated());
        return redirect()->route("users.show", $user);
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "update() with mutation → passes" "0" "$EXIT"

# Case 13: dead-conditional case (mutating method with conditional that never fires)
echo "[case 13] mutating method with no mutation (dead conditional flag)"
INPUT=$(build_input "Write" "/app/Http/Controllers/ReturnController.php" '<?php
class ReturnController extends Controller {
    public function process(Request $request) {
        if ($request->is_returning) {
            // never set anywhere; never executes
        }
        return redirect()->route("home");
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "mutating method with no mutation → strict blocks" "2" "$EXIT"

# Case 14: bash allow other tools — should pass
echo "[case 14] non-Write/Edit tool ignored"
INPUT=$(build_input "Bash" "/some/file.php" 'irrelevant')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "Bash tool → exits early" "0" "$EXIT"

# Case 15: multiple methods, mixed
echo "[case 15] multiple methods, one bad one good"
INPUT=$(build_input "Write" "/app/Http/Controllers/MixedController.php" '<?php
class MixedController extends Controller {
    public function index() {
        return view("posts.index");
    }
    public function store(Request $request) {
        $validated = $request->validate(["title" => "required"]);
        return redirect()->route("posts.index");
    }
    public function update(Request $request, Post $post) {
        $post->update($request->validated());
        return redirect()->route("posts.show", $post);
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "mixed methods with one bad → strict blocks" "2" "$EXIT"

# Case 16: empty file
echo "[case 16] empty content"
INPUT=$(build_input "Write" "/app/Http/Controllers/EmptyFile.php" '')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "empty content → exits early" "0" "$EXIT"

# Case 17: private constructor exempt
echo "[case 17] __construct exempt by name"
INPUT=$(build_input "Write" "/app/Http/Controllers/Constructor.php" '<?php
class Foo extends Controller {
    public function __construct(Request $request) {
        $this->middleware("auth");
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "__construct exempt → passes" "0" "$EXIT"

# Case 18: Edit tool with new_string
echo "[case 18] Edit tool with new_string"
INPUT=$(python3 -c "
import json
print(json.dumps({
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': '/app/Http/Controllers/PatchController.php',
        'old_string': 'placeholder',
        'new_string': '''public function store(Request \$request) {
            if (!auth()->check()) return redirect();
            return redirect()->route(\"home\");
        }'''
    }
}))")
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "Edit tool empty store() → strict blocks" "2" "$EXIT"

# Case 19: dispatch-pattern (queued job is a form of service delegation)
echo "[case 19] dispatch() job pattern"
INPUT=$(build_input "Write" "/app/Http/Controllers/JobController.php" '<?php
class JobController extends Controller {
    public function store(Request $request) {
        $validated = $request->validate(["payload" => "required"]);
        ProcessJob::dispatch($validated);
        return redirect()->route("jobs.index");
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "dispatch job pattern → passes" "0" "$EXIT"

# Case 20: response()->json with no mutation
echo "[case 20] API endpoint with response->json no mutation"
INPUT=$(build_input "Write" "/app/Http/Controllers/Api/StatusController.php" '<?php
class StatusController extends Controller {
    public function store(Request $request) {
        return response()->json(["ok" => true]);
    }
}')
OUT=$(echo "$INPUT" | CC_HANDLER_GATE_MODE=strict "$HOOK" 2>/dev/null; echo "exit=$?")
EXIT=$(echo "$OUT" | tail -1 | sed 's/exit=//')
assert_exit "store() returning JSON with no mutation → strict blocks" "2" "$EXIT"

echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
