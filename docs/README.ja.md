# cc-safe-setup

**Claude Codeを安全にするワンコマンドツール。** 719個のexample hook · 9,200+テスト · 30K+ 累計インストール

```bash
npx cc-safe-setup
```

10秒で8個の安全フックをインストール。`rm -rf /`のブロック、mainへのpush防止、シークレット漏洩検出、構文エラー自動検知。依存関係ゼロ。

> **フック（hook）とは？** Claude Codeがコマンドを実行する前に、内容をチェックして危険なら止める仕組み。空港のセキュリティゲートのようなもの — 搭乗口（コマンド実行）の前にチェック（hook）があり、危険物（rm -rf等）を持っていたら止められる。

## 何ができるか

| コマンド | 機能 |
|---|---|
| `npx cc-safe-setup` | 8個の安全フックをインストール |
| `--shield` | 最大安全（スタック検出+推奨hook自動選択） |
| `--install-example <name>` | 654個のexampleから個別インストール |
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
| CLAUDE.mdルール消失 | 圧縮後に無視 | 自動再注入 |
| サブエージェントの指示無視 | v2.1.84以降CLAUDE.md除外 ([#40459](https://github.com/anthropics/claude-code/issues/40459)) | hookで制約 |
| 読まずに編集 | 6%→34%に増加 ([#42796](https://github.com/anthropics/claude-code/issues/42796)) | 警告 |

> 📘 トークン消費が多すぎる？ [Token Book](token-book.html)（¥2,500・[Zennで購入](https://zenn.dev/yurukusa/books/token-savings-guide)）でCLAUDE.md最適化・hookによるトークン制御・コンテキスト管理・ワークフロー設計を解説。800+時間の実測データ付き。第1章無料。hookの設計パターンは[Safety Guide](https://zenn.dev/yurukusa/books/6076c23b1cb18b)（¥800・第3章まで無料）。

**既知の制限:**

- `FileChanged`通知はファイル内容をhookの**前に**コンテキストへ注入します。セッション中に`.env`や`credentials.json`が外部で変更された場合、hookでブロックできません（[#44909](https://github.com/anthropics/claude-code/issues/44909)）。対策: `dotenv-watch`で警告を受け取り、Claude Code実行中は機密ファイルを編集しないでください。

## セッション保護フック

セッションの破損やトークンの無駄遣いを防ぐフック。

| フック | 解決する問題 | Issue |
|--------|-------------|-------|
| `cch-cache-guard` | セッションファイル読み取りによるキャッシュ汚染をブロック | [#40652](https://github.com/anthropics/claude-code/issues/40652) |
| `image-file-validator` | 偽画像ファイル（テキストの.png）の読み取りをブロック | [#24387](https://github.com/anthropics/claude-code/issues/24387) |
| `large-read-guard` | 大きなファイルのcatによるコンテキスト浪費を警告 | [#41617](https://github.com/anthropics/claude-code/issues/41617) |
| `prompt-usage-logger` | 全プロンプトをログしてトークン消費パターンを追跡 | [#41249](https://github.com/anthropics/claude-code/issues/41249) |
| `compact-alert-notification` | auto-compaction発火を通知（トークン浪費サイクルを検知） | [#41788](https://github.com/anthropics/claude-code/issues/41788) |
| `token-budget-guard` | セッションコスト上限を超えたらツール呼び出しをブロック | [#38335](https://github.com/anthropics/claude-code/issues/38335) |
| `session-index-repair` | 終了時にsessions-index.jsonを再構築（`--resume`でセッション消失防止） | [#25032](https://github.com/anthropics/claude-code/issues/25032) |
| `session-backup-on-start` | 開始時にセッションJSONLをバックアップ（勝手な削除から保護） | [#41874](https://github.com/anthropics/claude-code/issues/41874) |
| `working-directory-fence` | CWD外のRead/Edit/Writeをブロック（別プロジェクトでの誤作業防止） | [#41850](https://github.com/anthropics/claude-code/issues/41850) |
| `pre-compact-transcript-backup` | compaction前にJSONL全体をバックアップ（rate limit時のデータ喪失防止） | [#40352](https://github.com/anthropics/claude-code/issues/40352) |
| `read-before-edit` | 読まずに編集するパターンを検知して警告（Read:Edit比が70%低下 — [#42796](https://github.com/anthropics/claude-code/issues/42796)） | [#42796](https://github.com/anthropics/claude-code/issues/42796) |
| `subagent-error-detector` | サブエージェントの529/502/timeout結果を検知して警告 | [#41911](https://github.com/anthropics/claude-code/issues/41911) |

インストール: `npx cc-safe-setup --install-example <名前>`

## ドキュメント

- [Getting Started](https://yurukusa.github.io/cc-safe-setup/getting-started.html) — 5分で安全に
- [Hook Selector](https://yurukusa.github.io/cc-safe-setup/hook-selector.html) — 5問で最適なhookセットを推薦
- [Auto-Approve Guide](https://yurukusa.github.io/cc-safe-setup/auto-approve-guide.html) — 許可プロンプトを減らす
- [OWASP MCP対応表](https://yurukusa.github.io/cc-safe-setup/owasp-mcp-hooks.html) — OWASP MCP Top 10全リスク対策
- [settings.jsonリファレンス](../SETTINGS_REFERENCE.md) — 全設定の解説
- [COOKBOOK](../COOKBOOK.md) — レシピ集
- [トラブルシューティング](../TROUBLESHOOTING.md) — 動かない時の対処法
- [Web版ツール](https://yurukusa.github.io/cc-safe-setup/hub.html) — 全ツール一覧
- [Safety Audit](https://yurukusa.github.io/cc-safe-setup/safety-audit.html) — プロによる安全設定レビュー（$50〜）

hookの仕組みと設定方法は[Claude Code公式ドキュメント](https://docs.anthropic.com/en/docs/claude-code/hooks)を参照。

## 必要なもの

- `jq`: `brew install jq` / `apt install jq`
- Claude Code 2.1以上

## ライセンス

MIT
