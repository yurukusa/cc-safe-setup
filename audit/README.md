# The Claude Code Safety Audit — course resources

Six scripts and one sheet. Everything here runs against whatever Claude Code
setup you already have. Nothing here requires my hooks or my repository.

| File | What it does |
|---|---|
| `fire.sh` | Hands one hook the operation it is supposed to refuse, and prints the decision. `--bare` repeats it with no `jq`, no `python3` and no `node` on `PATH`. |
| `boundary.sh` | Takes one thing your hook should refuse and fires the hook at its neighbours — backups, case changes, a trailing space — and at things it must let through. Counts holes and overreach separately. |
| `count-hooks.py` | Reads all three settings files and reports how many hook groups are registered in each, plus the merge. |
| `find-dead-hooks.sh` | Lists registrations whose script is not on disk. Those produce no error and no symptom. |
| `audit-checklist.md` | The 50-point sheet, in six sections. |
| `selftest.sh` | Proves `find-dead-hooks.sh` actually detects a missing registration, using a throwaway directory. Run it once if you want evidence that the detector works before you trust its silence. |
| `boundary-selftest.sh` | The same evidence for `boundary.sh`: builds a guard with a known hole and a guard without one, and checks that the report separates them. |

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
chmod +x fire.sh boundary.sh find-dead-hooks.sh selftest.sh boundary-selftest.sh

# 1. What is registered?
python3 count-hooks.py

# 2. Are any registrations pointing at nothing?
./find-dead-hooks.sh

# 3. Does a guard you rely on actually refuse?
./fire.sh <your-hook> Bash "command=<the dangerous command>"

# 4. Does it still refuse on a machine without a JSON parser?
./fire.sh --bare <your-hook> Bash "command=<the dangerous command>"

# 5. Does it also refuse the neighbours of that operation?
./boundary.sh <your-hook> Read file_path <the file it must protect>
```

Step 4 is the one that changes most people's score. Step 5 is the one that
changes it a second time, after you have fixed what steps 3 and 4 found.

## Why step 5 exists

Steps 3 and 4 answer "does the guard refuse this exact operation". That is
necessary and it is not enough. A path-matching guard draws a border, and the
holes are never in the middle of the protected area — they are just outside it,
on names nobody thought to type.

The hook shipped in this repository refused `id_rsa` and allowed `id_rsa.bak`.
After that was fixed it still allowed `id_rsa~`, `id_rsa.old.2`, and `id_rsa`
with a trailing space. Each of those is the same file to whoever reads it and a
different string to the matcher. All three were found by `boundary.sh` on a
guard that had just been widened by hand and looked finished.

`boundary.sh` also fires at things the guard must **let through** — the `.pub`
half of the key, a `.md` file that merely names it — and counts those separately
as overreach. A guard that refuses everything is not safe, it is unusable, and
there is no way to notice you have built one by testing refusals alone.

Rows marked `policy` are printed and not scored. Whether a key outside the
`.ssh` directory should be refused is your decision, not this script's.

## A note on steps 3 and 5

Both run the hook with a throwaway `HOME`, so a hook that writes state into its
config directory will not touch yours while you are testing. Neither sandboxes
anything else: a hook that itself runs destructive commands would still run
them. Read a hook before you fire it — they are short.

No file is ever opened. A `PreToolUse` hook only sees the arguments of the tool
call, so the paths you pass do not need to exist, and no real key is read.
