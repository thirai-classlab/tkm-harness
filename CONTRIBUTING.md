# 開発の進め方

## 配布は main 1 本・プラグインは 1 つ

**`main` から、プラグイン `tkm-harness` を 1 つ配ります。** マーケットプレイス定義
（`.claude-plugin/marketplace.json`）は `main` に置き、1 行を持ちます。

| entry | source | 版 |
|---|---|---|
| `tkm-harness` | `"./"`（リポの root） | `VERSION`・`.claude-plugin/plugin.json` と同じ |

GitHub Project のタスク管理の機能（`hirai-task`・`/tkm-harness:board`・`/tkm-harness:project-setup`・skill `github-project`）は
同じプラグインの中にあります（旧 `hirai-project-method` は 2 つ目のプラグインでしたが、1 つにしました）。
`plugin.json` に `dependencies` と `repository` は書きません。配布の一覧の `owner.name` は `tkm-harness` で、
持ち主とリポの名前は動く部品（hooks・scripts・bin・commands・skills・templates・rules）に書きません。
fork がそのまま自分の owner で配れるようにするためです（`tests/smoke.sh` case 9 が見ます）。

利用者が `/plugin marketplace update tkm-harness` → 端末で `claude plugin update tkm-harness@tkm-harness --scope <入れた範囲>`（画面なら `/plugin` → Installed → Update now） を実行すると受け取るのは
**その時点の `main`** です。旧 `hirai-lite`（`hirai-method-lite` リポ）は触らず、新しい版を出しません（テックリード 2026-11-26 10:4x「tkm-ハーネスのみで良いです。」）。

タグは版ごとに `tkm-harness--v<版>` で付けます。

そのため次を守ります。

- **`main` には、リリースしてよい状態だけを置く。** 途中の状態・動作未確認の変更を push しない。
- 作業は作業用ブランチで行い、まとまってから `main` に入れる。
- `main` に入れる前に、必ず次を通す。
  - `bash tests/smoke.sh` と `bash tests/smoke-tasks.sh` が全項目 PASS で終了する
  - `claude plugin validate . --strict` が PASS する
  - 下の「版の上げ方」の版が一致している
- 版を上げたら、`main` のコミットに注釈付きタグ（`git tag -a tkm-harness--v<版>` など）を打つ。「どのコミットがどの版か」を
  あとから追うために残す。

## 版の上げ方

`VERSION` は更新の合図にも使われます（セッション開始時に、配布元の `VERSION` と手元の版を比べて
「更新あり」を出す仕組み）。**次の 4 か所を必ず同じ値に揃えます。**
`tests/smoke.sh` の case 9 が同じ検査をします。

- `VERSION`
- `.claude-plugin/plugin.json` の `version`
- `.claude-plugin/marketplace.json` の `plugins[0].version`
- `.claude-plugin/marketplace.json` の `metadata.version`

## 触らないもの

- `rules/` は利用者が `/tkm-harness:add-rule` で育てる資産の**素材**です。予算（常時読まれる分の合計は 6,000 tokens で警告 / 10,000 tokens が上限）
  に直結するため、増やすときは `tests/smoke.sh` の case 4・5 が通ることを必ず確かめます。
- 数の上限（常時読まれるルール 3 本 / 自動処理 6 本 / skill 3 個 / 自己検証 10 項目）は
  `tests/smoke.sh` の case 6 が守っています。自動処理を 5 本から 6 本にしたのは、2 つのプラグインを 1 つにして、
  コーディネーターの会話だけで働く PostToolUse の hook（`coordinator-load.sh`）が同じプラグインに入ったためです
  （heyapro-app #2042）。上限に達している枠に足すときは、先に何を減らすかを決めます。
