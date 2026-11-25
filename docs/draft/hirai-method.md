# hirai-lite と hirai-project-method を 1 つのプラグイン hirai-method にまとめる

id_prefix: HM
kind: ハーネス・進め方
domain: —
implements: README.md「やることの形と Orca の設定」, plugins/hirai-project-method/README.md
decisions: heyapro-app feature #2042（テックリード 2026-11-25 の決定）
upstream: —
downstream: heyapro-app の hirai-method への移行（同じ feature #2042 の PR）
supersedes: —
wave: —
status: 起案
approvals: 要件=PR #<n> 設計=PR #<n> task=PR #<n>
approved_at:
merged_into:

起案: 2026-11-25（heyapro-app #2042 の作業ツリー 2042-hirai-method）。

## 1. 問題

### 提案: hirai-method-lite の土台と足す部品を、元リポ thirai-classlab/hirai-method の 1 つのプラグイン hirai-method に作り直し、機能の切り替えを各リポの `.claude/settings.json` に置く

**決めること**: hirai-lite と hirai-project-method を、元リポ hirai-method の 1 つのプラグインに作り直し、機能を settings.json で切り替えるか。**推奨**: 承認する（テックリードが 2026-11-25 に決めた）

**目的**: プラグインを 1 行で入れられ、2 つの版のずれ（hirai-task の探し方・取り込むと前の版が止まる）が無くなる

**位置**: ハーネスの改善。元リポ hirai-method・hirai-method-lite・heyapro-app の 3 本の PR

**承認すると**: 入れ方が `hirai-method@hirai-method`、command が `/hirai-method:…` になる。hirai-method-lite は凍結し、入れている別のプロジェクトは何も変わらない。戻せる（元リポの元の main は tag `legacy-v1` に残す）

**しないと**:
- 足す部品は土台の版に依存し（`plugins/hirai-project-method/.claude-plugin/plugin.json` の `dependencies`）、hirai-task の探し方が 3 か所に分かれている（`scripts/tasks-path.sh:401`・`scripts/update-check.sh:62`・heyapro-app の `scripts/gh-task.sh:97`）

**注意**: 機能の切り替えに使える project の settings.json の項目は `env` だけ（§3）。`env` はシェルの環境変数より強いので、一時の上書き（`HC_*`）とは名前を分ける

## 2. 目指す状態

### 追加された要件

### 要件 HM-R1: 利用者は、1 つのプラグイン hirai-method を入れるだけで、土台・GitHub Project のタスク管理・Orca の機能を使える
- HM-R1.1 Given 何も入っていないリポ When `/plugin marketplace add thirai-classlab/hirai-method` → `/plugin install hirai-method@hirai-method` Then command・skill・hook・`bin/hirai-task` が全部入る（足すプラグインは要らない）
- HM-R1.2 Given hirai-method 4.x When command を打つ Then 名前は `/hirai-method:…`（`/hirai-method:board`・`/hirai-method:project-setup` も同じプラグインの中）

### 要件 HM-R2: プロジェクトの機能は、各リポの `.claude/settings.json` の `env` で切り替える
- HM-R2.1 Given `.claude/settings.json` に `"env": {"HIRAI_METHOD_TASKS": "github-project"}` When 会話を開く Then タスク管理は GitHub Project の形で動く（無ければ台帳）
- HM-R2.2 同じく `HIRAI_METHOD_WORKTREE`（off / warn / block）・`HIRAI_METHOD_NOTIFY`（off / orca）
- HM-R2.3 優先は「シェルの `HC_TASKS`・`HC_WORKTREE`・`HC_NOTIFY`（一時の上書き）> 環境変数の `HIRAI_METHOD_*`（Claude Code が settings.local.json > settings.json を重ねて渡す）> ファイルの `.claude/settings.local.json` の env > `.claude/settings.json` の env（Claude Code の外の端末・CI で打ったとき）> `.claude/mode.yml` の `tasks:`・`worktree:`・`notify:`（4.x の間だけ読む移行用）> 既定」
- HM-R2.4 Given mode.yml にだけ 3 項目がある When 会話を開く Then 開始時に「settings.json の env へ移せます（/hirai-method:config）」と 1 行出る。`/hirai-method:config` は settings.json の env に書く
- HM-R2.5 進め方（`mode`）・`auto_sync`・表の設定（`load_*`・`nightly_ci`）は mode.yml に残す（切り替えるたびに共有の settings.json を書き換えないため）

### 要件 HM-R3: hirai-task は同じプラグインの `bin/` にあり、探し方は 1 本
- HM-R3.1 Given hirai-method が入ったリポ When hook・statusline・command が hirai-task を探す Then `installed_plugins.json` の `hirai-method@hirai-method` のこのリポの行の最大版の `bin/hirai-task` を使う

### 要件 HM-R4: hirai-task は feature を着手から完了まで回せ、目印と coverage を feature で読む（heyapro-app #2021 の 2 回目の問い）
- HM-R4.1 Given 着手可の feature When `hirai-task start <feature>` Then Status が 進行中 になる（今は exit 2。`bin/hirai-task:1572`）。`review`・`done`・`set` も feature を受ける。feature の 承認待ち → 着手可 は今までどおり人だけが動かす
- HM-R4.2 Given 着手可の feature で開いたコードの task が子に無い When `hirai-task ready` Then その feature が着手できるものに出る（今は task だけ。`:1320`）
- HM-R4.3 Given 提案の表 When `new --from-table` Then 印の無い task の行（コードの行）は issue にせず、親の feature の本文のチェックリスト（`- [ ] <行の id>: <題名>`）にし、feature の目印に `rows=<行の id,…>` と読む束の和 `reads=` を書く。`[操作]`・`[User]` の行は今までどおり issue
- HM-R4.4 Given feature の目印の `rows=` When `coverage` Then その行を起票済みと数える。`start`・`show` の読む束は feature の目印の `reads=` を出す（`:3285`）
- HM-R4.5 Given 子の issue が 0 本の feature When `close-parents`・`align` Then 閉じない・動かさない（チェックリストの feature は PR の `Closes #<feature>` で閉じる）

### 要件 HM-R5: hirai-lite を入れている別のプロジェクトは何も変わらない
- HM-R5.1 hirai-method-lite（配布元 hirai-lite）は中身を凍結する。README の先頭に hirai-method へ移る案内を足すだけ
- HM-R5.2 hirai-method-lite の配布の一覧から hirai-lite-v2 の行を外す（入っている 2 か所はそのまま動く。更新が来なくなるだけ）

### 要件 HM-R6: 責務分離を README と heyapro-app の docs/harness に書く
- HM-R6.1 3 つの層: hirai-method の土台（決まりの予算・進め方・確認・画面下）／ タスク管理の機能（hirai-task・board・project-setup）／ 各リポのハーネス（そのリポの決まり・検査・hook・skill）

## 3. 公式で確かめたこと・実測

| 問い | 答え | 出典 |
|---|---|---|
| プラグインの設定項目（`userConfig`）を project の settings.json に置けるか | 置けない。値は user（か managed）の `pluginConfigs` にだけ入り、project からの読み取りは 2.1.207 で廃止 | https://code.claude.com/docs/en/settings-reference.md#pluginconfigs ・ https://code.claude.com/docs/en/plugins/manifest-reference.md#user-configuration |
| project の settings.json で渡せるもの | `env`（「すべての session とその subprocess に設定する」） | https://code.claude.com/docs/en/settings-reference.md#env |
| `env` は hook と Bash に届くか | 届く（実測: 2.1.312 の `claude -p`、SessionStart・PreToolUse の hook と Bash ツールの 3 つとも settings の値） | heyapro-app の作業ツリーの `.tmp/env-probe` |
| シェルの環境変数と同じ名前なら | **settings の値が勝つ**（実測: シェルで `B=from-shell` を渡しても 3 か所とも `from-settings`） | 同上 |
| settings.local.json の env | settings.json の env に名前ごとに勝つ（実測） | 同上 |
| 名前の付け替え | marketplace.json の `renames`（旧名 → 新名。2.1.193）。旧名を「案内だけ」で残す公式の仕組みは無い。**今回は配布元ごと別なので使わない** | https://code.claude.com/docs/en/plugins/host-marketplace.md#rename-or-remove-a-plugin |
| skill を project で止める | `skillOverrides`（"off" など。どの settings にも書ける。2.1.129）。台帳のリポで `github-project` を隠したいときに使える | https://code.claude.com/docs/en/settings-reference.md#skilloverrides |

`env` がシェルより強いので、settings.json に `HC_NOTIFY` を書くと、コーディネーターが `HC_NOTIFY=off claude` で開いても orca になる（`bin/hirai-notify` の説明「だからコーディネーターは HC_NOTIFY=off で開く」が効かなくなる）。だから settings の名前は `HIRAI_METHOD_*`、一時の上書きは今の `HC_*` のまま分ける。

## 4. 設計

### 4.1 作り直し方（元リポ thirai-classlab/hirai-method）

1. 元の main（96d5256・2026-07-21。install.sh の旧ハーネス）を tag `legacy-v1` に残す（force push はしない）
2. 元リポの main から branch を切り、hirai-method-lite の main を **履歴ごと merge で取り込む**（`--allow-unrelated-histories`。木は hirai-method-lite のものにする）。理由: (1) 取り込んだ file の `git log`・`git blame` が続く（ハーネスの検査は blame で過去の行を当て直す） (2) このあと hirai-method-lite に入る直し（#2021 の文言など）を普通の merge で取り込める
3. その上に、1 つにする直し・名前の付け替え・settings.json の読み・hirai-task の直しを積み、PR で main に入れる

### 4.2 中身の移し先

| いま（hirai-method-lite の足すプラグイン） | 4.0.0（hirai-method の中） |
|---|---|
| `plugins/hirai-project-method/bin/hirai-task` | `bin/hirai-task` |
| `commands/board.md`・`project-setup.md` | `commands/`（`/hirai-method:board`・`:project-setup`） |
| `skills/github-project/` | `skills/github-project/`（skill は 3 本で上限 3 に収まる） |
| `hooks/coordinator-load.sh` と hooks.json | `hooks/` に足し、hooks.json を 1 本に。hook は 6 本になり、smoke case 6 の上限 5 を 6 に上げる |
| `scripts/ghp-path.sh`・`hirai_*.py` | `scripts/` |
| `docs/rules-reference/project-setup.md` | `docs/rules-reference/` |
| `tests/smoke.sh` | 土台の `tests/smoke.sh` の case に入れる |
| `plugin.json` の `dependencies` | 無くなる |

配布の一覧（`.claude-plugin/marketplace.json`）は name `hirai-method`・plugin 1 つ（`hirai-method`・source `./`）。

### 4.3 settings.json の形（導入先）

```json
{
  "enabledPlugins": { "hirai-method@hirai-method": true },
  "extraKnownMarketplaces": {
    "hirai-method": { "source": { "source": "github", "repo": "thirai-classlab/hirai-method" }, "autoUpdate": true }
  },
  "env": {
    "HIRAI_METHOD_TASKS": "github-project",
    "HIRAI_METHOD_WORKTREE": "block",
    "HIRAI_METHOD_NOTIFY": "orca"
  }
}
```

読むのは `scripts/tasks-path.sh` の `harness_tasks_form` と、同じ形の `harness_worktree`・`harness_notify`（新設。`hooks/worktree-guard.sh`・`bin/hirai-notify`・`hooks/notify-attention.sh`・`hooks/session-start.sh`・`scripts/statusline.sh` が今 mode.yml を直接読んでいる所をこの 2 つに寄せる）。

### 4.4 heyapro-app 側

- `.claude/settings.json`: `enabledPlugins` を `hirai-method@hirai-method` 1 つに、`extraKnownMarketplaces` に `hirai-method`、`env` に 3 項目。mode.yml の `tasks:`・`worktree:`・`notify:` は消す
- `scripts/gh-task.sh`: 探すのは `hirai-method@hirai-method` → 無ければ `hirai-project-method@hirai-lite`（merge から入れ替えまでの間も動く）
- `.claude/tasks-path.sh`・`.claude/statusline.sh`: 4.0.0 の写しに替える
- `/hirai-lite:` の言及: 現在形の文書と `.claude/` だけ `/hirai-method:` に。凍った ADR・過去の draft は触らない
- 入れ替えは merge のあとにコーディネーターが本体の checkout で打つ（1 行ずつ）:
  1. `claude plugin marketplace add thirai-classlab/hirai-method`
  2. `claude plugin install hirai-method@hirai-method --scope project`
  3. `claude plugin uninstall hirai-project-method@hirai-lite --scope project --keep-data`
  4. `claude plugin uninstall hirai-lite@hirai-lite --scope project --keep-data`

### 4.5 hirai-method-lite 側（凍結と案内）

- README の先頭に「hirai-method へ移りました。移し方は 4.4 の 4 行（範囲は入れた範囲）」の節を足す
- 配布の一覧から `hirai-lite-v2` の行を外す
- 中身（command・hook・script）は変えない。版も上げない（入れている 44 か所に更新が届かない）

## 5. 要判断

| # | 問い | 推し | 理由 |
|---|---|---|---|
| 1 | 版の番号 | **4.0.0**（hirai-lite の続き） | 変更履歴と取り込んだ履歴が hirai-lite の続き。`/update` の移し方の手順は版の大小で分かれる（「1.x・2.x から 3.0.0 へ」）。元リポの旧ハーネスの `package.json` は 0.1.0 で、1.0.0 だと旧ハーネスの続きに見える。tag は `hirai-method--v4.0.0` |
| 2 | 配布元の名前 | **hirai-method**（テックリード 2026-11-25 23:45「hiraimethodはlite+projectmethodでリベースして下さい」） | 決まった |
| 3 | 別のプロジェクトの移し方 | **凍結して各自で移す**（hirai-method-lite は README の案内だけ） | 入れている 44 か所（`installed_plugins.json` の hirai-lite の 45 行から rmp-app を除く）は配布元 hirai-lite のまま何も変わらない。開始時の案内を出すには hirai-method-lite の版を上げることになり、44 か所に更新が届く |

## 6. 進め方

1. 判断を待つ間: hirai-task の feature の扱い（HM-R4）、settings.json の env の読み（HM-R2）を hirai-method-lite の branch で作る（あとで hirai-method に merge）。責務分離の文書（HM-R6）
2. 元リポに tag `legacy-v1` を打ち、hirai-method-lite を履歴ごと取り込む（§4.1）
3. 1 つにする直し・名前の付け替え・配布の一覧・README・CHANGELOG・tag
4. heyapro-app #2021 の branch が push されたら hirai-method-lite の上で重ね、hirai-method へ merge で取り込む（`rules/code.md`・`commands/commit.md`・`docs/rules-reference/task-ledger.md`・`templates/draft.md`・`skills/github-project/SKILL.md`・`docs/rules-reference/project-setup.md` はそれまで触らない）
