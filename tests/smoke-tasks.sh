#!/usr/bin/env bash
# tkm-harness のタスク管理の機能 (hirai-task・ghp-path.sh・coordinator-load.sh) の自己検証 smoke (7 case)。1 件でも FAIL なら exit 1。
# プラグイン全体の確かめは tests/smoke.sh。
#
#   ROOT = このスクリプトの 1 つ上 (プラグインのルート。1 つのプラグインなので土台も同じ)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$here/.." && pwd)"
FAILED=0
# gh を呼ばせない。case 4 だけが偽の gh を PATH に置く。
export HARNESS_UPDATE_CHECK=off

pass() { echo "PASS  case $1: $2"; }
fail() { echo "FAIL  case $1: $2 — ${3:-}"; FAILED=1; }
tmpdirs=()
mk() { local d; d="$(mktemp -d)"; tmpdirs+=("$d"); printf '%s' "$d"; }
trap 'for d in "${tmpdirs[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done' EXIT

# case 1: 部品が揃っている (移した部品・タスク管理の command 2 本・skill・hook・旧 tasks-path.sh の指しが残っていない)
case_1() {
  local missing="" f
  for f in bin/hirai-task scripts/ghp-path.sh scripts/hirai_board.py scripts/hirai_card.py scripts/hirai_project_setup.py \
           scripts/hirai_task_selftest.py scripts/hirai_load.py scripts/hirai_progress.py commands/board.md commands/project-setup.md skills/github-project/SKILL.md hooks/hooks.json hooks/coordinator-load.sh \
           docs/rules-reference/project-setup.md docs/rules-reference/glossary.md docs/rules-reference/approval-view.md .claude-plugin/plugin.json VERSION; do
    [ -f "$ROOT/$f" ] || missing="$missing $f"
  done
  [ -x "$ROOT/bin/hirai-task" ] || missing="$missing bin/hirai-task(実行権限)"
  [ ! -e "$ROOT/plugins" ] || missing="$missing plugins/(1 つのプラグインにしたので無いはず)"
  [ -z "$missing" ] || { fail 1 "部品が揃っている" "無い:$missing"; return; }
  local stale
  stale="$(grep -n "HARNESS_V2_ENTRY_NAME\|hirai-lite-v2" "$ROOT/bin/hirai-task" "$ROOT"/scripts/hirai_*.py "$ROOT/commands/board.md" "$ROOT/commands/project-setup.md" "$ROOT"/skills/github-project/SKILL.md "$ROOT/docs/rules-reference/project-setup.md" "$ROOT/docs/rules-reference/glossary.md" | head -3)"
  [ -z "$stale" ] || { fail 1 "2.x の entry 名の指しが残っていない" "$stale"; return; }
  pass 1 "部品が揃っている (hirai-task・hirai_*.py・ghp-path.sh・board・project-setup・skill github-project・hook・plugins/ なし)"
}

# case 2: 版 (VERSION = plugin.json = カタログの版)。plugin.json に dependencies・repository が無い
case_2() {
  local v pj name ver
  v="$(tr -d '[:space:]' < "$ROOT/VERSION")"
  pj="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['name'], d['version'], 'dependencies' in d, 'repository' in d)" "$ROOT/.claude-plugin/plugin.json" 2>&1)" \
    || { fail 2 "plugin.json が読める" "$pj"; return; }
  set -- $pj; name="$1"; ver="$2"
  [ "$name" = "tkm-harness" ] || { fail 2 "name が tkm-harness" "$name"; return; }
  [ "$ver" = "$v" ] || { fail 2 "VERSION と plugin.json の version が一致" "VERSION=$v plugin.json=$ver"; return; }
  { [ "$3" = False ] && [ "$4" = False ]; } || { fail 2 "plugin.json に dependencies・repository が無い" "$pj"; return; }
  local mv
  mv="$(python3 -c "import json,sys; print(next((p.get('version','') for p in json.load(open(sys.argv[1]))['plugins'] if p['name']=='tkm-harness'), 'ENTRY無し'))" "$ROOT/.claude-plugin/marketplace.json")"
  [ "$mv" = "$v" ] || { fail 2 "カタログの tkm-harness の版が VERSION と一致" "catalog=$mv VERSION=$v"; return; }
  pass 2 "版 ${v} が VERSION・plugin.json・カタログで一致し、依存・repository を宣言していない"
}

# case 3: hirai-task の自己検査 (gh を使わない。同じプラグインの approval-template.md と templates/draft.md を読む)
case_3() {
  local out rc
  out="$("$ROOT/bin/hirai-task" --selftest 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { fail 3 "hirai-task --selftest が exit 0" "rc=$rc $(printf '%s' "$out" | grep -m3 '^ *FAIL\|Error' )"; return; }
  printf '%s' "$out" | grep -q 'line は控えの 1 行を出し' || { fail 3 "line の自己検査が走っている" "出力に無い"; return; }
  # 別の場所へ写した bin・scripts だけでは、approval-template.md が無く検査を飛ばさず落ちる (土台探しの決め打ちが無い)
  local cp h got
  cp="$(mk)"; h="$(mk)"
  cp -R "$ROOT/bin" "$ROOT/scripts" "$cp/"
  got="$(HOME="$h" PYTHONDONTWRITEBYTECODE=1 python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import hirai_task_selftest as m; m._base_plugin_root()" "$cp/scripts" 2>&1 | tail -1)"
  case "$got" in *AssertionError*) ;; *) fail 3 "プラグインのルートに approval-template.md が無ければ検査を飛ばさず落ちる" "got=$got"; return ;; esac
  pass 3 "hirai-task --selftest が exit 0 ($(printf '%s' "$out" | grep -c 'PASS') 件)・ルートに approval-template.md が無ければ落ちる"
}

# case 4: 控えの id が entry 名-カタログ名。ghp-path.sh だけを source しても動き、土台の関数を要らない
case_4() {
  local id want catalog
  id="$(sed -n 's/^HARNESS_GHP_ID="\(.*\)"$/\1/p' "$ROOT/scripts/ghp-path.sh" | head -1)"
  catalog="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$ROOT/.claude-plugin/marketplace.json")"
  want="tkm-harness-${catalog}"
  [ "$id" = "$want" ] || { fail 4 "HARNESS_GHP_ID が <entry 名>-<カタログ名>" "want=$want ghp-path.sh=${id:-無}"; return; }
  local h r p
  h="$(mk)"; r="$(mk)"
  p="$(env -i HOME="$h" PATH="$PATH" bash -c ". \"$ROOT/scripts/ghp-path.sh\"; harness_ghp_cache_file \"$r\"; echo; type harness_tasks_file >/dev/null 2>&1 && echo LEAK")"
  printf '%s' "$p" | grep -q "^$h/.claude/plugins/data/$want/tasks-unknown.json" || { fail 4 "控えの path が data/$want/ の下" "$p"; return; }
  printf '%s' "$p" | grep -q LEAK && { fail 4 "ghp-path.sh だけで動く (土台の関数を持ち込まない)" "harness_tasks_file が定義された"; return; }
  pass 4 "控えの id=${want}・ghp-path.sh は単独で読める"
}

# case 5: hirai-task line の出し分け (実物の ghp-path.sh と偽の HOME・偽の gh)
#   控え無し=空 / 控えあり=1 行 / 引数なしは gh を呼ばない / --refresh は背景で gh を呼ぶ / form が ghp でない=空
case_5() {
  local h r bin calls out i
  h="$(mk)"; r="$(mk)"; bin="$(mk)"; calls="$h/gh-calls"
  git -C "$r" init -q && git -C "$r" remote add origin https://github.com/acme/widgets.git
  printf '#!/usr/bin/env bash\necho call >> "%s"\nexit 1\n' "$calls" > "$bin/gh"; chmod +x "$bin/gh"
  run_line() { HOME="$h" PATH="$bin:$PATH" HIRAI_TASK_ROOT="$r" HIRAI_TASK_REPO=acme/widgets "$ROOT/bin/hirai-task" line "$@"; }
  out="$(run_line)"; [ $? -eq 0 ] && [ -z "$out" ] || { fail 5 "控えが無いとき空で exit 0" "out=$out"; return; }
  [ ! -e "$calls" ] || { fail 5 "引数なしの line は gh を呼ばない" "呼んだ"; return; }
  # 控えを作る (form=ghp・件数 2/1/0/3)
  HOME="$h" bash -c ". \"$ROOT/scripts/ghp-path.sh\"; f=\"\$(harness_ghp_cache_file \"$r\")\"; harness_ghp_write_probe \"\$f\" ghp PVT_x 7; harness_ghp_write_counts \"\$f\" 2 1 0 3"
  out="$(run_line)"
  case "$out" in "3（承認 2・裁定 1・取り込み 0）／進行中 3／待ち解け —（"*"時点）") ;; *) fail 5 "控えがあれば 1 行を出す" "out=$out"; return ;; esac
  [ ! -e "$calls" ] || { fail 5 "引数なしの line は gh を呼ばない (控えあり)" "呼んだ"; return; }
  # 書いた直後は見分けも件数も間隔内で飛ばされるので、見分け (probed_epoch) を 0 に戻してから gh が呼ばれることを見る
  HOME="$h" bash -c ". \"$ROOT/scripts/ghp-path.sh\"; f=\"\$(harness_ghp_cache_file \"$r\")\"; sed -i.bak 's/\"probed_epoch\": .*/\"probed_epoch\": 0/' \"\$f\""
  run_line --refresh >/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do [ -e "$calls" ] && break; sleep 0.5; done
  [ -e "$calls" ] || { fail 5 "--refresh は背景で gh を呼ぶ" "5 秒待っても呼ばれない"; return; }
  # form が none なら出さない
  HOME="$h" bash -c ". \"$ROOT/scripts/ghp-path.sh\"; f=\"\$(harness_ghp_cache_file \"$r\")\"; harness_ghp_write_probe \"\$f\" none"
  out="$(run_line)"; [ -z "$out" ] || { fail 5 "form が ghp でなければ出さない" "out=$out"; return; }
  pass 5 "line: 控え無し=空・控えあり=1 行・引数なしは gh 不使用・--refresh は背景で gh・form none=空"
}

# case 6: 土台との境目 (土台の smoke が見る範囲の逆側) — 土台の source を要らず、ghp-path.sh が bash 3.2 の書き方 (連想配列なし)
case_6() {
  grep -n 'declare -A\|mapfile\|readarray\|\${[a-zA-Z_]*,,}' "$ROOT/scripts/ghp-path.sh" | head -1 | grep -q . \
    && { fail 6 "ghp-path.sh が bash 3.2 で動く書き方 (連想配列・mapfile・小文字化なし)" "$(grep -n 'declare -A\|mapfile\|readarray' "$ROOT/scripts/ghp-path.sh" | head -1)"; return; }
  bash -n "$ROOT/scripts/ghp-path.sh" || { fail 6 "ghp-path.sh の構文" "bash -n が落ちた"; return; }
  pass 6 "ghp-path.sh は bash 3.2 の書き方で構文が通る"
}

# case 7: コーディネーターの hook（止めない・60 行以内・GitHub も控えも読まない・知らせを受けたときだけ 1 行を足す）
case_7() {
  local h="$ROOT/hooks/coordinator-load.sh" cfg="$ROOT/hooks/hooks.json" s out rc lines bad=""
  bash -n "$h" || { fail 7 "coordinator-load.sh の構文" "bash -n が落ちた"; return; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); e=d["hooks"]; assert len(e["PostToolUse"])==1 and e["PostToolUse"][0]["matcher"]=="Bash" and "coordinator-load.sh" in e["PostToolUse"][0]["hooks"][0]["command"]' "$cfg" 2>/dev/null \
    || { fail 7 "hooks.json の PostToolUse は Bash の coordinator-load.sh の 1 本" "形が違う"; return; }
  lines="$(wc -l < "$h" | tr -d ' ')"
  [ "$lines" -le 60 ] || { fail 7 "hook は 60 行以内" "$lines 行"; return; }
  s="$(mk)"; mkdir -p "$s/hooks" "$s/bin" "$s/repo" "$s/fake"
  cp "$h" "$s/hooks/"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "$@" >> "$FAKE_LOG"' 'pwd -P >> "$FAKE_LOG"' 'exit "${FAKE_RC:-0}"' > "$s/bin/hirai-task"
  printf '%s\n' '#!/usr/bin/env bash' 'echo GH >> "$FAKE_LOG"; exit 1' > "$s/fake/gh"
  chmod +x "$s/bin/hirai-task" "$s/fake/gh"
  run7() { # run7 <HC_NOTIFY> <ORCA_TERMINAL_HANDLE> <hirai-task の exit> <tool_name> <command> <tool_response>
    : > "$s/log"
    out="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]},"tool_response":{"stdout":sys.argv[4]},"cwd":sys.argv[3]}))' "$4" "$5" "$s/repo" "$6" \
      | env -i PATH="$s/fake:$PATH" HOME="$s" HC_NOTIFY="$1" ORCA_TERMINAL_HANDLE="$2" FAKE_RC="$3" FAKE_LOG="$s/log" CLAUDE_PLUGIN_ROOT="$s" bash "$s/hooks/coordinator-load.sh" 2>"$s/err")"; rc=$?
  }
  local msg='{"messages":[{"id":"msg_ab12","type":"worker_done"}]}'
  run7 off term_1 0 Bash "orca orchestration check --wait" "$msg"
  { [ "$rc" = 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert list(d)==["hookSpecificOutput"], d           # decision・continue など止める口が無い
h=d["hookSpecificOutput"]; assert h["hookEventName"]=="PostToolUse" and "load --changed" in h["additionalContext"] and set(h)=={"hookEventName","additionalContext"}, h
'; } || bad="$bad 知らせを受けたのに 1 行が出ない・形が違う(rc=$rc out=$out);"
  [ "$(head -1 "$s/log")" = "is-coordinator" ] && [ "$(sed -n 2p "$s/log")" = "$(cd "$s/repo" && pwd -P)" ] || bad="$bad 会話の cwd で is-coordinator だけを呼んでいない($(cat "$s/log"));"
  grep -q GH "$s/log" && bad="$bad gh を叩いた;"
  run7 off term_1 0 Bash "orca orchestration check" '{"messages":[]}'; [ -z "$out" ] && [ "$rc" = 0 ] && [ ! -s "$s/log" ] || bad="$bad 知らせが無いのに出た;"
  run7 off term_1 1 Bash "orca orchestration check" "$msg"; [ -z "$out" ] && [ "$rc" = 0 ] || bad="$bad コーディネーターでないのに出た;"
  run7 orca term_1 0 Bash "orca orchestration check" "$msg"; [ -z "$out" ] && [ "$rc" = 0 ] && [ ! -s "$s/log" ] || bad="$bad HC_NOTIFY が off でないのに出た;"
  run7 off "" 0 Bash "orca orchestration check" "$msg"; [ -z "$out" ] && [ "$rc" = 0 ] || bad="$bad Orca の端末でないのに出た;"
  run7 off term_1 0 Bash "echo orca orchestration checkout msg_ab12" "$msg"; [ -z "$out" ] && [ "$rc" = 0 ] || bad="$bad 関係ないコマンドで出た;"
  run7 off term_1 0 Read "orca orchestration check" "$msg"; [ -z "$out" ] && [ "$rc" = 0 ] || bad="$bad Bash 以外で出た;"
  run7 off term_1 0 Bash "cd x && orca orchestration check --wait" "$msg"; [ -n "$out" ] || bad="$bad && のあとの check で出ない;"
  run7 off term_1 0 Bash "orca orchestration check --ack d1 | head -3" "ok"; [ -n "$out" ] && [ "$rc" = 0 ] || bad="$bad 受領（--ack）で出ない;"
  run7 off term_1 0 Bash "orca worktree list --ack" "ok"; [ -z "$out" ] || bad="$bad check でないコマンドの --ack で出た;"
  out="$(printf 'not json' | env -i PATH="$s/fake:$PATH" HOME="$s" HC_NOTIFY=off ORCA_TERMINAL_HANDLE=t CLAUDE_PLUGIN_ROOT="$s" bash "$s/hooks/coordinator-load.sh" 2>&1)"; rc=$?
  { [ "$rc" = 0 ] && [ -z "$out" ]; } || bad="$bad 壊れた入力で落ちたか出た;"
  run7 off term_1 0 Bash "orca orchestration check" "$msg"; [ ! -s "$s/err" ] || bad="$bad 標準エラーに出した($(cat "$s/err"));"
  [ -z "$bad" ] || { fail 7 "コーディネーターの hook" "$bad"; return; }
  pass 7 "知らせを受けたときだけ 1 行を足し、担当・他の会話・知らせ無し・失敗では何も出さず exit 0（止める口なし・gh も控えも読まない）"
}

for n in 1 2 3 4 5 6 7; do "case_$n"; done
[ "$FAILED" -eq 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
