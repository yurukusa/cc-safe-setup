# Python Hook Examples

Same functionality as the bash hooks, written in Python.

| Hook | What It Does |
|------|-------------|
| [destructive_guard.py](destructive_guard.py) | Block rm -rf, git reset --hard, PowerShell destructive |
| [secret_guard.py](secret_guard.py) | Block git add .env, credential files |

## Usage

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{"type": "command", "command": "python3 /path/to/destructive_guard.py"}]
    }]
  }
}
```

## Why Python?

- Easier to extend with complex logic
- Better string handling for pattern matching
- Familiar to Python developers
- Same exit code convention: 0=allow, 2=block
