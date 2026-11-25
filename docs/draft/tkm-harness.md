# hirai-lite と hirai-project-method を 1 つのプラグイン tkm-harness にまとめる

id_prefix: TKM
kind: ハーネス・進め方
domain: —
implements: README.md「やることの形と Orca の設定」, plugins/hirai-project-method/README.md
decisions: heyapro-app feature #2042（テックリード 2026-11-25〜26 の決定）
upstream: —
downstream: heyapro-app の tkm-harness への移行（同じ feature #2042 の PR）
supersedes: —
wave: —
status: 起案
approvals: 要件=PR #<n> 設計=PR #<n> task=PR #<n>
approved_at:
merged_into:

起案: 2026-11-25（heyapro-app #2042 の作業ツリー 2042-hirai-method）。2026-11-26 に置き場と名前の決定に合わせて書き直した。

## 1. 問題

### 提案: hirai-method-lite の土台と足す部品を、新しいリポ thirai-classlab/tkm-harness の 1 つのプラグイン tkm-harness にし、機能の切り替えを各リポの `.claude/settings.json` に置く

**決めること**: hirai-lite と hirai-project-method を 1 つのプラグイン tkm-harness にまとめ、機能を settings.json で切り替えるか。**推奨**: 承認する（テックリードが 2026-11-25〜26 に決めた）

**目的**: プラグインを 1 行で入れられ、2 つの版のずれ（hirai-task の探し方・依存の版）が無くなる。fork してそのまま使える

**位置**: ハーネスの改善。tkm-harness・hirai-method-lite・heyapro-app の 3 本の PR

**承認すると**: 入れ方が `tkm-harness@tkm-harness`、command が `/tkm-harness:…` になる。hirai-method-lite は凍結し、入れている別のプロジェクトは何も変わらない。戻せる

**しないと**:
- 足す部品は土台の版に依存し（`plugins/hirai-project-method/.claude-plugin/plugin.json` の `dependencies`）、hirai-task の探し方が 3 か所に分かれている（`scripts/tasks-path.sh:401`・`scripts/update-check.sh:62`・heyapro-app の `scripts/gh-task.sh:97`）

**注意**: 機能の切り替えに使える project の settings.json の項目は `env` だけ（§3）。`env` はシェルの環境変数より強いので、一時の上書き（`HC_*`）とは名前を分ける

## 決まったこと（テックリード・原文）

- 2026-11-25「hirai-liteを1本化して下さい」「Aにしましょうか」「ただ、setting.jsonで制御できるようにして下さい。プロジェクト毎に設定をするべきだから」「hirai-liteとmethodとハーネスの責務分離も教えてください」
- 2026-11-26 00:10〜00:18「版任せます。tkm-はーねすにしておいて下さい。凍結しておいて下さい。まずは個人アカウントに出して、forkしてclasslab内でも利用します。」「新しくリポジトリ切って下さい。」「プラグイン名もtkm-ハーネスでええよ」

## 2. 目指す状態

### 追加された要件

### 要件 TKM-R1: 利用者は、1 つのプラグイン tkm-harness を入れるだけで、土台・GitHub Project のタスク管理・Orca の機能を使える
- TKM-R1.1 Given 何も入っていないリポ When `/plugin marketplace add thirai-classlab/tkm-harness`（fork なら fork の owner）→ `/plugin install tkm-harness@tkm-harness` Then command・skill・hook・`bin/hirai-task` が全部入る（足すプラグインは要らない）
- TKM-R1.2 Given tkm-harness 4.x When command を打つ Then 名前は `/tkm-harness:…`（`/tkm-harness:board`・`/tkm-harness:project-setup` も同じプラグインの中）

### 要件 TKM-R2: プロジェクトの機能は、各リポの `.claude/settings.json` の `env` で切り替える
- TKM-R2.1 Given `.claude/settings.json` に `"env": {"TKM_HARNESS_TASKS": "github-project"}` When 会話を開く Then タスク管理は GitHub Project の形で動く（無ければ台帳）
- TKM-R2.2 同じく `TKM_HARNESS_WORKTREE`（off / warn / block）・`TKM_HARNESS_NOTIFY`（off / orca）
- TKM-R2.3 効く順は「シェルの `HC_TASKS`・`HC_WORKTREE`・`HC_NOTIFY`（一時の上書き）> 環境変数の `TKM_HARNESS_*`（Claude Code が settings.local.json > settings.json を重ねて渡す）> 端末・CI で打ったときの `.claude/settings.local.json`・`.claude/settings.json` の file > `.claude/mode.yml` の `tasks:`・`worktree:`・`notify:`（4.x の間だけ読む移行用）> 既定」
- TKM-R2.4 Given mode.yml にだけ 3 項目がある When 会話を開く Then 開始時に「settings.json の env へ移せます（/tkm-harness:config）」と 1 行出る。`/tkm-harness:config` は settings.json の env に書く
- TKM-R2.5 進め方（`mode`）・`auto_sync`・`nightly_ci` は mode.yml に残す（切り替えるたびに共有の settings.json を書き換えないため）。表の設定（期限・本線）は settings.json の env の `TKM_HARNESS_LOAD_DEADLINE`・`TKM_HARNESS_LOAD_DEADLINE_LABEL`・`TKM_HARNESS_LOAD_MAINLINE`・`TKM_HARNESS_LOAD_MAINLINE_LABEL` が先、無ければ mode.yml の `load_*`

### 要件 TKM-R3: hirai-task は同じプラグインの `bin/` にあり、探し方は 1 本
- TKM-R3.1 Given tkm-harness が入ったリポ When hook・statusline・command が hirai-task を探す Then `${CLAUDE_PLUGIN_ROOT}/bin/hirai-task`、無ければ `installed_plugins.json` の `tkm-harness@<配布元>` のこのリポの行の最大版の `bin/hirai-task` を使う

### 要件 TKM-R4: hirai-task は feature を着手から完了まで回せ、目印と coverage を feature で読む（heyapro-app #2021 の 2 回目の問い）
- TKM-R4.1 Given 着手可の feature When `hirai-task start <feature>` Then Status が 進行中 になる（今は exit 2。`bin/hirai-task:1572`）。`review`・`done`・`set` も feature を受ける。feature の 承認待ち → 着手可 は今までどおり人だけが動かす
- TKM-R4.2 Given 着手可の feature で開いたコードの task が子に無い When `hirai-task ready` Then その feature が着手できるものに出る（今は task だけ。`:1320`）
- TKM-R4.3 Given 提案の表 When `new --from-table` Then 印の無い task の行（コードの行）は issue にせず、親の feature の本文のチェックリスト（`- [ ] <行の id>: <題名>`）にし、feature の目印に `rows=<行の id,…>` と読む束の和 `reads=` を書く。`[操作]`・`[User]` の行は今までどおり issue
- TKM-R4.4 Given feature の目印の `rows=` When `coverage` Then その行を起票済みと数える。`start`・`show` の読む束は feature の目印の `reads=` を出す（`:3285`）
- TKM-R4.5 Given 子の issue が 0 本の feature When `close-parents`・`align` Then 閉じない・動かさない（チェックリストの feature は PR の `Closes #<feature>` で閉じる）

### 要件 TKM-R5: fork してそのまま使える
- TKM-R5.1 配布の一覧（`.claude-plugin/marketplace.json`）の source は `./`。plugin.json・marketplace.json・動く部品（hooks・scripts・bin・commands・skills）に持ち主とリポの名前を書かない
- TKM-R5.2 更新の知らせが読む最新の版の URL は、`~/.claude/plugins/known_marketplaces.json` の配布元 tkm-harness の `source.repo`（github の形）から作る。取れなければ通信しない（fork を入れた人は fork の版を見る）

### 要件 TKM-R6: hirai-lite を入れている別のプロジェクトは何も変わらない
- TKM-R6.1 hirai-method-lite（配布元 hirai-lite）は中身を凍結する。README の先頭に tkm-harness へ移る案内を足すだけ。版は上げない
- TKM-R6.2 hirai-method-lite の配布の一覧から hirai-lite-v2 の行を外す（入っている 2 か所はそのまま動く。更新が来なくなるだけ）

### 要件 TKM-R7: 責務分離を README と heyapro-app の docs/harness に書く
- TKM-R7.1 3 つの層: tkm-harness の土台（決まりの予算・進め方・確認・画面下・知らせ）／ タスク管理の機能（hirai-task・board・project-setup）／ 各リポのハーネス（そのリポの決まり・検査・hook・skill・settings）

### 要件 TKM-R8: 進捗の表を board が出し、担当と「いまやっていること」を Orca から引く（テックリード 2026-11-26 00:45「アサインジェイソンに書いてる内容CLIから取れへんの?」「入れといて下さい。」「これだと何やってるかよくわからんなあ」）
- TKM-R8.1 Given GitHub Project のリポ When `hirai-task board --progress` Then 全体の 1 行・開いているセクションの 2 列の表・「進行中のタスク」の表（担当｜セクション｜順番｜進捗｜いまやっていること）・担当の居ないもの・これから立てる を文字の表で出す。`--json` で同じ中身を機械の形で出す（mod の欄から使う）
- TKM-R8.2 Given Orca がある When 担当の列を作る Then `orca orchestration worker-list`・`task-list`・`orca worktree list` を突き合わせ、issue の番号は割り当ての題（spec の 1 行目）からだけ取り、完了を報告して作業ツリーが残る担当（merge 待ち）も出し、着手可なのにどこにも無い task を「これから立てる」に出す。担当の名前は割り当ての短い題
- TKM-R8.3 Given 担当の行 When 「いまやっていること」を作る Then 最新の heartbeat の phase・最新の status か question の件名・作業ツリーの最後の commit・PR と CI の状態を 1 行に組む
- TKM-R8.4 Given Orca が無い When 担当の列を作る Then 開いている PR の head の branch 名の番号 → issue の assignee の順で引く

### 要件 TKM-R9: 進みの表を、決まった時機にコーディネーターの会話へ入れる（テックリード 2026-11-26「modはやめましょうか。適切なタイミングでコンテキストに注入しましょう。」「会話の始まり・/clear・圧縮のあと / after-merge / 振り出しのあと にしましょう」）
- TKM-R9.1 Given コーディネーターの会話 When 会話の始まり・`/clear`・圧縮のあと（SessionStart の startup・resume・clear・compact） Then `hirai-task load --cached` の表を丸ごと `additionalContext` で入れる。GitHub は叩かない。控えの古さを 1 行添え、控えが無ければ 1 行で断る。担当の会話・GitHub Project で回さないリポでは何も入れない
- TKM-R9.2 Given `TKM_HARNESS_LOAD_ON_START=off`（settings.json の env） When 会話を開く Then 入れない（既定は入れる。プラグインの設定項目 `userConfig` は project の settings.json に置けないので env で持つ）
- TKM-R9.3 after-merge と assign・start・done の出力の最後の表（`print_load_after`）は今のまま。担当の知らせ・ユーザーの発言のたびには入れない（PostToolUse の `coordinator-load.sh` は今のまま）
- TKM-R9.4 委譲の手順の文書に「`orca orchestration worker-start` のすぐあとに `hirai-task assign <issue> <担当> [順]` を打つ」「worker-start の作業ツリーに `orca worktree set --display-name <短い題> --issue <番号>` を付ける」「担当は状況が変わったら `orca worktree set --worktree current --comment <いまやっていること>` を打つ」を足す
- TKM-R9.5 コーディネーターの判定（`hirai-task is-coordinator`）は、付け忘れても表が出る形にする（案はテックリードに問い中）

## 3. 公式で確かめたこと・実測

| 問い | 答え | 出典 |
|---|---|---|
| プラグインの設定項目（`userConfig`）を project の settings.json に置けるか | 置けない。値は user（か managed）の `pluginConfigs` にだけ入り、project からの読み取りは 2.1.207 で廃止 | https://code.claude.com/docs/en/settings-reference.md#pluginconfigs ・ https://code.claude.com/docs/en/plugins/manifest-reference.md#user-configuration |
| project の settings.json で渡せるもの | `env`（「すべての session とその subprocess に設定する」） | https://code.claude.com/docs/en/settings-reference.md#env |
| `env` は hook と Bash に届くか | 届く（実測: 2.1.312 の `claude -p`、SessionStart・PreToolUse の hook と Bash ツールの 3 つとも settings の値） | heyapro-app の作業ツリーの `.tmp/env-probe` |
| シェルの環境変数と同じ名前なら | **settings の値が勝つ**（実測: シェルで `B=from-shell` を渡しても 3 か所とも `from-settings`） | 同上 |
| settings.local.json の env | settings.json の env に名前ごとに勝つ（実測） | 同上 |
| 入れ方の名前 | `<plugin>@<配布元>`。配布元の名前は marketplace.json の `name` | https://code.claude.com/docs/en/settings-reference.md#extraknownmarketplaces |
| 旧名を案内だけで残す仕組み | 無い（「deprecation state は無い」）。改名の `renames` は同じ配布元の中だけ。**今回は配布元ごと別なので使わない** | https://code.claude.com/docs/en/plugins/host-marketplace.md#rename-or-remove-a-plugin |
| skill を project で止める | `skillOverrides`（"off" など。どの settings にも書ける。2.1.129）。台帳のリポで `github-project` を隠したいときに使える | https://code.claude.com/docs/en/settings-reference.md#skilloverrides |

`env` がシェルより強いので、settings.json に `HC_NOTIFY` を書くと、コーディネーターが `HC_NOTIFY=off claude` で開いても orca になる（`bin/hirai-notify` の説明「だからコーディネーターは HC_NOTIFY=off で開く」が効かなくなる）。だから settings の名前は `TKM_HARNESS_*`、一時の上書きは今の `HC_*` のまま分ける。

## 4. 設計

### 4.1 リポの作り方

- 新しいリポ thirai-classlab/tkm-harness（公開）の main は、hirai-method-lite の `feat/2021-feature-unit`（c345922・hirai-lite 3.3.0 と hirai-project-method 1.2.1）を**履歴ごと**そのまま置いた（2026-11-26）。理由: (1) 取り込んだ file の `git log`・`git blame` が続く（ハーネスの検査は blame で過去の行を当て直す） (2) hirai-method-lite にあとから入る直し（#2020 の PR #19 など）を普通の merge で取り込める
- 1 つにする直しはすべて branch から main への PR で入れる。merge と tag（`tkm-harness--v4.0.0`）はテックリードの承認のあと
- 元リポ thirai-classlab/hirai-method（install.sh の旧ハーネス）は使わない

### 4.2 中身の移し先

| いま（hirai-method-lite の足すプラグイン） | 4.0.0（tkm-harness の中） |
|---|---|
| `plugins/hirai-project-method/bin/hirai-task` | `bin/hirai-task`（道具の名前は変えない） |
| `commands/board.md`・`project-setup.md` | `commands/`（`/tkm-harness:board`・`:project-setup`） |
| `skills/github-project/` | `skills/github-project/`（skill は 3 本で上限 3 に収まる） |
| `hooks/coordinator-load.sh` と hooks.json | `hooks/` に足し、hooks.json を 1 本に。hook は 6 本になり、smoke case 6 の上限 5 を 6 に上げる |
| `scripts/ghp-path.sh`・`hirai_*.py` | `scripts/` |
| `docs/rules-reference/approval-view.md`・`glossary.md`・`project-setup.md` | `docs/rules-reference/` |
| `tests/smoke.sh` | `tests/smoke-tasks.sh` |
| `plugin.json` の `dependencies` | 無くなる |

配布の一覧は name `tkm-harness`・plugin 1 つ（`tkm-harness`・source `./`）。

### 4.3 settings.json の形（導入先）

```json
{
  "enabledPlugins": { "tkm-harness@tkm-harness": true },
  "extraKnownMarketplaces": {
    "tkm-harness": { "source": { "source": "github", "repo": "thirai-classlab/tkm-harness" }, "autoUpdate": true }
  },
  "env": {
    "TKM_HARNESS_TASKS": "github-project",
    "TKM_HARNESS_WORKTREE": "block",
    "TKM_HARNESS_NOTIFY": "orca"
  }
}
```

fork（例 classlab-inc/tkm-harness）へ替えるときは `extraKnownMarketplaces.tkm-harness.source.repo` の 1 か所だけを替え、各自 `claude plugin marketplace update tkm-harness`。配布元の名前は fork でも tkm-harness のままなので、`enabledPlugins` の鍵は変わらない（未検証: 同じ名前の配布元の取得元を替えたときの Claude Code の動き。替える前に使い捨ての HOME で確かめる）。

### 4.4 heyapro-app 側

- `.claude/settings.json`: `enabledPlugins` を `tkm-harness@tkm-harness` 1 つに、`extraKnownMarketplaces` に `tkm-harness`、`env` に 3 項目。mode.yml の `tasks:`・`worktree:`・`notify:` は入れ替えまでの間 hirai-lite 3.1.0 が読むので残す
- `scripts/gh-task.sh`: 探すのは `tkm-harness@tkm-harness` → 無ければ `hirai-project-method@hirai-lite`（merge から入れ替えまでの間も動く）
- `.claude/tasks-path.sh`・`.claude/statusline.sh`: 4.0.0 の写しに替える
- `/hirai-lite:` の言及: 現在形の文書と `.claude/` だけ `/tkm-harness:` に。凍った ADR・過去の draft・事故記録は触らない
- 入れ替えは merge のあとにコーディネーターが本体の checkout で打つ（1 行ずつ）:
  1. `claude plugin marketplace add thirai-classlab/tkm-harness`
  2. `claude plugin install tkm-harness@tkm-harness --scope project`
  3. `claude plugin uninstall hirai-project-method@hirai-lite --scope project --keep-data`
  4. `claude plugin uninstall hirai-lite@hirai-lite --scope project --keep-data`

### 4.5 hirai-method-lite 側（凍結と案内）

- README の先頭に「tkm-harness へ移りました。移し方は 4.4 の 4 行（範囲は入れた範囲）」の節を足す
- 配布の一覧から `hirai-lite-v2` の行を外す
- 中身（command・hook・script）は変えない。版も上げない（入れている 44 か所に更新が届かない）

## 5. 要判断

| # | 問い | 答え |
|---|---|---|
| 1 | 版の番号 | **4.0.0**（テックリード「版任せます」→ 推しの 4.0.0。hirai-lite 3.x の続きと分かり、`/update` の移し方の手順が版の大小で読める） |
| 2 | 配布元とリポの名前 | **tkm-harness**（新しいリポ thirai-classlab/tkm-harness。プラグインの名前も tkm-harness） |
| 3 | 別のプロジェクトの移し方 | **凍結**（hirai-method-lite は README の案内だけ。44 か所は触らない） |

## 6. 進め方

1. hirai-task の feature の扱い（TKM-R4）・settings.json の env の読み（TKM-R2）・進捗の表（TKM-R8）を hirai-method-lite の branch で作り、この branch に merge で取り込む
2. 1 つにする直し・名前の付け替え（`hirai-lite`・`hirai-project-method`・`HIRAI_METHOD_*` → `tkm-harness`・`TKM_HARNESS_*`）・fork しやすさ（TKM-R5）・配布の一覧・README・CHANGELOG
3. #2020（hirai-method-lite の PR #19）が hirai-method-lite に入ったら、merge で取り込む
