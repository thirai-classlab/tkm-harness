# プロジェクトの設定を settings.json の env に集め、settings.local.json で上書きする（4.1.0）

id_prefix: TKS
kind: ハーネス・進め方
domain: —
implements: README.md「やることの形と Orca の設定」, commands/config.md, scripts/tasks-path.sh, bin/hirai-task
decisions: heyapro-app feature #2052（テックリード 2026-11-26 の決定）
upstream: docs/draft/tkm-harness.md（TKM-R2。R2.5 をこのメモが置き換える）
downstream: heyapro-app の移行（同じ feature #2052 の PR）
supersedes: docs/draft/tkm-harness.md の TKM-R2.5
wave: —
status: 起案
approvals: 要件=feature #2052 設計=feature #2052 task=feature #2052
approved_at: 2026-11-26（テックリードの原文。下の「決まったこと」）
merged_into:

起案: 2026-11-26（heyapro-app #2052 の作業ツリー 2052-settings-local）。

## 1. 問題

### 提案: プロジェクトごとの設定を `.claude/settings.json` の `env` に集め、各自の `.claude/settings.local.json` で上書きし、進め方（mode）は settings.local.json に置く

**決めること**: 設定の置き場を settings.json の env（土台）と settings.local.json の env（上書き）にし、mode は settings.local.json に書くか。**推奨**: 承認する（テックリードが 2026-11-26 に決めた）

**目的**: プロジェクトに依存する設定を 1 か所で見て変えられ、各自の好み（進め方）はリポに入れずに持てる

**位置**: ハーネスの改善。tkm-harness 4.1.0 と heyapro-app の 2 本の PR

**承認すると**: mode・auto_sync・Project の番号・リポ・進みの表の期限と本線が settings の env で決まる。mode.yml は無いときの予備になる。戻せる

**しないと**: 設定が mode.yml・settings.json・導入先の scripts の 3 か所に散ったまま。Project の番号は毎回 GitHub に問い合わせて探す（GraphQL を 1 回使う）

## 決まったこと（テックリード 2026-11-26・原文）

- 「プロジェクト依存系はsetting.jsonに集約したい。」
- 「すべてsetting.json>setting.local.jsonで上書きが良いかと思います。modeはlocal.jsonを上書きするように変更して下さい。」
- 「プロジェクトもsetting.jsonで指定できたほうが良いです。」
- heyapro-app の `scripts/gh-task.sh` の扱い（A 今のまま／B 薄い入口にして残す／C なくす）に「B」
- 「`hirai-task assign` が feature を受け付けない」穴に「#2052に含めて対応して下さい。」

## 2. 確かめた事実（Claude Code 2.1.312）

| # | 事柄 | 公式の文書 | 実測（使い捨てのリポ・`claude -p`） |
|---|---|---|---|
| F1 | settings.local.json は settings.json より上。env は変数ごとに上の層が勝ち、下の層にしかない変数は残る | https://code.claude.com/docs/en/settings.md （Settings precedence「Claude Code uses the value from the highest level that sets it.」「An `env` block inside a settings file is an ordinary key and follows the levels above.」）・ https://code.claude.com/docs/en/settings-reference.md#env （「when several files set a variable, the highest-precedence one applies」） | settings.json に A・B、settings.local.json に A・C → A=local・B=settings.json・C=local |
| F2 | 同じ名前ならシェルの環境変数より settings の env が勝つ | （文書の該当節は取り出せず未検証） | シェル `S=from-shell`・settings.json `S=from-settings-json` → S=from-settings-json（4.0.0 の ADR-0816 と同じ） |
| F3 | settings の env は hook と Bash ツールに届く | settings-reference.md#env「reach every subprocess Claude Code starts.」・ https://code.claude.com/docs/en/hooks.md 「A hook process inherits the parent environment」 | SessionStart・PreToolUse の hook と Bash に F1 と同じ値が届いた |
| F4 | 会話の途中で settings の file を保存すると、動いている会話の env に入る。変数を消しても、動いている会話からは消えない | https://code.claude.com/docs/en/env-vars.md 「A running session applies new and changed values to its environment when you save the file」「Removing a variable from the file doesn't unset it in a running session」 | 会話の途中で settings.local.json の A を書き換え・D を足す → 5 秒後の Bash と PreToolUse の hook に新しい A と D が届いた |
| F5 | git の worktree では、本体の checkout の settings.local.json も読む。本体の local ＞ worktree の local ＞ settings.json | （文書に記述なし） | 本体だけに local → worktree の会話に local の値。両方に local（同じ変数 A・worktree だけの E）→ A=本体の local・E=worktree の local |
| F6 | statusLine のコマンドに env が届くか | 文書に記述なし（未検証） | 画面下は `claude -p` で動かないので未測定。statusline は F7 の file 読みを持つので、届かなくても値は出る |

F4 から、`/tkm-harness:config` で settings の file に書いた値は、開き直さなくても同じ会話の次の Bash・hook から効く（4.0.0 の「開き直すまで古い」は誤り）。消したときだけ、開き直すまで古い値が残る。

## 3. 目指す状態

### 要件 TKS-R1: 設定は 1 本の順で決まる

- TKS-R1.1 効く順は上から「一時の上書き > env > 会話の途中で読む settings の file > mode.yml（移行用の予備）> 既定」
  1. 一時の上書き: シェルの `HC_<項目>`（mode・auto_sync・tasks・worktree・notify・load_on_start）、`HIRAI_TASK_PROJECT`・`HIRAI_TASK_REPO`（project・repo）
  2. 環境変数 `TKM_HARNESS_<項目>`（Claude Code の中では F1・F5 の順に重なった値）
  3. settings の file の `env.TKM_HARNESS_<項目>`: 本体の checkout の settings.local.json → toplevel の settings.local.json → toplevel の settings.json → `~/.claude/settings.json`（F5 と同じ向き。Claude Code の外の端末・CI と、2 が空のときに読む）
  4. `.claude/mode.yml` の `<項目>:`（mode・auto_sync・tasks・worktree・notify・load_*・nightly_ci。project・repo は無い）
  5. 既定
- TKS-R1.2 値の前後の空白は外す。許す値の決まった項目（mode・auto_sync・tasks・worktree・notify）で知らない値は、読む側が今までどおり扱う（mode は値をそのまま見せ、ほかは既定に倒す）

### 要件 TKS-R2: 項目と置き場

| 項目 | env の名前 | 値 | 既定 | `/tkm-harness:config` が書く先 |
|---|---|---|---|---|
| mode（進め方） | `TKM_HARNESS_MODE` | normal・loop | normal | settings.local.json（Claude Code が最初に読むもの。worktree なら本体の checkout の。F5） |
| auto_sync（更新後の入れ替え） | `TKM_HARNESS_AUTO_SYNC` | on・off | off | settings.json |
| tasks・worktree・notify | `TKM_HARNESS_TASKS`・`_WORKTREE`・`_NOTIFY` | 4.0.0 と同じ | 4.0.0 と同じ | settings.json（4.0.0 と同じ） |
| project（GitHub Project の番号） | `TKM_HARNESS_PROJECT` | 正の整数 | 無し（リポに紐づいた Project を探す） | settings.json |
| repo（owner/リポ） | `TKM_HARNESS_REPO` | `<owner>/<name>` | `git remote get-url origin` | settings.json |
| 進みの表の期限と本線 | `TKM_HARNESS_LOAD_DEADLINE`・`_LOAD_DEADLINE_LABEL`・`_LOAD_MAINLINE`・`_LOAD_MAINLINE_LABEL` | 4.0.0 と同じ | 空 | settings.json（手で書く） |
| 前夜の CI | `TKM_HARNESS_NIGHTLY_CI` | workflow のファイル名 | 空 | settings.json（手で書く） |

- TKS-R2.1 Given settings.local.json に `TKM_HARNESS_MODE=loop` When 会話を開く Then 開始時の表示・画面下・毎ターンの reminder が loop（mode.yml に mode が無くても）
- TKS-R2.2 Given settings.json に `TKM_HARNESS_PROJECT=7` When `hirai-task ready` Then Project を探す問い合わせ（`Repository.projectsV2`）を打たず #7 を使う。値が正の整数でないときは exit 2 で理由を出す（黙って探しに行かない）
- TKS-R2.3 Given settings.json に `TKM_HARNESS_REPO=o/r` When hirai-task を打つ Then o/r を対象にする。無ければ作業ツリーのルートの `git remote get-url origin`（今いるディレクトリでなく `_root()` で引く）
- TKS-R2.4 `/tkm-harness:config` の 1（mode）は settings.local.json の env に、7-b（auto_sync）は settings.json の env に、1 つのキーだけを書く。書いたら同じ会話の次の Bash から効く（F4）。mode.yml の同じ項目の行は消さない（移行用の予備。値が settings と違うときは 1 行で知らせる）

### 要件 TKS-R3: mode.yml は予備

- TKS-R3.1 Given settings にも env にも mode が無く、mode.yml に `mode: loop` When 会話を開く Then loop（4.0.0 と同じ動き）
- TKS-R3.2 Given mode.yml にだけ値がある項目 When 会話を開く Then 開始時に 1 行「settings の env へ移せます」（4.0.0 の HM-R2.4 を mode・auto_sync・load_* に広げる。mode は settings.local.json へ）
- TKS-R3.3 `/tkm-harness:update` の移しは、auto_sync・load_*・nightly_ci を settings.json の env へ、mode を settings.local.json の env へ写す（移した先にすでに値があれば写さない）。mode.yml の行は消さない（チームの mode.yml の mode を消すと、settings.local.json を持たない人が normal に戻るため）

### 要件 TKS-R4: `hirai-task assign` は feature も受け付ける（ADR-0815 で割り振りの単位が feature になった）

- TKS-R4.1 Given 種別=feature の open の issue When `hirai-task assign <feature> <担当> [順]` Then 手元の控えに書く（wave は今までどおり断る）
- TKS-R4.2 Given 控えに feature がある When assign のあとの進みの表（load）Then その担当の行に feature が出て、段は task と同じ決め方（その feature を Closes する PR と issue の実物）で決まる

## 4. 採らなかった案

- mode を settings.json に置く: チームの共有の file を、各自が進め方を変えるたびに書き換えることになる（決まったことの「modeはlocal.json」に合わない）
- mode.yml の行を移したときに消す: settings.local.json を持たない人の進め方が黙って normal に戻る。予備として残し、効く順で settings を先にする
- 会話の途中の値を file から先に読む（env より file を先）: F4 で保存した値は env に入るので要らない。file を先にすると、Claude Code が重ねた値（F1・F5）と別の順を自分で組むことになる
