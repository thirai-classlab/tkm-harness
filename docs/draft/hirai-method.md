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

### 提案: 土台と足す部品の 2 つのプラグインを hirai-method 1 つにし、機能の切り替えを各リポの `.claude/settings.json` に置く

**決めること**: hirai-lite と hirai-project-method を hirai-method にまとめ、機能を settings.json で切り替えるか。**推奨**: 承認する（テックリードが 2026-11-25 に決めた）

**目的**: プラグインを 1 行で入れられ、2 つの版のずれ（hirai-task の探し方・取り込むと前の版が止まる）が無くなる

**位置**: ハーネスの改善。このリポと heyapro-app の 2 本の PR

**承認すると**: 名前が hirai-method、command が `/hirai-method:…` になる。hirai-lite を入れている別のプロジェクトは何も変わらない。戻せる

**しないと**:
- 足す部品は土台の版に依存し（`plugins/hirai-project-method/.claude-plugin/plugin.json` の `dependencies`）、hirai-task の探し方が 3 か所に分かれている（`scripts/tasks-path.sh:401`・`scripts/update-check.sh:62`・heyapro-app の `scripts/gh-task.sh:97`）

**注意**: 機能の切り替えに使える settings.json の項目は `env` だけ（§3）。`env` はシェルの環境変数より強いので、一時の上書き（`HC_*`）とは名前を分ける

## 2. 目指す状態

### 追加された要件

### 要件 HM-R1: 利用者は、1 つのプラグイン hirai-method を入れるだけで、土台・GitHub Project のタスク管理・Orca の機能を使える
- HM-R1.1 Given 何も入っていないリポ When `/plugin install hirai-method@hirai-lite` Then command・skill・hook・`bin/hirai-task` が全部入る（足すプラグインは要らない）
- HM-R1.2 Given hirai-method 4.x When command を打つ Then 名前は `/hirai-method:…`（`/hirai-method:board`・`/hirai-method:project-setup` も同じプラグインの中）

### 要件 HM-R2: プロジェクトの機能は、各リポの `.claude/settings.json` の `env` で切り替える
- HM-R2.1 Given `.claude/settings.json` に `"env": {"HIRAI_METHOD_TASKS": "github-project"}` When 会話を開く Then タスク管理は GitHub Project の形で動く（無ければ台帳）
- HM-R2.2 同じく `HIRAI_METHOD_WORKTREE`（off / warn / block）・`HIRAI_METHOD_NOTIFY`（off / orca）
- HM-R2.3 優先は「シェルの `HC_TASKS`・`HC_WORKTREE`・`HC_NOTIFY`（一時の上書き）> `settings.local.json` の env > `settings.json` の env > `.claude/mode.yml` の `tasks:`・`worktree:`・`notify:`（4.x の間だけ読む移行用）> 既定」
- HM-R2.4 Given mode.yml にだけ 3 項目がある When 会話を開く Then 開始時の 1 行に「settings.json へ移せます（/hirai-method:config）」と出る。`/hirai-method:config` は settings.json の env に書く
- HM-R2.5 進め方（`mode`）・`auto_sync`・表の設定（`load_*`・`nightly_ci`）は mode.yml に残す（切り替えるたびに共有の settings.json を書き換えないため）

### 要件 HM-R3: hirai-task は同じプラグインの `bin/` にあり、探し方は 1 本
- HM-R3.1 Given hirai-method が入ったリポ When hook・statusline・command が hirai-task を探す Then `installed_plugins.json` の `hirai-method@hirai-lite` のこのリポの行の最大版の `bin/hirai-task` を使う

### 要件 HM-R4: hirai-task は feature を `start`・`ready` でき、目印と coverage を feature で読む（heyapro-app #2021 の 2 回目の問い）
- HM-R4.1 Given 着手可の feature When `hirai-task start <feature>` Then Status が 進行中 になる（今は task だけ）
- HM-R4.2 Given 着手可の feature で子の task が無い When `hirai-task ready` Then その feature が着手できるものに出る
- HM-R4.3 Given 目印・coverage の検査 When feature の PR Then feature の本文のチェックリストを読む

### 要件 HM-R5: hirai-lite を入れている別のプロジェクトは何も変わらない
- HM-R5.1 Given 別のプロジェクトの hirai-lite（1.14〜3.1）・hirai-project-method When marketplace を更新 Then 凍結した ref のまま動く（名前の付け替え `renames` は書かない。§5 の判断 3）
- HM-R5.2 marketplace から hirai-lite-v2 の行を外す（入っている 2 か所はそのまま動く。更新が来なくなるだけ）

### 要件 HM-R6: 責務分離を README と heyapro-app の docs/harness に書く
- HM-R6.1 3 つの層: hirai-method の土台（決まりの予算・進め方・確認・画面下）／ タスク管理の機能（hirai-task・board・project-setup）／ 各リポのハーネス（そのリポの決まり・検査・hook・skill）

## 3. 公式で確かめたこと・実測

| 問い | 答え | 出典 |
|---|---|---|
| プラグインの設定項目（`userConfig`）を project の settings.json に置けるか | 置けない。値は user（か managed）の `pluginConfigs` にだけ入り、project からの読み取りは 2.1.207 で廃止 | https://code.claude.com/docs/en/settings-reference.md#pluginconfigs ・ https://code.claude.com/docs/en/plugins/manifest-reference.md#user-configuration |
| project の settings.json で渡せるもの | `env`（「すべての session とその subprocess に設定する」） | https://code.claude.com/docs/en/settings-reference.md#env |
| `env` は hook と Bash に届くか | 届く（実測: 2.1.312 の `claude -p`、SessionStart・PreToolUse の hook と Bash ツールの 3 つとも settings の値） | `.tmp/env-probe`（heyapro-app の作業ツリー） |
| シェルの環境変数と同じ名前なら | **settings の値が勝つ**（実測: シェルで `B=from-shell` を渡しても 3 か所とも `from-settings`） | 同上 |
| settings.local.json の env | settings.json の env に名前ごとに勝つ（実測） | 同上 |
| 名前の付け替え | marketplace.json の `renames`（旧名 → 新名）で、各範囲の `enabledPlugins` の旧キーが書き換わる（2.1.193）。旧名を「案内だけ」で残す公式の仕組みは無い | https://code.claude.com/docs/en/plugins/host-marketplace.md#rename-or-remove-a-plugin |
| 旧名の行を別の ref に固定 | 根の plugin は `url`＋`ref`、下の dir の plugin は `git-subdir`（`url`・`path`・`ref`） | https://code.claude.com/docs/en/plugins/marketplace-reference.md#git-subdir-plugin-source |
| skill を project で止める | `skillOverrides`（"off" など。どの settings にも書ける。2.1.129） | https://code.claude.com/docs/en/settings-reference.md#skilloverrides |

`env` がシェルより強いので、settings.json に `HC_NOTIFY` を書くと、コーディネーターが `HC_NOTIFY=off claude` で開いても orca になる（`bin/hirai-notify` の説明「だからコーディネーターは HC_NOTIFY=off で開く」が効かなくなる）。だから settings の名前は `HIRAI_METHOD_*`、一時の上書きは今の `HC_*` のまま分ける。

## 4. 設計

### 4.1 中身の移し先

| いま（足すプラグイン） | 4.0.0（hirai-method の中） |
|---|---|
| `plugins/hirai-project-method/bin/hirai-task` | `bin/hirai-task` |
| `commands/board.md`・`project-setup.md` | `commands/`（`/hirai-method:board`・`:project-setup`） |
| `skills/github-project/` | `skills/github-project/`（skill は 3 本で上限 3 に収まる） |
| `hooks/coordinator-load.sh` と hooks.json | `hooks/` に足し、hooks.json を 1 本に。hook は 6 本になり、smoke case 6 の上限 5 を 6 に上げる |
| `scripts/ghp-path.sh`・`hirai_*.py` | `scripts/` |
| `docs/rules-reference/project-setup.md` | `docs/rules-reference/` |
| `tests/smoke.sh` | 土台の `tests/smoke.sh` の case に入れる（case の上限 10 は超えない形で） |
| `plugin.json` の `dependencies` | 無くなる |

`plugins/hirai-project-method/` は main から消す。足すプラグインの行は凍結した tag を `git-subdir` で指す。

### 4.2 settings.json の形（導入先）

```json
{
  "enabledPlugins": { "hirai-method@hirai-lite": true },
  "env": {
    "HIRAI_METHOD_TASKS": "github-project",
    "HIRAI_METHOD_WORKTREE": "block",
    "HIRAI_METHOD_NOTIFY": "orca"
  }
}
```

読むのは `scripts/tasks-path.sh` の `harness_tasks_form` と、同じ形の `harness_worktree`・`harness_notify`（新設。`hooks/worktree-guard.sh`・`bin/hirai-notify`・`hooks/session-start.sh`・`scripts/statusline.sh` が今 mode.yml を直接読んでいる所をこの 2 つに寄せる）。

### 4.3 marketplace（判断 2・3 の推しのとき）

```json
"plugins": [
  { "name": "hirai-method", "source": "./", "version": "4.0.0" },
  { "name": "hirai-lite", "source": { "source": "url", "url": "https://github.com/thirai-classlab/hirai-method-lite.git", "ref": "hirai-lite--v3.1.0" }, "description": "退役。hirai-method へ移る（3.x は tag に凍結）" },
  { "name": "hirai-project-method", "source": { "source": "git-subdir", "url": "https://github.com/thirai-classlab/hirai-method-lite.git", "path": "plugins/hirai-project-method", "ref": "hirai-project-method--v1.2.0" }, "description": "退役。hirai-method の中に入った" }
]
```

`hirai-lite-v2` の行は外す。`renames` は書かない。2 つの tag はどちらも origin に在る（`git ls-remote --tags origin`）。`hirai-lite--v3.1.0` と今の main の差は marketplace.json と README の 12 行だけで、プラグインの中身は同じ（`git diff --stat hirai-lite--v3.1.0 origin/main -- . ':!plugins'`）。

### 4.4 heyapro-app 側

- `.claude/settings.json`: `enabledPlugins` を `hirai-method@hirai-lite` 1 つに、`env` に 3 項目。mode.yml の `tasks:`・`worktree:`・`notify:` は消す
- `scripts/gh-task.sh`: 探すのは `hirai-method@hirai-lite` → 無ければ `hirai-project-method@hirai-lite`（merge から入れ替えまでの間も動く）
- `.claude/tasks-path.sh`・`.claude/statusline.sh`: 4.0.0 の写しに替える（v2 の控えの読みはそのまま残る）
- `/hirai-lite:` の言及: 現在形の文書と `.claude/` だけ `/hirai-method:` に。凍った ADR・過去の draft は触らない
- 入れ替えは merge のあとにコーディネーターが打つ（1 行ずつ）:
  1. `claude plugin marketplace update hirai-lite`
  2. `claude plugin install hirai-method@hirai-lite --scope project`
  3. `claude plugin uninstall hirai-project-method@hirai-lite --scope project --keep-data`
  4. `claude plugin uninstall hirai-lite@hirai-lite --scope project --keep-data`

## 5. 要判断

| # | 問い | 推し | 理由 |
|---|---|---|---|
| 1 | 版の番号 | **4.0.0**（hirai-lite の続き） | 同じリポ・同じ CHANGELOG の続き。`/update` の移し方の手順は版の大小で分かれ（「1.x・2.x から 3.0.0 へ」）、1.0.0 だと 3.1.0 より古く見える。tag は `hirai-method--v4.0.0`。副作用: 凍結した 1.x・3.x は main の `VERSION` を 1 日 1 回読む（`scripts/update-check.sh:15`）ので、開始時に「更新あり v3.1.0 → v4.0.0」と出る。これが移れることの知らせになるが、書いてある `/hirai-lite:update` では上がらない（README の移し方へ）。1.0.0 なら何も出ない |
| 2 | 配布元の名前 | **hirai-lite のまま**（`hirai-method@hirai-lite`） | 配布元の名前を変えると、入れている 45 行（rmp-app を除く 44 行は別のプロジェクトとその worktree）の `@hirai-lite` が引けなくなる（`installed_plugins.json` の実数）。元リポ thirai-classlab/hirai-method は install.sh のハーネスで配布元ではない（`.claude-plugin/` が無い）ので、名前は重なっても引き違えない。README に「別物」と 1 行書く |
| 3 | 別のプロジェクトの移し方 | **凍結して各自で移す**（`renames` を書かない） | `renames` を書くと、別のプロジェクトの hirai-lite（1.14〜3.1）が次の更新で黙って 4.0.0 に替わり、各リポに写した決まりの `/hirai-lite:…` が切れる。凍結すれば何も変わらず、移すときは §4.4 の 4 行と `/hirai-method:update` |

## 6. 進め方

1. 判断を待つ間: hirai-task の feature の `start`・`ready`・目印と coverage（HM-R4）、責務分離の文書（HM-R6）、`harness_worktree`・`harness_notify` の新設と env の読み（HM-R2）
2. 判断のあと: 名前の付け替え・中身の移し・marketplace・README・CHANGELOG・tag
3. heyapro-app #2021 の branch が push されたら、その上に重ねる（`rules/code.md`・`commands/commit.md`・`docs/rules-reference/task-ledger.md`・`templates/draft.md`・`skills/github-project/SKILL.md`・`docs/rules-reference/project-setup.md` はそれまで触らない）
