# cc-safe-setup

**Claude Codeを安全にするワンコマンドツール。** 909個のexample hook · 71件超のAnthropic公式Issueに対応 · 239個のテストファイル · 30K+ 累計npmダウンロード

```bash
npx github:yurukusa/cc-safe-setup
```

> **なぜ `npx cc-safe-setup` ではないのか。** npm で配っている版は **2026年4月20日公開の 29.8.0 で止まっています**（このリポジトリは 30.0.4）。npm の資格情報の更新待ちで、それが済むまで npm は 29.8.0 を配り続けます。差は見た目だけではありません。同じ入力を与えると、29.8.0 のガードは 30.0.4 が拒否する3つの操作を通します——シェル変数越しのホームへの再帰削除（`rm -rf $HOME/x`）、`&` を区切りに使った `git reset --hard`、連結コマンドでの `git add .env`。上の GitHub を直接指す形なら、常に現行のコードが入ります。中身は同じもので、置き場所が違うだけです。

10秒で8個の安全フックをインストール。`rm -rf /`のブロック、mainへのpush防止、シークレット漏洩検出、構文エラー自動検知。依存関係ゼロ。

> **フック（hook）とは？** Claude Codeがコマンドを実行する前に、内容をチェックして危険なら止める仕組み。空港のセキュリティゲートのようなもの — 搭乗口（コマンド実行）の前にチェック（hook）があり、危険物（rm -rf等）を持っていたら止められる。

> **Claude Code 本体がもう止めてくれるのでは？** 一部はそのとおりで、知っておく価値があります。v2.1.183（2026年6月）で、破壊的な **git** コマンド（`git reset --hard` / `git clean -fd` / `git stash drop` など）と `terraform`/`pulumi`/`cdk destroy` を、**あなたが頼んでいないと判断した時に** 止める **auto mode** のガードが本体に入りました（歓迎すべき改善です）。ただしこれは **auto mode 限定**・対象は **git と IaC のみ**・**分類器による判定**（意図を推測するので確率的）です。cc-safe-setup のフックは **決定論的**（パターン → `exit 2`・推測しない）で、**すべてのモードで発火**し、本体のガードが対象にしない領域 — `rm -rf`・本番DBの破壊・シークレットのコミット・`main` への push / force-push・作業範囲の逸脱・クラウド/k8s の破棄・サブエージェントの暴走・嘘の「完了」報告 — まで止めます。**両方を併用するのが一番**です。

## 入れておけば、こうして守れる（実際の事故から）

```
  cc-safe-setup
  Claude Code を自律運用でも、安心して任せられる状態に

  入れておけば、こうした実際の事故を未然に防げる（GitHub Issue より）:
  ✓ rm -rf による約50GB / 1,500ファイルの破壊を、実行の前に止める (#49129)
  ✓ auto モードの ~/.ssh の削除を止め、SSH 鍵を守る (#49554)
  ✓ ~/.git-credentials の PAT の確認なしの削除を止める (#49539)
  ✓ rm -rf の NTFS ジャンクション経由のユーザーディレクトリ全消去を止める (#36339)
  ✓ Remove-Item -Recurse -Force による未 push のソースの破壊を止める (#37331)
  ✓ 本番データベースへの破壊的な DDL を、実行の前に止める (#46684)
  ✓ 副の作業者の「完了」の偽りの報告を検出する（道具の呼び出しの記録が 0 件）
  ✓ 文脈の圧縮の後に CLAUDE.md のルールが黙って無視されるのを検出する (#6354)
```

**今日、どの問題を解決したいですか？** — 実際に本を買った方の経路をもとに、まず無料で解決し、必要なら深掘りの本へ。

| あなたの状況 | まず無料で | さらに深く |
|---|---|---|
| 破壊的操作 (`rm -rf` / force push / 本番のコマンド) を止めたい | [rm -rf 事故を防ぐ](prevent-rm-rf-jp.html) → `npx github:yurukusa/cc-safe-setup` | [事故防止本 (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme-ja&utm_medium=routing-table) |
| 本番データベースを消されたくない | [本番DB全消しを防ぐ](prevent-database-wipe-jp.html) | [事故防止本 (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme-ja&utm_medium=routing-table) |
| 未コミットの作業が `git reset` で消える | [git reset --hard 事故を防ぐ](prevent-git-reset-hard-jp.html) | [事故防止本 (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme-ja&utm_medium=routing-table) |
| 認証情報の漏洩・乗っ取りが怖い | [認証情報の漏洩を防ぐ](prevent-credential-leak-jp.html) | [事故防止本 (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme-ja&utm_medium=routing-table) |
| トークンの費用が暴走する (`/cost` ショック) | [費用爆発を防ぐ](prevent-cost-explosion-jp.html) | [Token Book (¥2,500)](https://zenn.dev/yurukusa/books/token-savings-guide?utm_source=readme-ja&utm_medium=routing-table) |
| チームや組織に配ってよいか判断したい（稟議・権限・監査の説明が要る） | [チームの費用ガバナンス](team-cost-governance-jp.html)・[導入の手引き](team-rollout-guide.html)・[統制のスコアカード](team-governance-scorecard.html) | [チーム/企業導入 安全パック (¥3,000)](https://zenn.dev/yurukusa/books/cc-team-safety-pack?utm_source=readme-ja&utm_medium=routing-table) ——稟議・ポリシー・権限設計・月次レビューを1冊で |
| 急に遅い・固まる・落ちる | [遅い/クラッシュの原因と直し方](claude-code-slow-crash-jp.html) | 無料の道具で対処 |
| どのモデルが実際に動いているか分からない | [提供モデルの監査](claude-code-which-model-served-jp.html) | 無料の道具で確認 |
| サブエージェントが嘘の「完了」を返す（派遣の捏造・沈黙の停止・観察の不在・範囲の逸脱） | [集積の露出診断](cluster-exposure-diagnostic.html) | [副の作業者の沈黙の失敗 (¥1,500)](https://zenn.dev/yurukusa/books/sub-agent-observability?utm_source=readme-ja&utm_medium=routing-table) ——4つの型を一冊で深掘り・[事故防止本 (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme-ja&utm_medium=routing-table) |
| `AGENTS.md` と `CLAUDE.md` の同期 | [相互運用スコアカード](agents-md-interop-scorecard.html) | [AGENTS.md 相互運用本 (¥1,500)](https://zenn.dev/yurukusa/books/agents-md-interop?utm_source=readme-ja&utm_medium=routing-table) |
| MCP のプラグインを入れたいが、費用と安全性が読めない | [OWASP MCP 対応表](owasp-mcp-hooks.html) | [MCPプラグインの信頼性 (¥800)](https://zenn.dev/yurukusa/books/mcp-plugin-reliability?utm_source=readme-ja&utm_medium=routing-table) ——5つの脆弱性と利用者の側の防衛 |
| サブエージェントの worktree 隔離が黙って無効になり、コミットが別ブランチへ静かに着地する | [worktree 隔離リスク自己診断](multi-agent-worktree-isolation-risk-jp.html) → `npx github:yurukusa/cc-safe-setup` | [AGENTS.md 相互運用本 (¥1,500)](https://zenn.dev/yurukusa/books/agents-md-interop?utm_source=readme-ja&utm_medium=routing-table)・[事故防止本 (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme-ja&utm_medium=routing-table) |
| 「調べて」と頼んだだけなのに、勝手にコマンドを実行・状態を変更された (docker restart / ALTER SYSTEM / マイグレーション) | [「調べて」が勝手な変更に化けるとき](claude-code-diagnose-became-mutation-jp.html) → `npx github:yurukusa/cc-safe-setup` | [事故防止本 (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b?utm_source=readme-ja&utm_medium=routing-table-diagnose) |
| 来月の新しい事故に備えたい | [Safety Lab 5月号の無料試し読み](safety-lab-may-preview.html) | [CC Safety Lab（月刊・¥500/月）](https://note.com/yurukusa/membership) |

## 何ができるか

| コマンド | 機能 |
|---|---|
| `npx github:yurukusa/cc-safe-setup` | 8個の安全フックをインストール |
| `--shield` | 最大安全（スタック検出+推奨hook自動選択） |
| `--install-example <name>` | 909個のexampleから個別インストール |
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

56個のCLIコマンドの全リスト: `npx github:yurukusa/cc-safe-setup --help`

## インストール

```bash
npx github:yurukusa/cc-safe-setup
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

> 🔁 月次の追跡が欲しい？ [CC Safety Lab（月刊・¥500/月）](https://note.com/yurukusa/membership)で、毎月その月に実際に起きた事故 4-8 件（対処法付き）、 1-2 個の安全 hook、 1 件の深掘り、 月次の安全チェックリスト、 商品更新案内を届ける。 note のメンバーシップで、各号は無料の試し読みから中身を確かめてから加入できる。

> 📕 Kindle 派の人へ：[事故防止本は Amazon Kindle でも出している（B0H69B7SVZ）](https://www.amazon.co.jp/dp/B0H69B7SVZ)。ただし**Kindle 版は 2026年6月22日に出したきりで、当時の内容のまま更新していない**（当時のZenn 版は40章台だった）。Zenn 版はいま全100章・約61万字で、新しい事故が見つかるたびに章が増え、既に買った人には追加の費用なしで届く。Kindle Unlimited で読めるのは、その6月22日時点の中身だと思ってほしい。中身は、データが消えた夜・本番DBを消す一歩手前・トークンが想定の20倍に膨らんだ月といった、起きた順の事故とコピーして使える復旧の手順をまとめたもの。新刊の通知を受け取りたい人は Amazon の著者ページから「著者をフォロー」もできる。

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

インストール: `npx github:yurukusa/cc-safe-setup --install-example <名前>`

## 🚨 2026年6月15日の課金の崖
> **訂正（2026年6月22日）: Anthropic は施行の当日にこれを一時停止した。** 課金の分離は2026年6月15日に予定されていたが、Anthropic はその日に一時停止し「当面は何も変わらない」と通知した。`claude -p`・Agent SDK・GitHub Actions の利用は、今も通常の購読の枠から引かれる（[the-decoder](https://the-decoder.com/anthropic-backs-off-unpopular-billing-overhaul-as-price-war-with-openai-looms/)、[digitalapplied](https://www.digitalapplied.com/blog/anthropic-claude-credit-overhaul-june-15-2026)）。ただし公式には告知されたままで再来し得るので、自分の露出を知っておく価値はある。下の道具は「いま起きている緊急事態」ではなく「再来に備える準備」として使うこと。

Anthropic は[2026年6月15日に programmatic の課金を分離](https://docs.claude.com/en/api/billing)する（予定だったが当日に一時停止・上の訂正を参照）。 `claude -p` や SDK の呼び出しが別の credit の bucket に routing される。 2026年5月、 起票で財務の損失の報告が表面化: [#61704 自信を持ったが間違いの billing の主張で €60の限度を €84.68 で超過](https://github.com/anthropics/claude-code/issues/61704)、 [#61728 動かない code を動いているかのように提示して $80 の損失](https://github.com/anthropics/claude-code/issues/61728)、 [#61086 修正の請け合いの後の malformed の tool call の繰り返しで token の浪費](https://github.com/anthropics/claude-code/issues/61086)、 [#61699 production の deployment の session で繰り返しの欺瞞](https://github.com/anthropics/claude-code/issues/61699)。 **モデルは Anthropic 自身の課金の logic を training data から検証できない。** 6月15日の後、 モデルの billing の主張と実際の課金の routing の乖離が更に広がる。
**今日利用可能の利用者の側の防衛:**
- **無料の90秒の対話の診断** (日本語の道具): [Claude Code の課金で間違われた？](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/78dafd28f5dc839f6b0c78130591fe2e/raw/wrong-charge-diagnostic-ja.html) — 5件の質問で利用者の事例を filed reports (€84.68、 $80) に照合、 support.anthropic.com に貼り付けるための返金の論理の素案を生成。 signup 不要、 telemetry なし、 単一の HTML ([英語版](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/d3a0e2403cc4078aa0183400c137d824/raw/wrong-charge-diagnostic.html))。
- **無料の billing-axis の整理** (install 不要): [日本語版の長編 Gist](https://gist.github.com/yurukusa/65d9ce96fab8d767ed0a088fb1e20152) — 4件の filed cases、 9行の cluster の目録、 4件の利用者の側の防衛、 効く返金の論理 ([英語版](https://gist.github.com/yurukusa/4ca735cb192219581d303afe5f63d2eb))
- **無料の6月15日の見積もりの道具** (browser のみ、 signup 不要): 直近30日の利用を貼り付けて post-June-15 の見積もりを取得 → [Pool 2 の estimator](https://htmlpreview.github.io/?https://gist.githubusercontent.com/yurukusa/b78e1cb9234a5d12b27b61c9d82637d9/raw/june-15-pool2-estimator.html)
- **無料の6月15日の露出の判定（実機のログから）** (ブラウザのみ、 アップロードなし): 推定でなく、 あなたのセッションのログに記録された起動の種類を読んで、 対話（Pool 1）とプログラム経由（Pool 2）の比率を出します → [実データの露出チェッカー](https://yurukusa.github.io/cc-safe-setup/june15-cliff-exposure-from-logs-jp.html)
- **判定の枠組み**: [Claude Code Migration Playbook ($19、 Edition 2 は 2026-08-12 から配布中)](https://yurukusa.gumroad.com/l/claude-code-migration-playbook) — 251頁、 11件の dated の triggers (Opus 4.7 silent regression、 6月15日の programmatic credit pool cliff、 133-case の claim-vs-reality cluster) + 3件の移行の経路 (stay+harden / switch / hybrid — ある operator は Kimi K2 を $0.02/call の coworker として $200/月 を $30/月 に削減) + 日々の burn rate から stay / switch / hybridize の判定。 Edition 1 の購入者には Gumroad library から無償の自動更新
- **月額の継続の購読**: [CC Safety Lab（月刊・¥500/月）](https://note.com/yurukusa/membership) — note のメンバーシップ。毎月その月の事故のまとめ・安全チェックリスト・コピペできる hook・失敗事例の深掘りを届ける。各号は無料の試し読みあり
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
- [Safety Audit](https://yurukusa.github.io/cc-safe-setup/safety-audit.html) — いまの設定がどの種類の危険を防げていて、どれを防げていないかを判定する（無料・登録不要）

hookの仕組みと設定方法は[Claude Code公式ドキュメント](https://code.claude.com/docs/en/hooks)を参照。

## 書面の監査（有償・3件）

hook 本体はこれからも無料（MIT）です。そのうえで、自分の設定を誰かに読ませたい場合のために、書面の監査を3件だけ用意しています。いずれも非同期で、通話も打ち合わせもなく、こちらがあなたの環境で何かを実行することもありません。注文と依頼を日本語で書いていただければ、報告書も日本語でお返しします。

法人向けの安全監査（¥150,000〜）・研修・導入支援・月額の運用保守・スポットのコンサルは[受け付けていません](https://yurukusa.github.io/cc-safe-setup/services-jp.html)。止めたのは「人が継続して手を動かす形」で、書面の監査はその形ではないので続けています。

| 監査 | 何を読むか | 価格・納期 |
|---|---|---|
| [CLAUDE.md 監査](https://yurukusa.github.io/cc-safe-setup/claude-md-audit-jp.html) | 指示ファイル（`CLAUDE.md`、任意で `settings.json` と使用頻度の高い hook 5本） | ¥3,980・48時間 |
| [Token Burn 監査](https://yurukusa.github.io/cc-safe-setup/token-burn-audit-jp.html) | セッションの記録と `/cost` の出力。費用が実際に消えている場所 | ¥3,980・48時間 |
| [Full-Surface 監査](https://yurukusa.github.io/cc-safe-setup/full-surface-audit-jp.html) | 上の2件がそれぞれ1種類のファイルを読むのに対し、こちらは `CLAUDE.md`・`settings.json`・hook・セッションの記録・CI の設定の**5層を互いに突き合わせて**、層と層の**あいだ**にしか現れない矛盾だけを報告する | ¥29,800・72時間 |

買う前に中身が見えないものなので、成果物はすべて公開しています。[CLAUDE.md 監査の見本](claude-md-audit-sample-jp.md)／[Token Burn 監査の見本](token-burn-audit-sample-jp.md)／[Full-Surface 監査の見本](full-surface-audit-sample-jp.md)。いずれも自分の設定に対して実際に走らせた実物で、自分の数字と自分の hook が間違っていた箇所もそのまま載せています。Full-Surface の見本で出てきたいちばん重い1件は、自分の機械で動いていた安全 hook が、同じ名前で配布しているものとは別のプログラムだった、というものでした。

注文は [Ko-fi](https://ko-fi.com/yurukusa/commissions) から。送っていただいたファイルの扱い（公開しない・学習に使わない・納品から30日以内に削除）と返金の条件は [SERVICES.md](../SERVICES.md) に書いてあります。**セッションの記録や設定を、公開される場所（issue など）へ貼らないでください。** 非公開の受け渡しの経路をこちらから返します。

## 必要なもの

- `jq`: `brew install jq` / `apt install jq`
- Claude Code 2.1以上

## ライセンス

MIT
