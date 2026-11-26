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
- 振り出しのあとに進みの表が出なかった件（AI が出力を切り、出し忘れた）に「仕組みで解決しておいて下さい。」

## 2. 確かめた事実（Claude Code 2.1.312）

| # | 事柄 | 公式の文書 | 実測（使い捨てのリポ・`claude -p`） |
|---|---|---|---|
| F1 | settings.local.json は settings.json より上。env は変数ごとに上の層が勝ち、下の層にしかない変数は残る | https://code.claude.com/docs/en/settings.md （Settings precedence「Claude Code uses the value from the highest level that sets it.」「An `env` block inside a settings file is an ordinary key and follows the levels above.」）・ https://code.claude.com/docs/en/settings-reference.md#env （「when several files set a variable, the highest-precedence one applies」） | settings.json に A・B、settings.local.json に A・C → A=local・B=settings.json・C=local |
| F2 | 同じ名前ならシェルの環境変数より settings の env が勝つ | （文書の該当節は取り出せず未検証） | シェル `S=from-shell`・settings.json `S=from-settings-json` → S=from-settings-json（4.0.0 の ADR-0816 と同じ） |
| F3 | settings の env は hook と Bash ツールに届く | settings-reference.md#env「reach every subprocess Claude Code starts.」・ https://code.claude.com/docs/en/hooks.md 「A hook process inherits the parent environment」 | SessionStart・PreToolUse の hook と Bash に F1 と同じ値が届いた |
| F4 | 会話の途中で settings の file を保存すると、動いている会話の env に入る。変数を消しても、動いている会話からは消えない | https://code.claude.com/docs/en/env-vars.md 「A running session applies new and changed values to its environment when you save the file」「Removing a variable from the file doesn't unset it in a running session」 | 会話の途中で settings.local.json の A を書き換え・D を足す → 5 秒後の Bash と PreToolUse の hook に新しい A と D が届いた |
| F5 | git の worktree では、本体の checkout の settings.local.json も読む。本体の local ＞ worktree の local ＞ settings.json | （文書に記述なし） | 本体だけに local → worktree の会話に local の値。両方に local（同じ変数 A・worktree だけの E）→ A=本体の local・E=worktree の local |
| F6 | statusLine のコマンドに env が届くか | 文書に記述なし（未検証） | 画面下は `claude -p` で動かないので未測定。statusline は F7 の file 読みを持つので、届かなくても値は出る |
| F7 | hook の JSON の `systemMessage` は人の画面に出て、AI の context には入らない | https://code.claude.com/docs/en/hooks.md の「JSON output」の表「`systemMessage` … Warning message shown to the user. In Agent SDK and `--output-format stream-json` output, it can arrive as an `SDKInformationalMessage`」・「To surface a message to the user on any platform, return `systemMessage` in JSON output.」 | PostToolUse(Bash) の hook が 1 つの JSON に `systemMessage` と `hookSpecificOutput.additionalContext` を両方出す形で、(a) 対話の画面（Orca の端末で `claude` を開いて読んだ）: Bash の結果の下に `PostToolUse:Bash says: <1 行目>` と続く行がそのまま出た（Markdown の表としては描かれず文字のまま）。(b) `claude -p --output-format stream-json --verbose`: `{"type":"system","subtype":"informational","level":"notice","content":"PostToolUse:Bash says: …"}` で流れ、各行の頭に `PostToolUse:Bash says: ` が付いた。AI は systemMessage の印を見ていない |
| F8 | PostToolUse の `additionalContext` は AI の context に入り、画面には出ない。上限は欄ごとに 10,000 字（超えると file に退避され、先頭 2,000 字だけ） | hooks.md の「Add context for Claude」「The `additionalContext` field passes a string from your hook into Claude's context window. … it doesn't appear as a chat message in the interface.」「PreToolUse, PostToolUse, … : next to the tool result」・「JSON output」の「capped at 10,000 characters」 | 上の (b) で AI は additionalContext の印だけを見た（「CTX-MARKER が見えた」と答えた） |

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

### 要件 TKS-R5: 進みの表は、振り出しと完了のあとに仕組みで出る（テックリード 2026-11-26「仕組みで解決しておいて下さい。」）

- TKS-R5.1 Given コーディネーターの会話（`hirai-task is-coordinator` が exit 0。親がいない・tasks が github-project） When Bash で振り出し（`orca orchestration worker-start`・`orca worktree set … --issue`・`hirai-task assign`・`hirai-task start`）か完了（`hirai-task done`・`hirai-task after-merge`・`gh pr merge`）を打った Then PostToolUse の hook が `hirai-task load --cached`（GitHub を叩かない）を回し、表を `systemMessage`（人に見える）と `additionalContext`（AI に入る）の両方で出す。AI が出力を `tail` で切っても、表を貼り忘れても、人の画面に表が出る
  - hirai-task は導入先の入口（`bash scripts/gh-task.sh start 12` のように hirai-task へ引数を渡す script）からも呼ばれるので、コマンドの中の `hirai-task <サブコマンド>` と `gh-task.sh <サブコマンド>` の両方を見る
- TKS-R5.2 Given 担当の会話（親がいる）・判定できない会話・GitHub Project で回さないリポ・対象でないコマンド When Bash Then 1 バイトも出さない。`load --cached` が失敗・時間切れ・空なら 1 バイトも出さない（常に exit 0）
- TKS-R5.3 既存の「知らせの受領で `load --changed` を促す 1 行」（`orca orchestration check` に msg_ があるとき）とは重ならない: 1 回の Bash で出す JSON は 1 つ。両方に当たる複合のコマンドは表を出す側だけ
- TKS-R5.4 hook は増やさない（数の予算の上限 6。今の `hooks/coordinator-load.sh` を広げる）。hook の時間切れ（hooks.json の 10 秒）より前に終わる（load は 8 秒で切る）。各欄は 10,000 字の内に収め、超えるなら末尾を切って「（続きは hirai-task load）」の 1 行にする

### 要件 TKS-R6: 表の担当は Orca の作業ツリーから取る

- TKS-R6.1 Given issue を紐づけた Orca の作業ツリー（`orca worktree list --json` の `linkedIssue`。main と archived を除き、`projectId` が `github:<リポ>` のもの） When `hirai-task load`（`--cached` も） Then その作業ツリーの表示名（`displayName`）を担当にして、その issue の行を出す。`hirai-task assign` の控えは補い（Orca に紐づきの無い番号の担当と、順番）。Orca が無い・exit が 0 でない・JSON が読めない・3 秒で返らないときは控えだけ（今と同じ）
- TKS-R6.2 Given 担当が feature に直接付いている（Orca の linkedIssue が feature・控えが feature） When load Then その feature の行が出る。段は、その feature を `Closes` する PR があれば task と同じ決め方、無ければ Status（承認待ち・着手可 → 0、進行中 → 20、レビュー中 → 60、完了か閉じた → 100）。セクションは、その feature の親の wave の名前（今は「—」になる）
- TKS-R6.3 全体の %（sections の total・done）は今のまま task だけで数える（feature を足して二重に数えない）

## 4. 採らなかった案

- mode を settings.json に置く: チームの共有の file を、各自が進め方を変えるたびに書き換えることになる（決まったことの「modeはlocal.json」に合わない）
- mode.yml の行を移したときに消す: settings.local.json を持たない人の進め方が黙って normal に戻る。予備として残し、効く順で settings を先にする
- 会話の途中の値を file から先に読む（env より file を先）: F4 で保存した値は env に入るので要らない。file を先にすると、Claude Code が重ねた値（F1・F5）と別の順を自分で組むことになる
