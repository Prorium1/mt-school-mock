# mt-school-mock


## Prorium AI Development Environment

このリポジトリは Mac のローカル・Claude Code Cloud（スマホ含む）・将来のCIのどこから開いても、
**同じ開発思想・同じSkillセット・同じ品質基準**で開発できる状態を保つ。
Prorium の全リポジトリで同じ節を共有しており、内容を変えるときは他のリポジトリにも反映する。

### 実装前に必ず確認する

実装を始める前に、利用可能な Agent Skills を確認する。必要なSkillが見当たらないときだけ、

```
bash .claude/bootstrap.sh
```

を実行して環境を用意する。**毎回無条件に実行しない**（導入済みなら何もしないが、
確認のための通信が無駄になる）。現状だけ見たいときは `bash .claude/bootstrap.sh --check`。

`~/.claude/skills` は環境ごとに別物で、Cloudのコンテナは使い捨てのため、
**新しいCloudセッションでは存在しないことがある**。その場合のみ上記を実行する。

### 使えるものは積極的に使う

| 工程 | 使うもの |
|---|---|
| Planning | `/office-hours` `/autoplan` `/plan-ceo-review` `/plan-eng-review` |
| Design | `ui-ux-pro-max` / `web-design-guidelines` / gstack design skills |
| Engineering | `supabase` / `supabase-postgres-best-practices` |
| Review | `/review` `/investigate` |
| QA | `/browse` `/qa`（**Cloudでは不可**。Macで実施） |
| Security | `/cso` `/guard` |
| Release | `/ship` |

### 新機能の進め方

原則としてこの順で進める。

```
企画 → CEOレビュー → Engineeringレビュー → 実装 → Review → QA → Security → Ship
```

小さな変更（文言修正・1ファイルの不具合修正など）は、必要な工程だけ選んでよい。
判断に迷う規模なら、工程を省かず通す。

### 環境ごとの差（gstackのCORE ONLY方針）

**Claude Code Cloud では gstack の Browser機能（Playwright Chromium）が利用できない場合がある。**
2026-08-28 に実測した環境では、既設 Chromium と gstack 同梱 Playwright のリビジョン不一致に加え、
不足するブラウザを取得する CDN も利用できなかったため、CORE ONLY として運用する。
ただし Skill のリンク自体は `bin/gstack-relink` で完了するため、**Core Skills は通常どおり使える**。
`bootstrap.sh` はこれを CORE ONLY として扱い、ブラウザが無いことだけを理由に導入失敗と判定しない。

**フォールバック方針**: Cloudでは Core Skills で開発を進め、
**最終的なブラウザQAは Mac など Playwright Chromium が使える環境で行う**。
Cloudで `/qa` や `/design-review` を実行しようとして失敗したら、その工程だけ Mac に回す。

| 分類 | Skill | Mac | Cloud |
|---|---|---|---|
| Skill（gstack外） | ui-ux-pro-max / supabase / supabase-postgres-best-practices / web-design-guidelines | ○ | ○ |
| gstack Core | `/review` `/investigate` `/cso` `/guard` `/autoplan` `/plan-ceo-review` `/plan-eng-review` `/plan-devex-review` `/devex-review` `/spec` `/health` `/retro` `/learn` `/freeze` `/unfreeze` `/careful` `/context-save` `/context-restore` `/document-generate` `/document-release` `/ship` | ○ | ○ |
| gstack 一部制限 | `/office-hours`（対話レビューは可。第三者サイトの代行操作のみ不可）<br>`/land-and-deploy`（デプロイは可。公開後のスモーク確認のみ不可） | ○ | △ |
| gstack Browser | `/qa` `/qa-only` `/design-review` `/design-shotgun` `/design-consultation` `/design-html` `/plan-design-review` `/scrape` `/benchmark` `/canary` `/skillify` `/open-gstack-browser` `/pair-agent` `/setup-browser-cookies` | ○ | **×** |

この表は 2026-08-28 に Cloud で実測したもの（`browse --help` は成功・`browse open` はChromium起動で失敗）。
推測ではなく、各 SKILL.md の browse 依存とガードの有無を確認して分類している。
gstack を更新したら分類が変わる可能性があるため、`bash .claude/bootstrap.sh --check` で状態を確かめる。

### Cloud Browser Capability Rule（Cloudでの誤実行を防ぐ）

**Claude Code Cloud では、作業開始時に `bash .claude/bootstrap.sh --check` で browser capability を確認する。**

`gstack browser: 利用不可（CORE ONLY）` と出たら、**上の表の「gstack Browser」行のSkillは実行しない**。
これらはリンク済みのため一覧に出て呼べてしまうが、Chromium の起動で必ず失敗する。

そのSkillが必要な工程に到達したら、**無理に実行せず、Chromium の再インストールも試みない**。
「Mac側でBrowser QAが必要」としてタスクに残し、Cloudでは利用可能な Core Skills
（`/review` `/investigate` `/cso` `/guard` `/autoplan` `/plan-ceo-review` `/plan-eng-review` `/ship` など）で作業を継続する。

Mac の Claude Code で gstack browser が利用可能なら、Browser系Skillは通常どおり使ってよい。

原因は、既設 Chromium と gstack 同梱 Playwright のリビジョン不一致に加え、
不足するブラウザを取得する CDN も利用できないこと（2026-08-28 に shimei-clinic で実測）。
`GSTACK_CHROMIUM_PATH` で既設 Chromium を指す回避策は効かなかった。

### セキュリティ（この構成で守ること）

- `.env*` をコミットしない（`.gitignore` 済み）
- APIキー・トークンをコード・ドキュメント・チャットに書かない（絶対制約5）
- `~/.claude/settings.json` をリポジトリへコピーしない（個人の権限設定・OAuth情報が入る）
- MCPの認証情報をコミットしない
- 危険な操作（`rm -rf` / `DROP TABLE` / force push など）を自動許可の設定に入れない。
  必ず都度確認する
- `bootstrap.sh` は秘密情報を一切扱わない。入力も求めないし、書き出しもしない
