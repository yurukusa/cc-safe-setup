# The Claude Code Safety Audit — course resources

Four scripts and one sheet. Everything here runs against whatever Claude Code
setup you already have. Nothing here requires my hooks or my repository.

| File | What it does |
|---|---|
| `fire.sh` | Hands one hook the operation it is supposed to refuse, and prints the decision. `--bare` repeats it with no `jq`, no `python3` and no `node` on `PATH`. |
| `count-hooks.py` | Reads all three settings files and reports how many hook groups are registered in each, plus the merge. |
| `find-dead-hooks.sh` | Lists registrations whose script is not on disk. Those produce no error and no symptom. |
| `audit-checklist.md` | The 50-point sheet, in six sections. |
| `selftest.sh` | Proves `find-dead-hooks.sh` actually detects a missing registration, using a throwaway directory. Run it once if you want evidence that the detector works before you trust its silence. |

## The three exit codes

Claude Code hands a hook the tool call as JSON on standard input and reads its
exit code.

| Code | Meaning |
|---|---|
| `0` | allow the operation |
| `2` | refuse it, and show what the hook wrote to standard error |
| anything else | the hook itself failed, and the operation proceeds |

A warning printed to standard error does not stop anything. Only `2` does.

## Quick start

```bash
chmod +x fire.sh find-dead-hooks.sh selftest.sh

# 1. What is registered?
python3 count-hooks.py

# 2. Are any registrations pointing at nothing?
./find-dead-hooks.sh

# 3. Does a guard you rely on actually refuse?
./fire.sh ~/.claude/hooks/YOUR-HOOK.sh Bash "command=<the dangerous command>"

# 4. Does it still refuse on a machine without a JSON parser?
./fire.sh --bare ~/.claude/hooks/YOUR-HOOK.sh Bash "command=<the dangerous command>"
```

Step 4 is the one that changes most people's score.

## A note on step 3

`fire.sh` runs the hook with a throwaway `HOME`, so a hook that writes state
into `~/.claude` will not touch yours while you are testing. It does not
sandbox anything else: a hook that itself runs destructive commands would still
run them. Read a hook before you fire it — they are short.
