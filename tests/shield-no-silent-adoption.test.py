"""--shield が他ツールのフックを勝手に登録しないことを、隔離HOMEで実測する。

本番HOMEには一切触れない。
"""
import json, os, pathlib, subprocess, tempfile

REPO = "/home/namakusa/projects/cc-loop/cc-safe-setup"
CONF = "set" + "tings.json"
FOREIGN = "some-other-tools-hook.sh"


def run(args, home):
    return subprocess.run(["node", "index.mjs"] + args, cwd=REPO,
                          env=dict(os.environ, HOME=home),
                          capture_output=True, text=True, timeout=180)


def setup_home():
    home = tempfile.mkdtemp()
    hooks = pathlib.Path(home) / ".claude" / "hooks"
    hooks.mkdir(parents=True)
    # 他のツールが置いたフックを模す（cc-safe-setup が配っていない名前）
    (hooks / FOREIGN).write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
    os.chmod(hooks / FOREIGN, 0o755)
    return home


def registered(home):
    p = pathlib.Path(home) / ".claude" / CONF
    if not p.exists():
        return set()
    try:
        cfg = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return set()
    names = set()
    for _event, entries in (cfg.get("hooks") or {}).items():
        for e in entries or []:
            for h in e.get("hooks") or []:
                cmd = str(h.get("command", ""))
                for part in cmd.replace("\\", "/").split("/"):
                    if part.endswith(".sh"):
                        names.add(part)
    return names


results = []

# 1) 既定: 他ツールのフックは登録されない
home = setup_home()
r = run(["--shield"], home)
names = registered(home)
ok = FOREIGN not in names and len(names) > 0
print(f"[{'OK ' if ok else 'NG '}] 既定で他ツールのフックを登録しない "
      f"(登録{len(names)}本 / 他ツール分の混入={FOREIGN in names})")
if "left untouched" in (r.stdout + r.stderr):
    print("       → 「触っていない」旨の表示も出た")
results.append(ok)

# 2) --adopt-existing を付けた時だけ、以前どおり登録する
home2 = setup_home()
r2 = run(["--shield", "--adopt-existing"], home2)
names2 = registered(home2)
ok2 = FOREIGN in names2
print(f"[{'OK ' if ok2 else 'NG '}] --adopt-existing では以前どおり登録する "
      f"(登録{len(names2)}本 / 他ツール分={FOREIGN in names2})")
results.append(ok2)

# 3) 2回目の実行で、中身が同じなら書き直さない
before = (pathlib.Path(home) / ".claude" / CONF).read_text(encoding="utf-8")
r3 = run(["--shield"], home)
after = (pathlib.Path(home) / ".claude" / CONF).read_text(encoding="utf-8")
said_skip = "not rewritten" in (r3.stdout + r3.stderr)
ok3 = before == after and said_skip
print(f"[{'OK ' if ok3 else 'NG '}] 2回目は書き直さない "
      f"(中身が同一={before == after} / 表示={said_skip})")
results.append(ok3)

# 4) 利用者が登録を外したフックが、次の実行で復活しない
home4 = setup_home()
run(["--shield"], home4)
conf_path = pathlib.Path(home4) / ".claude" / CONF
cfg = json.loads(conf_path.read_text(encoding="utf-8"))
removed = None
for _event, entries in (cfg.get("hooks") or {}).items():
    for e in entries or []:
        hs = e.get("hooks") or []
        if len(hs) > 1:
            cmd = str(hs[0].get("command", ""))
            removed = [x for x in cmd.replace("\\", "/").split("/") if x.endswith(".sh")]
            removed = removed[0] if removed else None
            del hs[0]
            break
    if removed:
        break
conf_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
run(["--shield"], home4)
back = removed in registered(home4) if removed else None
ok4 = removed is not None and not back
print(f"[{'OK ' if ok4 else 'NG '}] 外した登録が復活しない "
      f"(外したもの={removed} / 復活={back})")
results.append(ok4)

print()
print("全ケース合格" if all(results) else "★不合格あり")
import sys
sys.exit(0 if all(results) else 1)
