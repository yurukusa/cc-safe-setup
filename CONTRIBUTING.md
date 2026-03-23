# Contributing to cc-safe-setup

Thanks for considering a contribution. Here's how to add a new hook.

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
7. Run tests: `bash test.sh`

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
3. Run `bash test.sh` (all must pass)
4. Submit PR with:
   - What the hook does
   - Which GitHub Issue inspired it (if any)
   - Test evidence (manual or cc-hook-test output)

## Code Style

- Bash hooks (not Python/Node) for zero dependencies
- `jq` for JSON parsing
- Short variable names are fine (`CMD`, `FILE`, `INPUT`)
- Comments explain *why*, not *what*
