---
description: 設定の確認と変更。mode（進め方）/ ultracode / 常時読まれる量 / 置き場所 / statusLine（画面下部の情報表示）/ 更新の確認 / 更新の自動化 を一覧し、選ばれた項目だけ書き換える。
argument-hint: [mode normal|loop]
disable-model-invocation: true
---

# /config [mode normal|loop]

いまの設定を一覧で見せ、変えたいものだけ書き換える。**変える前に必ず「どのファイルが変わるか」を伝えてから実行する。** 出力は平易な日本語だけにし、内部の呼び名 (層 / frontmatter / scope / exit code など) は出さない。

**表記のきまり。** 設定の名前と値は **`<正式名>（<短い解説>）`** の形で出す (正式名だけだと意味が伝わらず、解説だけだと設定ファイルの中身と結び付かない)。`mode（進め方）` / `normal（確認あり）` / `loop（自動で進む）` / `ultracode（深く考えて自動で手分けする。利用量が増える）` / `statusLine（画面下部の情報表示）`。同じ 1 通のなかで 2 回目からは正式名だけでよい。

## 読み取り (ここでは 1 バイトも書き換えない)
設定は `.claude/settings.json` の `env` に集まる（mode だけは各自の `.claude/settings.local.json`。効く順は README「設定の置き場と効く順」）。**解決を自分で組み立てず**、セッション冒頭・画面下部と同じ共通ライブラリに任せる。
```bash
P="${CLAUDE_PLUGIN_ROOT}"; [ -d "$P" ] || P="$(command -v python3 >/dev/null 2>&1 && python3 -I -c 'import json,re,sys; d=json.load(open(sys.argv[1])); r=[x for k,v in d.get("plugins",{}).items() if k.split("@",1)[0]==sys.argv[2] for x in v if x.get("installPath")]; r.sort(key=lambda x:[int(n) if n.isdigit() else 0 for n in re.split(r"[.]", str(x.get("version","0")).split("-",1)[0])]); print(r[-1]["installPath"] if r else "")' "$HOME/.claude/plugins/installed_plugins.json" tkm-harness 2>/dev/null)"; [ -d "$P" ] || P="$(ls -d "$HOME"/.claude/plugins/cache/*/tkm-harness/*/ 2>/dev/null | sort -V | tail -1)"; P="${P%/}"
. "$P/scripts/tasks-path.sh"
R="$(harness_rules_dir "$PWD")"; D="$(dirname "$R")"
m="$(harness_mode "$PWD")"; case "$m" in normal) m="normal（確認あり）" ;; loop) m="loop（自動で進む）" ;; esac
echo "mode（進め方）: $m / 設定ファイル: $(harness_mode_write_file "$PWD")"
tform="$(harness_tasks_form "$PWD")"
if [ "$tform" = "github-project" ]; then
  [ -n "$(harness_pm_task_bin 2>/dev/null)" ] && ht="あり" || ht="なし（/plugin install tkm-harness@tkm-harness）"
  echo "設定一式の置き場: $D / やること管理: GitHub Project（tasks: github-project。hirai-task: $ht）"
else
  echo "設定一式の置き場: $D / やること一覧: $(harness_tasks_file "$PWD" || echo '(まだありません)')"
fi
echo "tasks: $tform / worktree: $(harness_worktree "$PWD") / notify: $(harness_notify "$PWD")"
echo "project: $(harness_setting project "$PWD" | grep . || echo '自動で探す') / repo: $(harness_setting repo "$PWD" | grep . || echo 'git remote')"
grep -q '"ultracode"[[:space:]]*:[[:space:]]*true' "$D/settings.json" 2>/dev/null && echo "ultracode: 有効" || echo "ultracode: 無効"
grep -q '"statusLine"' "$D/settings.json" 2>/dev/null && echo "statusLine（画面下部の情報表示）: 有効" || echo "statusLine（画面下部の情報表示）: 無効"
for f in CLAUDE.md "$HOME/.claude/CLAUDE.md" "$R"/*.md; do
  [ -f "$f" ] || continue
  head -5 "$f" | grep -q '^paths:' || wc -c "$f"
done | awk '{s+=$1} END {print "常時読まれる量:", int(s/3)}'
. "$P/scripts/update-check.sh"
[ "${HARNESS_UPDATE_CHECK:-on}" = off ] && echo "更新の確認: 無効" || echo "更新の確認: 有効"
date -r "$(harness_update_cache_dir "$P")/stamp" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "最後に確認: まだありません"
# 7-a プラグイン本体の自動更新は **Claude Code 本体の機能**（マーケットプレイス単位）。既定は無効。
#     置き場は settings.json の extraKnownMarketplaces.tkm-harness.autoUpdate で、
#     /plugin の Marketplaces タブの切り替えと同じ場所を読む（ここで独自の仕組みを作らない）。
au="無効"; auf=""
for f in .claude/settings.local.json .claude/settings.json "$HOME/.claude/settings.json"; do
  [ -f "$f" ] || continue
  v="$(python3 -I -c 'import json,sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
m = (d.get("extraKnownMarketplaces") or {}).get("tkm-harness")
print("" if not m else ("on" if m.get("autoUpdate") else "off"))' "$f" 2>/dev/null)"
  [ -n "$v" ] && { auf="$f"; [ "$v" = on ] && au="有効"; break; }
done
echo "プラグイン本体の自動更新: $au${auf:+ / 設定ファイル: $auf}"
# 7-b 更新後の入れ替え（ハーネス側）。既定は無効。.claude/settings.json の env TKM_HARNESS_AUTO_SYNC が決める。
as="$(harness_auto_sync "$PWD")"; case "$as" in on|true|yes) as="有効" ;; *) as="無効" ;; esac
echo "更新後の入れ替え: $as / 設定ファイル: $(harness_top "$PWD")/.claude/settings.json"
```

## 引数なし — 一覧を出す
下の型に**実測値**を埋めて出す (推測で埋めない)。

```
いまの設定

1. mode（進め方）      normal（確認あり）— 重要な分かれ道で聞いてから進みます
2. ultracode           有効（深く考えて自動で手分けする。そのぶん利用量が増えます）
3. 常時読まれる量      3,663 ／ 警告 6,000 ／ 上限 10,000
4. 置き場所            このプロジェクトのみ（.claude/）
                       やること一覧 → docs/tasks/list.md
5. statusLine（画面下部の情報表示）  有効
6. 更新の確認          有効（最後に確認したのは 2026-08-27 10:12）
7. 更新の自動化        プラグイン本体: 無効 ／ 更新後の入れ替え: 無効
                       どちらも既定は無効です（更新は動きの変更なので、黙って変えません）
8. 形と Orca           やること管理 → 台帳（tasks: ledger）
                       Orca の worktree → 見張らない（worktree: off）／ 知らせ → 送らない（notify: off）
                       GitHub Project → 自動で探す（project）／ リポ → git remote（repo）

番号か項目名を言ってもらえれば変更します（例:「1 を loop に」）。
```

- 1 は `loop` なら `loop（自動で進む）— 確認を求めず最後まで進みます`（`normal` / `loop` 以外の値はそのまま出す）。2 は無効なら `無効（利用量は増えません）`
- 3 は警告を超えていたら 1 行足す: `警告線を超えています。ルールを 1 件減らすことを勧めます`
- 4 は置き場が `~/.claude` なら `全プロジェクト共通（~/.claude/）`。台帳が無ければ `やること一覧 → まだありません`。`tasks: github-project` なら 2 行目を `やること管理 → GitHub Project（hirai-task: あり／なし）` に差し替える
- 6 は一度も調べていなければ `有効（まだ一度も確認していません）`
- 8 の project は番号（`TKM_HARNESS_PROJECT`）が入っていればその番号、無ければ `自動で探す`。repo は `<owner>/<name>`（`TKM_HARNESS_REPO`）が入っていればそれ、無ければ `git remote`
- 8 は `tasks` が `github-project` なら `GitHub Project（タスク管理の機能）`、`worktree` が `warn` なら `Orca の worktree でない会話に警告を出す`、`block` なら `Orca の worktree でない会話の、Edit・Write・NotebookEdit と git commit を止める（MCP の書き込みの道具と Bash でのファイルの書き換えは止めない）`、`notify` が `orca` なら `Orca のコーディネーターへ知らせる`
- 7 はどちらか一方でも有効なら、その行を `有効` に差し替えて 2 行目を `プラグイン本体が新しくなると自動で入れ替わります` にする

## 変更する
変えられるのは 1・2・5・6・7・8 の 6 つ（8 は tasks・worktree・notify・project・repo）。**3 と 4 は表示のみ**（3 は `/tkm-harness:add-rule`、4 は `/tkm-harness:init` の担当）。どれも「これから変わるファイル」を 1 行見せてから実行し、終わったら結果を 1 行で報告する。

### 1. mode（進め方）
`/tkm-harness:config mode loop` のように引数で直接指定してもよい（`進め方 確認あり` / `進め方 自動` のような日本語でも受け付ける）。mode は**各自の好み**なので、リポに入る `settings.json` には書かず、Claude Code が最初に読む **`.claude/settings.local.json`**（git に入らない）の `env.TKM_HARNESS_MODE` に 1 つだけ書く。git の worktree の会話からは**本体の checkout の** `.claude/settings.local.json` に書く（Claude Code は本体の settings.local.json も読むため、本体と全部の作業ツリーに効く）。`mode.yml` の `mode:` の行は消さない（移行用の予備。チームの mode.yml を消すと settings.local.json を持たない人が normal に戻るため）。
```bash
P="${CLAUDE_PLUGIN_ROOT}"; [ -d "$P" ] || P="$(command -v python3 >/dev/null 2>&1 && python3 -I -c 'import json,re,sys; d=json.load(open(sys.argv[1])); r=[x for k,v in d.get("plugins",{}).items() if k.split("@",1)[0]==sys.argv[2] for x in v if x.get("installPath")]; r.sort(key=lambda x:[int(n) if n.isdigit() else 0 for n in re.split(r"[.]", str(x.get("version","0")).split("-",1)[0])]); print(r[-1]["installPath"] if r else "")' "$HOME/.claude/plugins/installed_plugins.json" tkm-harness 2>/dev/null)"; [ -d "$P" ] || P="$(ls -d "$HOME"/.claude/plugins/cache/*/tkm-harness/*/ 2>/dev/null | sort -V | tail -1)"; P="${P%/}"
. "$P/scripts/tasks-path.sh"
f="$(harness_settings_set mode normal "$PWD")" && echo "変えたファイル: $f"   # 自動で進めるときは loop
harness_mode "$PWD" | cat   # HC_MODE を打ったシェルでは、その値が先に出る
y="$(harness_yml_value "$PWD" mode)"; [ -z "$y" ] || [ "$y" = "$(harness_mode "$PWD")" ] || echo "mode.yml の mode: は $y のまま（settings が先に効きます）"
```

報告書式: `normal（確認あり）にしました → <パス>。重要な分かれ道でひとこと確認してから進みます` ／ `loop（自動で進む）にしました → <パス>。確認を求めず最後まで進みます。止めたいときは「stop」`。書き込み先が `~/.claude/` の下だったときだけ 1 行足す: `この設定はすべてのプロジェクトに効きます`（mode はふつうホームに書かないので出ない）。worktree の会話から本体の checkout の settings.local.json に書いたときは 1 行足す: `本体と全部の作業ツリーに効きます`。`mode.yml` の値が違って残っているときは、上の最後の行を 1 行で知らせる。保存すると同じ会話の次の Bash・hook から新しい値が効く（開き直しは要らない）。

**`loop`（自動で進む）の間の振る舞い。** 作り方の選び方・branch 名・commit の件名・ビルドが通るまでの試行錯誤は聞かずに決める。止まるのは 3 つだけ（「stop」と言われた / やることが終わった / 続けられないエラー）。ただし新しい設計を足すとき・決めた内容から外れるとき・元に戻せない操作（`main` への push / PR の取り込み / 本番反映 / DB の作り替え / 秘密情報）は自動でも必ず確認を取る。作業を任せた相手を待つ間は別の作業を進め、会話の使用量が 50% に達したら `/tkm-harness:state save` を実行する。

`loop` にしたと報告するとき、1 行添える: `ターンをまたいで止まらずに続けさせたいときは、組み込みの /goal に終わりの条件を渡してください（例: `tasks: github-project` のリポは /goal hirai-task ready が空で、着手した task はすべて PR を出した。台帳のリポは /goal 台帳に未着手の行が無く、着手した task はすべて PR を出した）。終わったかは別のモデルが判定します`。`/goal` は組み込みのコマンドで Claude からは呼べないので、打つのは利用者。

### 2. ultracode（深く考えて自動で手分けする。利用量が増える）
`$D/settings.json` の `ultracode` を切り替える。**有効にすると利用量（費用）が増える。** 無効にするときは `ultracode` だけを外す（`workflowSizeGuideline` は ultracode と別の設定で、on・off のどちらでも効く）。設定ファイルを変えずにこの会話だけ試したいと言われたら、組み込みの `/effort ultracode on`（戻すときは `off`。Claude Code 2.1.284 以降。打つのは利用者）を案内する。書き換えたら `python3 -m json.tool "$D/settings.json"` を通し、失敗したら編集前へ戻す。

**費用に影響するので、有効にする前に承認を求める。** 本文に承認カード（**決めること・推奨 / 目的 / 位置 / 承認すると / しないと / 注意 / 詳しく**）をこの語で示してから `AskUserQuestion`（`承認する` / `承認しない` / `修正して提案し直す`）を出す。カードは本文に書き、選択肢の説明文に詰め込まない。型と記入例（`AskUserQuestion` が使えないときの平文の出し方も）は `docs/rules-reference/approval-template.md`（プロジェクトに無ければプラグイン同梱の同名ファイル）。**無効に戻すとき（費用が減る方向）と、利用者が自分から「有効にして」と言ったときは、この確認は要らない。** 実際に出す文面の例:

```
決めること: 自動で手分けする設定（ultracode）を有効にするか。推奨: 条件つき（1週間で見直す）
目的: 複数のファイルにまたがる調べものを、手で分けずに済ませる
位置: このプロジェクトの設定だけ。ほかのプロジェクトには効かない
承認すると: 次の会話から有効。利用量（費用）が増える。設定から外せば戻せる
しないと: 手分けを毎回こちらで指示する。品質が下がるとは限らない
注意: 増える量は測れていない（未確認）
詳しく: .claude/settings.json の ultracode（workflowSizeGuideline は別）
```

### 5. statusLine（画面下部の情報表示）／ 6. 更新の確認
5 は `$D/settings.json` の `statusLine`（消すと画面下部の 2 行が出なくなる）。ユーザー設定（`~/.claude/settings.json`）にも `statusLine` があるとき、プロジェクト側に書くとユーザー側の表示が隠れる。有効にする前にそのことを 1 行伝える。6 は環境変数 `HARNESS_UPDATE_CHECK=off` で止まる（設定ファイルは変えない）。どちらも変える前にファイル名か環境変数名を伝える。

### 7. 更新の自動化（既定は無効。有効にするかは利用者が決める）

**先に必ず伝える。** このプラグインは自動処理と決まりごとを配るので、更新は**動きの変更**になる。有効にすると、次にセッションを開いたとき、断りなく新しい版に入れ替わる。**迷うなら無効のままでよい**（`/tkm-harness:update` でいつでも手動更新できる）。2 つは独立しているので、片方だけ有効にしてもよい。

**有効にする前は、2（ultracode）と同じ承認の型を使う** — 承認カード（**決めること・推奨 / 目的 / 位置 / 承認すると / しないと / 注意 / 詳しく**）を本文に示してから `AskUserQuestion`（`承認する` / `承認しない` / `修正して提案し直す`）。文面の型は上の例に、詳細は `docs/rules-reference/approval-template.md` にある。**「しないと」には「手動更新のままになる（`/tkm-harness:update` で更新できる）」と正直に書く。** 無効に戻すときにこの確認は要らない。

**7-a プラグイン本体の自動更新 — これは Claude Code 本体の機能で、ハーネスは何もしない。**
`/plugin` → **Marketplaces** → `tkm-harness` → **Enable auto-update** で切り替える（元に戻すのは同じ場所の **Disable auto-update**）。**この案内を第一に出す。** Claude Code が起動後の背景で（最大 10 分の遅延を挟んで）マーケットプレイスの一覧とプラグイン本体を新しくする。**動いているセッションはそのまま**で、反映は `/reload-plugins` か次回起動から。

画面を開かずに切り替えたいと言われたときだけ、上の読み取りで見つかった `settings.json`（見つからなければ `.claude/settings.json`）の `extraKnownMarketplaces.tkm-harness.autoUpdate` を `true` / `false` に書き換える。**これは `/plugin` の切り替えと同じ場所**で、書いた値は起動時に Claude Code 側へ取り込まれる。書き換えたら `python3 -m json.tool "$f"` を通し、失敗したら編集前へ戻す。

```bash
f=.claude/settings.json   # 読み取りで見つかったファイルに差し替える
python3 - "$f" <<'PY'
import json, os, sys
p = sys.argv[1]; d = json.load(open(p))
mk = d.setdefault("extraKnownMarketplaces", {})
if "tkm-harness" not in mk:
    # 配布元の場所は、いま入っている配布元の source を写す（fork が別の owner で配っていてもそのまま当たる）
    ks = json.load(open(os.path.expanduser("~/.claude/plugins/known_marketplaces.json"))).get("tkm-harness", {}).get("source")
    if not ks:
        sys.exit("配布元 tkm-harness の source が known_marketplaces.json に無い。/plugin から切り替える")
    mk["tkm-harness"] = {"source": ks}
mk["tkm-harness"]["autoUpdate"] = True          # 止めるときは False
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
python3 -m json.tool "$f" >/dev/null && echo "OK $f"
```

報告書式: `プラグイン本体の自動更新を有効にしました → <パス>。次に開いたときから、Claude Code が背景で新しい版に入れ替えます（反映は入れ替えの次の起動から）`

**7-b 更新後の入れ替え — こちらがハーネスの受け持ち。**
プラグイン本体が新しくなっても、`/tkm-harness:init` で**導入先へ複製された** 3 本（`statusline.sh` / `tasks-path.sh` / `context-usage.sh`）は古いまま残る。有効にすると、**プラグインの版が変わった回のセッション冒頭だけ**、その 3 本を配布版に揃え、何件入れ替えたかを 1 行で報告する（中身が違うものは `.bak` に控えてから）。**決まりごと・安全設定・`CLAUDE.md`・やることの一覧表には触らない。** 版が同じ回は何もしない（手を入れた複製も、その版のうちは上書きされない）。

```bash
P="${CLAUDE_PLUGIN_ROOT}"; [ -d "$P" ] || P="$(command -v python3 >/dev/null 2>&1 && python3 -I -c 'import json,re,sys; d=json.load(open(sys.argv[1])); r=[x for k,v in d.get("plugins",{}).items() if k.split("@",1)[0]==sys.argv[2] for x in v if x.get("installPath")]; r.sort(key=lambda x:[int(n) if n.isdigit() else 0 for n in re.split(r"[.]", str(x.get("version","0")).split("-",1)[0])]); print(r[-1]["installPath"] if r else "")' "$HOME/.claude/plugins/installed_plugins.json" tkm-harness 2>/dev/null)"; [ -d "$P" ] || P="$(ls -d "$HOME"/.claude/plugins/cache/*/tkm-harness/*/ 2>/dev/null | sort -V | tail -1)"; P="${P%/}"
. "$P/scripts/tasks-path.sh"
f="$(harness_settings_set auto_sync on "$PWD")" && echo "変えたファイル: $f"   # 止めるときは off
harness_auto_sync "$PWD" | cat   # HC_AUTO_SYNC を打ったシェルでは、その値が先に出る
```

報告書式: `更新後の入れ替えを有効にしました → <パス>。プラグインが新しくなった回に、画面下部などのスクリプトを自動で最新にします（元の内容は .bak に残します）` ／ 無効にしたときは `更新後の入れ替えを無効にしました → <パス>。これまでどおり /tkm-harness:update で手動更新してください`。書き込み先は常にプロジェクトの `.claude/settings.json`（`env.TKM_HARNESS_AUTO_SYNC`）。保存すると同じ会話の次の Bash・hook から効く。

### 8. 形と Orca（tasks / worktree / notify）と GitHub Project の番号・リポ（project / repo）
5 つとも**プロジェクトの `.claude/settings.json` の `env`** の 1 つの名前で決まる: `TKM_HARNESS_TASKS`・`TKM_HARNESS_WORKTREE`・`TKM_HARNESS_NOTIFY`・`TKM_HARNESS_PROJECT`（GitHub Project の番号。正の整数。無ければ `hirai-task` がリポに紐づいた Project を探す）・`TKM_HARNESS_REPO`（`<owner>/<name>`。無ければ `git remote get-url origin`）。project・repo は `harness_settings_set project <番号>`・`harness_settings_set repo <owner/name>` で書く（正の整数・`<owner>/<name>` でなければ rc 2 で書かない）（プラグインがプロジェクトの settings から読めるのは `env` だけ。https://code.claude.com/docs/en/settings-reference.md#env）。`harness_settings_set <項目> <値>` が**その 1 つのキーだけ**を書く（python3 で JSON を読み、ほかのキーは触らず、indent 2・ensure_ascii False で書き戻す。JSON として読めない file は上書きせず rc 1）。書き込み先は**常にプロジェクト（git の toplevel）の `.claude/settings.json`**。ホームの `~/.claude/settings.json` には書かない（他のリポにも効いてしまうため）。書いたら、同じ項目の行がプロジェクトの `.claude/mode.yml` にあれば同じ関数が直す（`worktree` は行を消し、`tasks`・`notify` は値をそろえて行を残す。`hirai-task` の `is_coordinator` が今も mode.yml だけを読むため。`local` のときは触らない。4.x の間だけ mode.yml も読むが、settings が先）。**自分だけ変えたいときは `.claude/settings.local.json`（git に入らない）に書ける**: `harness_settings_set <項目> <値> "$PWD" local`。読む順は 環境変数 `HC_*`（一時の上書き。project・repo は `HIRAI_TASK_PROJECT`・`HIRAI_TASK_REPO`）→ `TKM_HARNESS_*`（Claude Code の中では settings.local.json > settings.json が重なって届く）→ Claude Code の外では settings の file を直に読む → mode.yml → 既定。値は `tasks`: `ledger`（既定）／ `github-project`、`worktree`: `off`（既定）／ `warn` ／ `block`、`notify`: `off`（既定）／ `orca`。
`tasks: github-project` にするときは、追加で入れるものはない（タスク管理の機能は tkm-harness の中にある）。`/tkm-harness:start-task` などが `hirai-task` を呼ぶ形に変わる。
`worktree: block` は、Orca の worktree でない会話からの、Edit・Write・NotebookEdit と `git commit` を止める（MCP の書き込みの道具と Bash でのファイルの書き換えは止めない。読み取り・リポの外・git に入らない場所への書き込み・`git switch` も止めない）。**止める設定なので、有効にする前に承認カードで確認を取る**（2 と同じ型。「しないと」は並行の会話が同じ作業ツリーを触る事故が残ること）。`warn` と `off`、`notify` の切り替えに確認は要らない。
**保存すると、同じ会話の次の Bash・hook から新しい値が効く**（Claude Code は会話の途中で settings の file を保存すると、動いている会話の環境変数に入れる。設計メモ F4）。**消したときだけ**、開き直すまで古い値が会話に残る（変数を消しても動いている会話からは消えないため。値を戻したいときは消さず、既定の値を書く）。
```bash
P="${CLAUDE_PLUGIN_ROOT}"; [ -d "$P" ] || P="$(command -v python3 >/dev/null 2>&1 && python3 -I -c 'import json,re,sys; d=json.load(open(sys.argv[1])); r=[x for k,v in d.get("plugins",{}).items() if k.split("@",1)[0]==sys.argv[2] for x in v if x.get("installPath")]; r.sort(key=lambda x:[int(n) if n.isdigit() else 0 for n in re.split(r"[.]", str(x.get("version","0")).split("-",1)[0])]); print(r[-1]["installPath"] if r else "")' "$HOME/.claude/plugins/installed_plugins.json" tkm-harness 2>/dev/null)"; [ -d "$P" ] || P="$(ls -d "$HOME"/.claude/plugins/cache/*/tkm-harness/*/ 2>/dev/null | sort -V | tail -1)"; P="${P%/}"
. "$P/scripts/tasks-path.sh"
f="$(harness_settings_set worktree warn "$PWD")" && echo "変えたファイル: $f"   # tasks・notify も同じ書き方。自分だけなら末尾に local を足す
harness_worktree "$PWD" | cat   # HC_WORKTREE を打ったシェルでは、その値が先に出る
```
報告書式: `worktree を warn にしました → <パス>（env の TKM_HARNESS_WORKTREE）。Orca の worktree でない会話に、開始時に警告を出します（開き直した会話から）`。自分だけの変更なら 1 行足す: `自分だけに効かせたいときは .claude/settings.local.json に書けます`。

## 判定できる終了条件

- 引数なしのとき、8 項目すべてに実測値が入っている（8 の project・repo は値か「自動で探す」「git remote」）。
- 7 の 2 つの値が、`extraKnownMarketplaces.tkm-harness.autoUpdate`（無ければ無効）と `harness_auto_sync "$PWD"` の実測値と一致している。
- 1・2・5 の表示が `<正式名>（<解説>）` の形になっている（`normal` / `loop` / `ultracode` / `statusLine` の文字が出ている）。
- 変更したときは、変更したファイルのパスが報告に入っており、`mode` なら `harness_mode "$PWD"` が指定した値と一致する。
