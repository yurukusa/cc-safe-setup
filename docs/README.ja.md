# cc-safe-setup

**Claude Codeを安全にするワンコマンドツール。** 800個超のexample hook · 71件超のAnthropic公式Issueに対応 · 9,228+テスト · 30K+ 累計インストール

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
| `--install-example <name>` | 800個超のexampleから個別インストール |
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

> 🔁 月次の追跡が欲しい？ [CC Safety Lab Founder](safety-lab.html)（¥500/月・[Ko-fiで参加](https://ko-fi.com/yurukusa/tiers)）で毎月 4-8 件の事故事例（対処法付き）、 1-2 個の安全 hook、 1 件の深掘り、 月次チェックリスト差分、 商品更新案内を届ける。 [5 月号の中身](safety-lab.html#may-issue) ｜ [6 月号予告](safety-lab.html#next-issue)。 Founder 価格は 12 ヶ月で ¥6,000、 据え置き。

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
| `subagent-identity-leak-guard` | 子エージェントが親の身分を名乗ったり親の会話履歴を漏らすのを予防（delegation prompt の身分の境界の検査） | [#55488](https://github.com/anthropics/claude-code/issues/55488) |
| `subagent-tool-allowlist-enforcer` | 子エージェントの道具の境界を delegation prompt で明示し、 親の検証手順を促す（虚偽報告の予防） | [#55653](https://github.com/anthropics/claude-code/issues/55653) |
| `subagent-spawn-verification-enforcer` | 子エージェントの spawn の応答が虚偽でないかを成果物の検証手順で予防する | [#55666](https://github.com/anthropics/claude-code/issues/55666) |
| `subagent-destructive-git-guard` | 子エージェントの delegation prompt で destructive な git の命令の禁止と安全な代替（git stash）と working tree の状態の確認の指示が明示されているかを検査（4/25-5/8 の 3 件の同型の data-loss の予防） | [#57463](https://github.com/anthropics/claude-code/issues/57463) / [#46444](https://github.com/anthropics/claude-code/issues/46444) / [#53765](https://github.com/anthropics/claude-code/issues/53765) |
| `trustfall-mcp-injection-guard` | clone した repo の `.mcp.json` と `.claude/settings.json` で MCP server が unsandboxed で起動する 1-click RCE を SessionStart の段で警告（Adversa AI の TrustFall PoC 対応） | [The Register](https://www.theregister.com/security/2026/05/07/claude-code-trust-prompt-can-trigger-one-click-rce/) / [GHSA-vp62-r36r-9xqp](https://github.com/advisories/GHSA-vp62-r36r-9xqp) |
| `mcp-startup-bloat-detector` | Pro / Claude.ai-OAuth の login で `claude.ai ` 前置きの connector が大量に同期されて System tools の context が膨れる現象を SessionStart で検知し、 `ENABLE_CLAUDEAI_MCP_SERVERS=false` の回避策を提示する（v2.1.14 で塞いだはずの経路が v2.1.133 で 29 倍に再発） | [#50062](https://github.com/anthropics/claude-code/issues/50062) / [#57235](https://github.com/anthropics/claude-code/issues/57235) |
| `stale-temp-settings-detector` | 同じ機械の他の利用者が `/tmp/claude-settings-*.json` を残している場合、机上版の `--settings '{}'` 起動が EACCES で衝突する現象を SessionStart で検知し、所有者の名前を表示して削除の判断を支援する | [#57224](https://github.com/anthropics/claude-code/issues/57224) |

インストール: `npx cc-safe-setup --install-example <名前>`

## 🚨 2026年6月15日の課金の崖
Anthropic は[2026年6月15日に programmatic の課金を分離](https://docs.claude.com/en/api/billing)する。 `claude -p` や SDK の呼び出しが別の credit の bucket に routing される。 2026年5月、 起票で財務の損失の報告が表面化: [#61704 自信を持ったが間違いの billing の主張で €60の限度を €84.68 で超過](https://github.com/anthropics/claude-code/issues/61704)、 [#61728 動かない code を動いているかのように提示して $80 の損失](https://github.com/anthropics/claude-code/issues/61728)、 [#61086 修正の請け合いの後の malformed の tool call の繰り返しで token の浪費](https://github.com/anthropics/claude-code/issues/61086)、 [#61699 production の deployment の session で繰り返しの欺瞞](https://github.com/anthropics/claude-code/issues/61699)。 **モデルは Anthropic 自身の課金の logic を training data から検証できない。** 6月15日の後、 モデルの billing の主張と実際の課金の routing の乖離が更に広がる。
**今日利用可能の利用者の側の防衛:**
- **無料の90秒の対話の診断** (日本語の道具): [Claude Code の課金で間違われた？](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/78dafd28f5dc839f6b0c78130591fe2e/raw/wrong-charge-diagnostic-ja.html) — 5件の質問で利用者の事例を filed reports (€84.68、 $80) に照合、 support.anthropic.com に貼り付けるための返金の論理の素案を生成。 signup 不要、 telemetry なし、 単一の HTML ([英語版](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/d3a0e2403cc4078aa0183400c137d824/raw/wrong-charge-diagnostic.html))。
- **無料の billing-axis の整理** (install 不要): [日本語版の長編 Gist](https://gist.github.com/yurukusa/65d9ce96fab8d767ed0a088fb1e20152) — 4件の filed cases、 9行の cluster の目録、 4件の利用者の側の防衛、 効く返金の論理 ([英語版](https://gist.github.com/yurukusa/4ca735cb192219581d303afe5f63d2eb))
- **無料の6月15日の見積もりの道具** (browser のみ、 signup 不要): 直近30日の利用を貼り付けて post-June-15 の見積もりを取得 → [Pool 2 の estimator](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/b78e1cb9234a5d12b27b61c9d82637d9/raw/june-15-pool2-estimator.html)
- **判定の枠組み**: [Claude Code Migration Playbook ($19、 Edition 2 は 2026-05-22 から live)](https://yurukusa.gumroad.com/l/claude-code-migration-playbook) — 241頁、 14件の dated の triggers (Opus 4.7 silent regression、 6月15日の programmatic credit pool cliff、 133-case の claim-vs-reality cluster) + 3件の移行の経路 (stay+harden / switch / hybrid — ある operator は Kimi K2 を $0.02/call の coworker として $200/月 を $30/月 に削減) + 日々の burn rate から stay / switch / hybridize の判定。 Edition 1 の購入者には Gumroad library から無償の自動更新
- **失敗の事例の集積**: [Claim-Verify Handbook ($19、 2026-05-22 から live)](https://yurukusa.gumroad.com/l/claim-verify-handbook) — Claude Code または副の作業者が「完了」 「verified」 と主張したが実態は乖離した133+件の事例の整理。 $80 を動かない code に消費 ([#61728](https://github.com/anthropics/claude-code/issues/61728))、 3週間の未 commit の作業を `git reset --hard` で消失 ([#61102](https://github.com/anthropics/claude-code/issues/61102))、 20件の session が silent に削除 ([#61952](https://github.com/anthropics/claude-code/issues/61952))、 安全 hook の flag file を `rm -f` で能動的に削除 ([#61953](https://github.com/anthropics/claude-code/issues/61953))。 3段階の枠組み + 14件の利用者の側の防衛 + 5件の検出の道具 (全件 implemented、 165+ tests passing) + 付録 E の operator-side gate matrix ([live gist](https://gist.github.com/yurukusa/bb3812006d92d49cf55db74a65fc4032))。 Migration Playbook Edition 2 の sister product
- **月額の継続の証拠の購読**: [CC Safety Lab Founder Membership (¥500/月、 Founder の値段で locked)](https://ko-fi.com/yurukusa/tiers) — 2026年6月号は23日の崖の準備の playbook を中核に
## ドキュメント

- [Getting Started](https://yurukusa.github.io/cc-safe-setup/getting-started.html) — 5分で安全に
- [Hook Selector](https://yurukusa.github.io/cc-safe-setup/hook-selector.html) — 5問で最適なhookセットを推薦
- [Auto-Approve Guide](https://yurukusa.github.io/cc-safe-setup/auto-approve-guide.html) — 許可プロンプトを減らす
- [OWASP MCP対応表](https://yurukusa.github.io/cc-safe-setup/owasp-mcp-hooks.html) — OWASP MCP Top 10全リスク対策
- [Defense Kit](https://gist.github.com/yurukusa/823f76c4783e45809735c92b660bd2ed) — 事故10件と対応するhook 10件と即時のinstallコマンド10件
- [トークン消費の順位表のアンチパターン](https://gist.github.com/yurukusa/ac41d467d97f3711129070d8e311db4f) — 社内のトークン消費の順位表が Goodhart の法則で失敗する理由、 5 つの代替の指標、 Uber の事例 (Fortune 2026-05-26: 順位表の導入で 2026 年の AI 予算を 4 ヶ月で消耗)
- [settings.jsonリファレンス](../SETTINGS_REFERENCE.md) — 全設定の解説
- [COOKBOOK](../COOKBOOK.md) — レシピ集
- [トラブルシューティング](../TROUBLESHOOTING.md) — 動かない時の対処法
- [Web版ツール](https://yurukusa.github.io/cc-safe-setup/hub.html) — 全ツール一覧
- [Safety Audit](https://yurukusa.github.io/cc-safe-setup/safety-audit.html) — プロによる安全設定レビュー（$50〜）

hookの仕組みと設定方法は[Claude Code公式ドキュメント](https://code.claude.com/docs/en/hooks)を参照。

## 必要なもの

- `jq`: `brew install jq` / `apt install jq`
- Claude Code 2.1以上

## ライセンス

MIT
