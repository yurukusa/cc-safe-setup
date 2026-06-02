# Session Snapshot (auto-generated)
Updated: 2026-06-02T10:36:54+09:00

## Git
- Branch: `feat/multi-vendor-concurrent-warner-2026-06-02`
- Uncommitted changes: 1 file(s)
```
 M .claude/session-snapshot.md
```
- Last commit: 4cdc01d3 feat: 別ベンダーのAI CLIの並走を検出して警告する multi-vendor-concurrent-warner を追加 複数のAI道具(Claude Code + Codex/Gemini/Cursor/Aider/Amp等)を同じリポジトリへ 並列で向ける運用は10件以上の運用者が独立して実在し(起票#64080の直接依頼)、 単一道具の運用にない2つの痛みを抱える。第1に同じファイルへの衝突する編集が どちらの道具からも見えない。第2に各社が別々に課金するため合算費用がどの道具 にも表示されず、並列で3-5倍に膨らむ。 既存の並行制御フックは全てClaude Code自身のサブエージェントを対象とし、別社の プロセスは見えない。このフックがその隙間を埋める。SessionStartでプロセス表を 調べ、他社のAI CLIが動いていれば一度だけ助言を出す(範囲の分離と費用の合算の 注意)。助言のみで、相手の道具を止めず中身も見ない。プロセス名は CC_MULTI_VENDOR_PROCS で上書き可能、テストは CC_MULTI_VENDOR_PS_OUTPUT で プロセス表を注入し決定的に検証(6シナリオ全通過)。 READMEに無料の手引き(英語/日本語のGist)とフックへの動線を追加。 Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>

## Recent Files
```
./.claude/session-snapshot.md
./test.sh
./README.md
./examples/multi-vendor-concurrent-warner.sh
./.claude/pre-compact-checkpoint.md
./examples/agents-md-sync-checker.sh
./scripts/agents-md-sync-setup.sh
./docs/june-15-cliff-14-day-plan.md
./examples/cowork-model-picker-advisor.sh
./tests/test-cowork-model-picker-advisor.sh
```

