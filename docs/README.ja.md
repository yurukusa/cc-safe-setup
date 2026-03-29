# cc-safe-setup

**Claude Codeを安全にするワンコマンドツール。** 610個のexample hook · 9,677テスト · 1,000+ インストール/日

```bash
npx cc-safe-setup
```

10秒で8個の安全フックをインストール。`rm -rf /`のブロック、mainへのpush防止、シークレット漏洩検出、構文エラー自動検知。依存関係ゼロ。

## 何ができるか

| コマンド | 機能 |
|---|---|
| `npx cc-safe-setup` | 8個の安全フックをインストール |
| `--shield` | 最大安全（スタック検出+推奨hook自動選択） |
| `--install-example <name>` | 511個のexampleから個別インストール |
| `--examples` | 全exampleを一覧表示 |
| `--create "説明"` | 自然言語でカスタムフック生成 |
| `--verify` | 各フックの動作確認 |
| `--audit` | 安全スコア（0-100） |
| `--doctor` | 動かない原因を診断 |
| `--dashboard` | ブロック統計ダッシュボード |
| `--stats` | ブロック統計レポート |
| `--lint` | 設定の静的解析 |
| `--benchmark` | フック実行速度を計測 |
| `--diff <file>` | 設定を比較 |
| `--watch` | ブロックされたコマンドをリアルタイム表示 |
| `--export / --import` | チームで設定を共有 |
| `--team` | プロジェクトにコミットして共有 |

56個のCLIコマンドの全リスト: `npx cc-safe-setup --help`

## インストール

```bash
npx cc-safe-setup
```

Claude Codeを再起動。完了。

## 何がブロックされるか

| 操作 | Before | After |
|---|---|---|
| `rm -rf /` | 実行される | ブロック |
| `git push --force` | 実行される | ブロック |
| `git push origin main` | 実行される | ブロック |
| `git add .env` | 実行される | ブロック |
| `cat ~/.netrc` | トークン表示 | ブロック |
| Python構文エラー | 気づかない | 自動検出 |
| コンテキスト枯渇 | 突然死 | 段階的警告 |

## ドキュメント

- [Getting Started](https://yurukusa.github.io/cc-safe-setup/getting-started.html) — 5分で安全に
- [Auto-Approve Guide](https://yurukusa.github.io/cc-safe-setup/auto-approve-guide.html) — 許可プロンプトを減らす
- [OWASP MCP対応表](https://yurukusa.github.io/cc-safe-setup/owasp-mcp-hooks.html) — OWASP MCP Top 10全リスク対策
- [settings.jsonリファレンス](../SETTINGS_REFERENCE.md) — 全設定の解説
- [COOKBOOK](../COOKBOOK.md) — レシピ集
- [トラブルシューティング](../TROUBLESHOOTING.md) — 動かない時の対処法
- [Web版ツール](https://yurukusa.github.io/cc-safe-setup/hub.html) — 全ツール一覧

📘 **[Claude Codeを本番品質にする実践ガイド](https://zenn.dev/yurukusa/books/6076c23b1cb18b)**（¥800 / [第2章を無料で読む](https://zenn.dev/yurukusa/books/6076c23b1cb18b/viewer/2-safety-guards)）— 700+時間の自律稼働から生まれた14章の実践ガイド。hookの設計パターン、テスト戦略、実際のインシデント事後分析。

## 必要なもの

- `jq`: `brew install jq` / `apt install jq`
- Claude Code 2.1以上

## ライセンス

MIT
