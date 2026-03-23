# cc-safe-setup

**Claude Codeを安全にするワンコマンドツール。**

8個の安全フック + 36個のインストール可能なexample。destructive guard、branch protection、secret leak prevention、syntax check、context monitor、その他。

```bash
npx cc-safe-setup
```

## 何ができるか

| コマンド | 機能 |
|---|---|
| `npx cc-safe-setup` | 8個の安全フックをインストール |
| `--create "説明"` | 自然言語でカスタムフック生成 |
| `--audit` | 安全スコア（0-100） |
| `--lint` | 設定の静的解析 |
| `--diff <file>` | 設定を比較 |
| `--benchmark` | フック実行速度を計測 |
| `--doctor` | 動かない原因を診断 |
| `--watch` | ブロックされたコマンドをリアルタイム表示 |
| `--stats` | ブロック統計レポート |
| `--share` | 共有URLを生成 |
| `--export / --import` | チームで設定を共有 |
| `--verify` | 各フックの動作確認 |
| `--install-example <name>` | 36個のexampleフック |

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
| Python構文エラー | 気づかない | 自動検出 |
| コンテキスト枯渇 | 突然死 | 段階的警告 |

## ドキュメント

- [settings.jsonリファレンス](../SETTINGS_REFERENCE.md) — 全設定の解説
- [移行ガイド](../MIGRATION.md) — permissionsからhooksへ
- [トラブルシューティング](../TROUBLESHOOTING.md) — 動かない時の対処法
- [チートシート](https://yurukusa.github.io/cc-safe-setup/cheatsheet.html) — 印刷用A4
- [エコシステム比較](https://yurukusa.github.io/cc-safe-setup/ecosystem.html) — 全hookプロジェクト比較
- [Web版](https://yurukusa.github.io/cc-safe-setup/) — ブラウザで診断＋セットアップ生成

## 必要なもの

- `jq`: `brew install jq` / `apt install jq`
- Claude Code 2.1以上

## ライセンス

MIT
