# Session Snapshot (auto-generated)
Updated: 2026-07-27T10:11:44+09:00

## Git
- Branch: `fix/doctor-wiring-check-2026-07-27`
- Uncommitted changes: 1 file(s)
```
 M .claude/session-snapshot.md
```
- Last commit: d26a33cb --doctor: 導入済みhookが宣言どおりのイベントに載っているかを検査する 誤ったイベントに繋がれた hook は、導入も成功し設定にも載るのに、一度も 発火しない。利用者は守られていると思い込む。このプロジェクトが最も嫌う型の 失敗でありながら、既存の診断13項目はこれを見ていなかった。 必要性の裏づけ: 導入の処理の照合子の解決を直した結果、908本中267本が 宣言と違う照合子で登録されうると判明した。だが解析側を直しても、既に settings.json に書かれた誤りは直らない。手元の環境で実際に走らせると 25本中7本が誤配線で、その中には CLAUDE.md を Edit/Write から守るはずの hook(Bash に繋がれていた)と、費用の遮断器(PostToolUse を宣言しているのに PreToolUse に繋がれ、道具の結果を読めず常に0を測っていた)が含まれる。 検査は読むだけで、settings.json を書き換えない。誤りを見つけたら、 どの hook がどこに載っていて何を宣言しているかを1行ずつ示し、直し方を 2通り(--install-example での書き直しと手での修正)提示する。 照合子は順序を無視して比べる。Edit|Write と Write|Edit は同じ道具を選ぶので、 文字列のまま比べると意味のない差を報告してしまう。鳴きすぎる診断は読まれなくなる。 Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>

## Recent Files
```
./.claude/session-snapshot.md
./.claude/session-logs/2026-07-27.md
./.claude/pre-compact-checkpoint.md
./test.sh
./examples/parallel-cascade-detector.sh
./examples/plugin-hooks-json-bloat-detector.sh
./examples/skills-load-verifier.sh
./examples/tool-result-correlation-checker.sh
./examples/agents-md-sync-checker.sh
./examples/bypass-mode-effective-verifier.sh
```

## Active TODOs: 1 file(s)

