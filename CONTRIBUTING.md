# Contributing to cc-safe-setup

Thanks for considering a contribution. Here's how to add a new hook.

## Setting Up Your Clone

Run this once, right after cloning:

```bash
git config core.hooksPath scripts/hooks
```

`docs/search-index.json` is generated from `docs/*.html`, and CI fails the build
when the two disagree. That one check accounted for 17 of the 25 red runs in the
fortnight to 2026-08-10, every one of them a file a script could have written.
The tracked `scripts/hooks/pre-commit` rebuilds the index and adds it to your
commit whenever a docs page is staged. Git does not clone hooks, so the line
above is what turns it on.

## Adding an Example Hook

1. Create `examples/your-hook-name.sh`
2. Add the standard header comment:

```bash
#!/bin/bash
# ================================================================
# your-hook-name.sh — Short description
# ================================================================
# PURPOSE: What it does and why
# TRIGGER: PreToolUse | PostToolUse | Stop
# MATCHER: "Bash" | "Edit|Write" | ""
# ================================================================
```

3. Handle empty input:

```bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
```

4. Use exit codes correctly:
   - `exit 0` = allow
   - `exit 2` = block
   - Never use `exit 1` for blocking

5. Add to `index.mjs` categories (search for `CATEGORIES`)
6. Add to `README.md` examples list
7. Run `bash scripts/ci-local.sh`, then `bash test.sh`

## Testing Your Hook

```bash
# Manual test
echo '{"tool_input":{"command":"your test command"}}' | bash examples/your-hook.sh
echo $?

# Auto-test
npx cc-hook-test examples/your-hook.sh
```

## Hook Quality Checklist

- [ ] Handles empty input (exits 0)
- [ ] Uses `exit 2` for blocking (not `exit 1`)
- [ ] Has descriptive stderr messages on block
- [ ] Passes `bash -n` syntax check
- [ ] Linked to a GitHub Issue if applicable
- [ ] Added to README.md and index.mjs categories

## Pull Request Process

1. Fork and create a branch
2. Add your hook + update README + update categories
3. Run `bash scripts/ci-local.sh` (the four cheap CI steps, ~2s) and
   `bash test.sh` (the main suite) — all must pass
4. Submit PR with:
   - What the hook does
   - Which GitHub Issue inspired it (if any)
   - Test evidence (manual or cc-hook-test output)

## Code Style

- Bash hooks (not Python/Node), so nothing is pulled from npm
- A hook still needs a JSON reader for its stdin. These two lines used to read "zero
  dependencies" and "`jq` for JSON parsing" — which contradict each other, since `jq` is a
  dependency. Prefer the core hooks' chain: try `jq`, then `python3`, then `node`, and if none
  is present, **warn that the hook is not protecting the user** and exit 0. Silently reading an
  empty command is the failure mode to avoid: the hook stays listed in `settings.json` and
  guards nothing. `tests/core-scripts-parser-fallback.test.sh` covers this.
- Short variable names are fine (`CMD`, `FILE`, `INPUT`)
- Comments explain *why*, not *what*
