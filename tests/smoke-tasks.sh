#!/usr/bin/env bash
# tkm-harness のタスク管理の機能 (hirai-task・ghp-path.sh・coordinator-load.sh・進みの表の入れ方) の自己検証 smoke (13 case)。1 件でも FAIL なら exit 1。
# プラグイン全体の確かめは tests/smoke.sh。
#
#   ROOT = このスクリプトの 1 つ上 (プラグインのルート。1 つのプラグインなので土台も同じ)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$here/.." && pwd)"
FAILED=0
# gh を呼ばせない。case 4 だけが偽の gh を PATH に置く。
export HARNESS_UPDATE_CHECK=off
# 設定の読み（TKS-R1）に効く環境変数を外す。Claude Code の中で回しても外と同じ結果にする（会話の env には TKM_HARNESS_TASKS などが入っている）。
unset HC_MODE HC_AUTO_SYNC TKM_HARNESS_MODE TKM_HARNESS_AUTO_SYNC TKM_HARNESS_PROJECT TKM_HARNESS_REPO \
  TKM_HARNESS_LOAD_DEADLINE TKM_HARNESS_LOAD_DEADLINE_LABEL TKM_HARNESS_LOAD_MAINLINE TKM_HARNESS_LOAD_MAINLINE_LABEL TKM_HARNESS_NIGHTLY_CI \
  HIRAI_TASK_PROJECT HIRAI_TASK_REPO

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

# case 7: コーディネーターの hook（止めない・100 行以内・知らせを受けたときの 1 行。表の出し方は case 13）
case_7() {
  local h="$ROOT/hooks/coordinator-load.sh" cfg="$ROOT/hooks/hooks.json" s out rc lines bad=""
  bash -n "$h" || { fail 7 "coordinator-load.sh の構文" "bash -n が落ちた"; return; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); e=d["hooks"]; assert len(e["PostToolUse"])==1 and e["PostToolUse"][0]["matcher"]=="Bash" and "coordinator-load.sh" in e["PostToolUse"][0]["hooks"][0]["command"]' "$cfg" 2>/dev/null \
    || { fail 7 "hooks.json の PostToolUse は Bash の coordinator-load.sh の 1 本" "形が違う"; return; }
  lines="$(wc -l < "$h" | tr -d ' ')"
  [ "$lines" -le 100 ] || { fail 7 "hook は 100 行以内" "$lines 行"; return; }
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
  # 判定は is-coordinator だけが持つ（hook は HC_NOTIFY・端末の印を自分で見ない）: 0 なら HC_NOTIFY=orca・端末の印なしでも出る / 3（判定できない）は出さない
  run7 orca term_1 0 Bash "orca orchestration check" "$msg"; [ -n "$out" ] && [ "$rc" = 0 ] || bad="$bad 判定を is-coordinator に任せていない（HC_NOTIFY=orca で出ない）;"
  run7 off "" 0 Bash "orca orchestration check" "$msg"; [ -n "$out" ] && [ "$rc" = 0 ] || bad="$bad 判定を is-coordinator に任せていない（端末の印なしで出ない）;"
  run7 off term_1 3 Bash "orca orchestration check" "$msg"; [ -z "$out" ] && [ "$rc" = 0 ] || bad="$bad 判定できない（exit 3）のに出た;"
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

# ---------- 進みの表をコーディネーターの会話へ入れる (TKM-R9。lane E) ----------
# 偽の gh・偽の orca・偽の hirai-task だけで動かす。本物の gh・orca は呼ばない（PATH に本物の orca が無い env -i で回す）。
PY_DIR="$(dirname "$(command -v python3)")"
BASE_PATH="/usr/bin:/bin:$PY_DIR"

# 偽の orca: FAKE_MODE が worker-list の答えを決め、全部の呼び出しを $FAKE_LOG に 1 行ずつ書く
#   listed=呼んだ端末（環境変数 ORCA_TERMINAL_HANDLE）が 1 頁目に載る / absent=載らない / page2=1 頁目に無く hasMore・2 頁目（--cursor c2）に載る / fail=exit 1 / sleep=8 秒眠る / badjson=壊れた出力
mk_fake_orca() {
  cat > "$1" <<'FAKEORCA'
#!/usr/bin/env bash
printf '%s [%s]\n' "$*" "$#" >> "$FAKE_LOG"
[ "${1:-} ${2:-}" = "orchestration worker-list" ] || exit 0
H="${ORCA_TERMINAL_HANDLE:-none}"
case "${FAKE_MODE:-absent}" in
  fail) echo "runtime unavailable" >&2; exit 1 ;;
  sleep) sleep 8; exit 0 ;;
  badjson) echo "not json"; exit 0 ;;
  listed) echo '{"ok":true,"result":{"workers":[{"agentTerminalHandle":"term_X"},{"agentTerminalHandle":"'"$H"'"}],"page":{"hasMore":false,"nextCursor":null}}}' ;;
  page2)
    case " $* " in
      *" --cursor c2 "*) echo '{"ok":true,"result":{"workers":[{"agentTerminalHandle":"'"$H"'"}],"page":{"hasMore":false,"nextCursor":null}}}' ;;
      *) echo '{"ok":true,"result":{"workers":[{"agentTerminalHandle":"term_X"}],"page":{"hasMore":true,"nextCursor":"c2"}}}' ;;
    esac ;;
  *) echo '{"ok":true,"result":{"workers":[{"agentTerminalHandle":"term_X"}],"page":{"hasMore":false,"nextCursor":null}}}' ;;
esac
FAKEORCA
  chmod +x "$1"
}

# mk_repo <dir> <settings.json の env の tasks（空なら env なし）> [mode.yml の中身] -> git のリポ
mk_repo() {
  mkdir -p "$1/.claude"; git -C "$1" init -q
  if [ -n "$2" ]; then printf '{"env":{"TKM_HARNESS_TASKS":"%s"}}\n' "$2" > "$1/.claude/settings.json"; else echo '{}' > "$1/.claude/settings.json"; fi
  [ -z "${3:-}" ] || printf '%s\n' "$3" > "$1/.claude/mode.yml"
}

# case 8: SessionStart が、親のいない会話にだけ進みの表（控え）を additionalContext で入れる (TKM-R9.1・R9.2)
check8() { # check8 <session-start.sh> -> 食い違いの文（無ければ空）
  local hook="$1" s bad="" out rc src plain t8 e8
  s="$(mk)"; mkdir -p "$s/plug/bin" "$s/plug/hooks" "$s/fake" "$s/home"
  cp -R "$ROOT/scripts" "$s/plug/scripts"; cp "$ROOT/VERSION" "$s/plug/"; cp "$hook" "$s/plug/hooks/session-start.sh"
  cat > "$s/plug/bin/hirai-task" <<'FAKETASK'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
case "$1" in
  is-coordinator) exit "${FAKE_ROLE_RC:-0}" ;;
  load) [ -z "${FAKE_SLEEP:-}" ] || sleep "$FAKE_SLEEP"
        [ "${FAKE_LOAD_RC:-0}" != 0 ] || { echo "TABLE-ROW"; echo "（控え: 3 分前）"; }
        exit "${FAKE_LOAD_RC:-0}" ;;
  *) exit 0 ;;
esac
FAKETASK
  printf '#!/usr/bin/env bash\necho GH >> "$FAKE_LOG"; exit 1\n' > "$s/fake/gh"
  chmod +x "$s/plug/bin/hirai-task" "$s/fake/gh"
  mk_repo "$s/gp" github-project; mk_repo "$s/ledger" ""
  run8() { # run8 <repo> <source> [VAR=値 ...] -> out, rc, log
    local repo="$1" source="$2"; shift 2
    : > "$s/log"
    out="$(printf '{"hook_event_name":"SessionStart","source":"%s"}' "$source" | ( cd "$repo" && env -i PATH="$s/fake:$BASE_PATH" HOME="$s/home" HARNESS_UPDATE_CHECK=off CLAUDE_PLUGIN_ROOT="$s/plug" CLAUDE_PROJECT_DIR="$repo" FAKE_LOG="$s/log" "$@" bash "$s/plug/hooks/session-start.sh" 2>"$s/err" ))"; rc=$?
  }
  ctx() { printf '%s' "$out" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); h=d["hookSpecificOutput"]; assert list(d)==["hookSpecificOutput"] and h["hookEventName"]=="SessionStart" and set(h)=={"hookEventName","additionalContext"}, d; print(h["additionalContext"])'; }
  # 担当の会話（親がいる = exit 1）の出力を基準にする（今の行は変えない）
  run8 "$s/gp" startup FAKE_ROLE_RC=1; plain="$out"
  { [ "$rc" = 0 ] && printf '%s' "$plain" | grep -q '^\[harness\] 進め方' && ! printf '%s' "$plain" | grep -q 'hookSpecificOutput\|TABLE-ROW'; } || bad="$bad 担当（親がいる）の会話の出力が平文の今の行でない(rc=$rc);"
  for src in startup resume clear compact; do
    run8 "$s/gp" "$src"
    { [ "$rc" = 0 ] && ctx > "$s/ctx" 2>/dev/null; } || { bad="$bad [$src] additionalContext の JSON でない(rc=$rc out=$out);"; continue; }
    { grep -q 'TABLE-ROW' "$s/ctx" && grep -q '（控え: 3 分前）' "$s/ctx"; } || bad="$bad [$src] 表と控えの古さが入っていない;"
    [ "$(head -n "$(printf '%s\n' "$plain" | wc -l | tr -d ' ')" "$s/ctx")" = "$plain" ] || bad="$bad [$src] 開始時の今の行が変わった;"
    grep -qx 'load --cached' "$s/log" || bad="$bad [$src] load --cached を呼んでいない($(tr '\n' '|' < "$s/log"));"
    { ! grep -q 'GH\|load --refresh\|^load$' "$s/log"; } || bad="$bad [$src] GitHub を叩く呼び方をした;"
  done
  run8 "$s/gp" startup FAKE_LOAD_RC=3
  { ctx > "$s/ctx" 2>/dev/null && grep -q '進みの表の控えがありません（`hirai-task load` で作る）' "$s/ctx" && ! grep -q 'TABLE-ROW' "$s/ctx"; } || bad="$bad 控えが無いときの 1 行が出ない(out=$out);"
  run8 "$s/gp" startup FAKE_ROLE_RC=3
  { ctx > "$s/ctx" 2>/dev/null && grep -q '判定できなかった' "$s/ctx" && ! grep -q 'TABLE-ROW' "$s/ctx" && ! grep -qx 'load --cached' "$s/log"; } || bad="$bad 判定できないとき 1 行で断らず表を入れた(out=$out);"
  t8="$(date +%s)"
  run8 "$s/gp" startup FAKE_SLEEP=6 HARNESS_LOAD_LIMIT_SEC=1
  e8=$(( $(date +%s) - t8 ))
  { ctx > "$s/ctx" 2>/dev/null && grep -q '1 秒で出せなかった' "$s/ctx" && ! grep -q 'TABLE-ROW' "$s/ctx"; } || bad="$bad 上限を超えたとき 1 行で断らない(out=$out);"
  # 子（sleep 6）ごと止める（process group）。子だけ止める形に壊すと 6 秒かかるので、4 秒以下を合格にする
  [ "$e8" -le 4 ] || bad="$bad 上限を超えたのに ${e8} 秒かかった（子ごと止めていない）;"
  run8 "$s/gp" startup TKM_HARNESS_LOAD_ON_START=off
  { [ "$out" = "$plain" ] && ! grep -q 'is-coordinator\|^load' "$s/log"; } || bad="$bad TKM_HARNESS_LOAD_ON_START=off（環境変数）でも入れた;"
  printf '{"env":{"TKM_HARNESS_TASKS":"github-project","TKM_HARNESS_LOAD_ON_START":"off"}}\n' > "$s/gp/.claude/settings.json"
  run8 "$s/gp" startup
  { ! printf '%s' "$out" | grep -q 'hookSpecificOutput\|TABLE-ROW' && ! grep -q '^load' "$s/log"; } || bad="$bad settings.json の env の LOAD_ON_START=off でも入れた;"
  printf '{"env":{"TKM_HARNESS_TASKS":"github-project"}}\n' > "$s/gp/.claude/settings.json"
  run8 "$s/ledger" startup
  { ! printf '%s' "$out" | grep -q 'hookSpecificOutput\|TABLE-ROW' && [ ! -s "$s/log" ]; } || bad="$bad GitHub Project で回さないリポ（台帳）で入れた/hirai-task を呼んだ;"
  rm -f "$s/plug/bin/hirai-task"
  run8 "$s/gp" startup
  { ! printf '%s' "$out" | grep -q 'hookSpecificOutput\|TABLE-ROW' && [ "$rc" = 0 ]; } || bad="$bad hirai-task が無いのに表を入れた/落ちた;"
  printf '%s' "$bad"
}
case_8() {
  local bad hook="$ROOT/hooks/session-start.sh" m d
  bash -n "$hook" || { fail 8 "session-start.sh の構文" "bash -n が落ちた"; return; }
  bad="$(check8 "$hook")"
  [ -z "$bad" ] || { fail 8 "SessionStart の進みの表" "$bad"; return; }
  # 壊した写し 3 つで、それぞれ検査が FAIL する
  d="$(mk)"
  sed 's#\[ "$(harness_setting load_on_start "$lroot" 2>/dev/null || true)" != "off" \] || return 0#true#' "$hook" > "$d/no-off.sh"
  sed 's#is-coordinator >/dev/null || rc=\$?#is-coordinator >/dev/null || rc=0#' "$hook" > "$d/no-role.sh"
  sed 's#"\$task" load --cached)#"$task" load)#' "$hook" > "$d/no-cached.sh"
  for m in no-off no-role no-cached; do
    cmp -s "$hook" "$d/$m.sh" && { fail 8 "壊した写し $m を作れた" "sed が当たらず元と同じ"; return; }
    [ -n "$(check8 "$d/$m.sh")" ] || { fail 8 "壊した写し $m で検査が FAIL する" "壊したのに通った"; return; }
  done
  pass 8 "SessionStart の startup・resume・clear・compact で、親のいない会話にだけ控えの表と古さを additionalContext で入れ、担当・判定不能・控え無し・上限超え・off・台帳のリポ・hirai-task 無しでは入れない/1 行だけ（壊した写し 3 つで FAIL）"
}

# case 9: hirai-task is-coordinator は「親がいるか」で決める (TKM-R9.5〜R9.7・6b(a)。偽の orca)
check9() { # check9 <プラグインの root> -> 食い違いの文
  local plug="$1" s bad="" rc t0 el
  s="$(mk)"; mkdir -p "$s/fake" "$s/home"; mk_fake_orca "$s/fake/orca"
  mk_repo "$s/gp" github-project; mk_repo "$s/led" ""; mk_repo "$s/both" ledger "tasks: github-project"; mk_repo "$s/ymlonly" "" "tasks: github-project"
  local task="$plug/bin/hirai-task"
  r9() { # r9 <repo> <FAKE_MODE> [VAR=値 ...] -> rc。引数は ARGS（既定 is-coordinator）。log は $s/log
    local repo="$1" mode="$2"; shift 2
    ( cd "$repo" && env -i PATH="$s/fake:$BASE_PATH" HOME="$s/home" FAKE_LOG="$s/log" FAKE_MODE="$mode" "$@" "$task" is-coordinator ${ARGS9:-} >"$s/out" 2>"$s/err" </dev/null )
  }
  : > "$s/log"; r9 "$s/gp" listed ORCA_TERMINAL_HANDLE=term_W; rc=$?
  [ "$rc" = 1 ] || bad="$bad worker-list に載る端末が担当扱い（exit 1）でない(rc=$rc);"
  { grep -q 'worker-list.*--limit 100' "$s/log" && ! grep -q 'terminal-state' "$s/log"; } || bad="$bad worker-list を --limit 100 で・--terminal-state なしで引いていない($(cat "$s/log"));"
  : > "$s/log"; r9 "$s/gp" absent ORCA_TERMINAL_HANDLE=term_A; rc=$?
  [ "$rc" = 0 ] || bad="$bad 載っていない端末が親なし（exit 0）でない(rc=$rc);"
  : > "$s/log"; r9 "$s/gp" page2 ORCA_TERMINAL_HANDLE=term_P2; rc=$?
  { [ "$rc" = 1 ] && grep -q -- '--cursor c2' "$s/log"; } || bad="$bad 2 頁目に載る端末を頁送りで見つけない(rc=$rc log=$(tr '\n' '|' < "$s/log"));"
  : > "$s/log"; r9 "$s/gp" fail ORCA_TERMINAL_HANDLE=term_F; rc=$?
  { [ "$rc" = 3 ] && [ ! -s "$s/out" ]; } || bad="$bad worker-list が exit 1 のとき exit 3（判定できない）でない(rc=$rc);"
  : > "$s/log"; r9 "$s/gp" badjson ORCA_TERMINAL_HANDLE=term_J; rc=$?
  [ "$rc" = 3 ] || bad="$bad 壊れた JSON のとき exit 3 でない(rc=$rc);"
  t0=$SECONDS; r9 "$s/gp" sleep ORCA_TERMINAL_HANDLE=term_S; rc=$?; el=$((SECONDS - t0))
  { [ "$rc" = 3 ] && [ "$el" -le 5 ]; } || bad="$bad 眠る orca を 2 秒の上限で切って exit 3 にしない(rc=$rc ${el} 秒);"
  : > "$s/log"; r9 "$s/gp" absent ORCA_TERMINAL_HANDLE=term_H HC_NOTIFY=off; rc=$?
  { [ "$rc" = 0 ] && [ ! -s "$s/log" ]; } || bad="$bad HC_NOTIFY=off が worker-list を引かず親なしにならない(rc=$rc);"
  : > "$s/log"; r9 "$s/gp" listed ORCA_TERMINAL_HANDLE=term_R1 TKM_HARNESS_ROLE=coordinator; rc=$?
  { [ "$rc" = 0 ] && [ ! -s "$s/log" ]; } || bad="$bad TKM_HARNESS_ROLE=coordinator が worker-list に勝たない(rc=$rc);"
  : > "$s/log"; r9 "$s/gp" absent ORCA_TERMINAL_HANDLE=term_R2 HC_NOTIFY=off TKM_HARNESS_ROLE=worker; rc=$?
  { [ "$rc" = 1 ] && [ ! -s "$s/log" ]; } || bad="$bad TKM_HARNESS_ROLE=worker が HC_NOTIFY=off に勝たない(rc=$rc);"
  : > "$s/log"; r9 "$s/gp" listed; rc=$?
  { [ "$rc" = 0 ] && [ ! -s "$s/log" ]; } || bad="$bad 端末の印が無い会話が親なしにならない(rc=$rc);"
  ( cd "$s/gp" && env -i PATH="$BASE_PATH" HOME="$s/home" ORCA_TERMINAL_HANDLE=term_N "$task" is-coordinator >/dev/null 2>&1 </dev/null ); rc=$?
  [ "$rc" = 0 ] || bad="$bad orca が無い会話が親なしにならない(rc=$rc);"
  r9 "$s/led" absent ORCA_TERMINAL_HANDLE=term_T; rc=$?
  [ "$rc" = 1 ] || bad="$bad tasks が github-project でないリポで表の側が偽（exit 1）にならない(rc=$rc);"
  # 判定の控え: 端末ごとに 10 分。判定できなかったときは控えない
  : > "$s/log"; r9 "$s/gp" absent ORCA_TERMINAL_HANDLE=term_C; r9 "$s/gp" absent ORCA_TERMINAL_HANDLE=term_C
  [ "$(grep -c worker-list "$s/log")" = 1 ] || bad="$bad 同じ端末の 2 回目が控えを使わない(worker-list $(grep -c worker-list "$s/log") 回);"
  : > "$s/log"; r9 "$s/gp" fail ORCA_TERMINAL_HANDLE=term_U; r9 "$s/gp" fail ORCA_TERMINAL_HANDLE=term_U
  [ "$(grep -c worker-list "$s/log")" = 2 ] || bad="$bad 判定できなかった結果を控えた;"
  # 6b(a): settings.json の env は mode.yml に勝つ・mode.yml だけの tasks: も読む・--role は tasks の形を見ない
  r9 "$s/both" absent ORCA_TERMINAL_HANDLE=term_B; rc=$?
  [ "$rc" = 1 ] || bad="$bad settings.json の tasks が mode.yml の tasks に勝たない(rc=$rc);"
  r9 "$s/ymlonly" absent ORCA_TERMINAL_HANDLE=term_Y; rc=$?
  [ "$rc" = 0 ] || bad="$bad mode.yml だけの tasks: github-project を読まない(rc=$rc);"
  ARGS9=--role r9 "$s/led" absent ORCA_TERMINAL_HANDLE=term_T; rc=$?
  { [ "$rc" = 0 ] && [ "$(cat "$s/out")" = coordinator ]; } || bad="$bad --role が tasks の形と無関係に coordinator を 1 語で出さない(rc=$rc out=$(cat "$s/out"));"
  # 親がいない会話 (worker-list に載らない) の done は送らず、黙らず stderr に 1 行出す（Run の外で立てた担当の知らせが消える原因を見せる）
  printf '# r\n' > "$s/f.md"; : > "$s/log"
  ( cd "$s/gp" && env -i PATH="$s/fake:$BASE_PATH" HOME="$s/home" FAKE_LOG="$s/log" FAKE_MODE=absent HC_NOTIFY=orca ORCA_TERMINAL_HANDLE=term_D \
      "$plug/bin/hirai-notify" done "$s/f.md" 完了 --to run:abc >"$s/out" 2>"$s/err" </dev/null ); rc=$?
  { [ "$rc" = 0 ] && grep -q 'TKM_HARNESS_ROLE=worker' "$s/err" && ! grep -q 'send' "$s/log"; } || bad="$bad 親がいない会話の done が黙って消える（stderr に理由が無い）か送った(rc=$rc err=$(cat "$s/err") log=$(cat "$s/log"));"
  printf '%s' "$bad"
}
case_9() {
  local bad d m
  bad="$(check9 "$ROOT")"
  [ -z "$bad" ] || { fail 9 "is-coordinator は親がいるかで決まる" "$bad"; return; }
  d="$(mk)"; mkdir -p "$d/a" "$d/b" "$d/c"
  for m in a b c; do cp -R "$ROOT/bin" "$ROOT/scripts" "$d/$m/"; done
  sed "s|cursor = page.get('nextCursor') or ''|cursor = ''|" "$ROOT/bin/hirai-task" > "$d/a/bin/hirai-task"
  sed "s|^ROLE_LIMIT_SECONDS = 2 |ROLE_LIMIT_SECONDS = 60 |" "$ROOT/bin/hirai-task" > "$d/b/bin/hirai-task"
  python3 -I - "$ROOT/bin/hirai-task" "$d/c/bin/hirai-task" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
s = s.replace("    for path in _settings_files():\n", "    for path in []:\n", 1)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
  chmod +x "$d"/*/bin/hirai-task
  for m in a b c; do
    cmp -s "$ROOT/bin/hirai-task" "$d/$m/bin/hirai-task" && { fail 9 "壊した写し $m を作れた" "当たらず元と同じ"; return; }
    [ -n "$(check9 "$d/$m")" ] || { fail 9 "壊した写し $m で検査が FAIL する" "壊したのに通った"; return; }
  done
  pass 9 "is-coordinator: 上書き > HC_NOTIFY=off > 端末・orca なし > worker-list（2 頁目・載る/載らない・exit 1・壊れた JSON・眠る・控え）・settings.json の env が mode.yml に勝つ（壊した写し 3 つで FAIL）"
}

# case 10: hirai-notify の note・done 後の comment・親がいない会話では送らない (TKM-R9.4 の口・R9.5)
check10() { # check10 <プラグインの root> -> 食い違いの文
  local plug="$1" s bad="" rc top n
  s="$(mk)"; mkdir -p "$s/fake" "$s/home"; mk_fake_orca "$s/fake/orca"
  mk_repo "$s/r" ""; printf '{"env":{"TKM_HARNESS_NOTIFY":"orca"}}\n' > "$s/r/.claude/settings.json"; echo rep > "$s/r/rep.md"
  mk_repo "$s/o" ""   # notify の設定なし
  top="$(cd "$s/r" && pwd -P)"
  local nt="$plug/bin/hirai-notify"
  n10() { # n10 <repo> <FAKE_MODE> [VAR=値 ...] -- <引数...>
    local repo="$1" mode="$2"; shift 2; local ev=()
    while [ $# -gt 0 ] && [ "$1" != -- ]; do ev+=("$1"); shift; done; shift
    : > "$s/log"
    ( cd "$repo" && env -i PATH="$s/fake:$BASE_PATH" HOME="$s/home" FAKE_LOG="$s/log" FAKE_MODE="$mode" ${ev[@]+"${ev[@]}"} "$BASH" "$nt" "$@" >"$s/out" 2>"$s/err" </dev/null )
  }
  n10 "$s/r" absent -- note "ビルドを直している"; rc=$?
  { [ "$rc" = 0 ] && grep -qxF "worktree set --worktree path:$top --comment ビルドを直している [6]" "$s/log"; } || bad="$bad note が作業ツリーの comment に書かれない(rc=$rc log=$(cat "$s/log"));"
  n10 "$s/r" absent -- note "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんあいうえおかきくけこさしすせそ"; rc=$?
  n=$(sed -n 's/^worktree set --worktree path:[^ ]* --comment \(.*\) \[6\]$/\1/p' "$s/log" | python3 -I -c 'import sys; print(len(sys.stdin.read().rstrip("\n")))')
  { [ "$rc" = 0 ] && [ "$n" = 60 ]; } || bad="$bad note が 60 字で切れない(rc=$rc 字数=$n);"
  n10 "$s/r" absent -- note; rc=$?
  { [ "$rc" = 0 ] && grep -qxF "worktree set --worktree path:$top --comment  [6]" "$s/log"; } || bad="$bad 文なしの note が comment を空にしない(rc=$rc log=$(cat "$s/log"));"
  n10 "$s/o" absent -- note "x"; rc=$?
  { [ "$rc" = 0 ] && [ ! -s "$s/log" ]; } || bad="$bad notify が off なのに note が orca を呼んだ(rc=$rc);"
  ( cd "$s/r" && env -i PATH="$BASE_PATH" HOME="$s/home" "$BASH" "$nt" note x >/dev/null 2>&1 </dev/null ); rc=$?
  [ "$rc" = 0 ] || bad="$bad orca が無いのに note が exit 0 でない(rc=$rc);"
  n10 "$s/r" absent HIRAI_COORDINATOR=run:C -- done rep.md 完了; rc=$?
  { [ "$rc" = 0 ] && grep -q '^orchestration send' "$s/log" && [ "$(tail -1 "$s/log")" = "worktree set --worktree path:$top --comment 完了報告済み [6]" ]; } || bad="$bad done を送れたあとに comment を「完了報告済み」にしない(rc=$rc log=$(tr '\n' '|' < "$s/log"));"
  # 親がいない会話は送らない・親がいる／判定できないときは送る
  n10 "$s/r" absent HIRAI_COORDINATOR=run:C ORCA_TERMINAL_HANDLE=term_A -- question rep.md 決めて; rc=$?
  { [ "$rc" = 0 ] && ! grep -q '^orchestration send' "$s/log"; } || bad="$bad 親がいない会話（worker-list に載らない）が送った(rc=$rc);"
  n10 "$s/r" listed HIRAI_COORDINATOR=run:C ORCA_TERMINAL_HANDLE=term_L -- question rep.md 決めて; rc=$?
  { [ "$rc" = 0 ] && grep -q '^orchestration send' "$s/log"; } || bad="$bad 親がいる担当が送れない(rc=$rc);"
  n10 "$s/r" fail HIRAI_COORDINATOR=run:C ORCA_TERMINAL_HANDLE=term_F -- question rep.md 決めて; rc=$?
  { [ "$rc" = 0 ] && grep -q '^orchestration send' "$s/log"; } || bad="$bad 判定できないときに送らない(rc=$rc);"
  n10 "$s/r" listed HIRAI_COORDINATOR=run:C ORCA_TERMINAL_HANDLE=term_R TKM_HARNESS_ROLE=coordinator -- question rep.md 決めて; rc=$?
  { [ "$rc" = 0 ] && ! grep -q '^orchestration send' "$s/log"; } || bad="$bad TKM_HARNESS_ROLE=coordinator なのに送った(rc=$rc);"
  n10 "$s/r" absent HIRAI_COORDINATOR=run:C -- question rep.md 決めて; rc=$?
  { [ "$rc" = 0 ] && grep -q '^orchestration send' "$s/log"; } || bad="$bad 端末の印も上書きも無い会話の今までの送り方が変わった(rc=$rc);"
  printf '%s' "$bad"
}
case_10() {
  local bad d m
  bad="$(check10 "$ROOT")"
  [ -z "$bad" ] || { fail 10 "hirai-notify の note・comment・親の判定" "$bad"; return; }
  d="$(mk)"; mkdir -p "$d/a" "$d/b" "$d/c"
  for m in a b c; do cp -R "$ROOT/bin" "$ROOT/scripts" "$d/$m/"; done
  sed 's|^  if \[ "\$role" = "coordinator" \]; then|  if false; then|' "$ROOT/bin/hirai-notify" > "$d/a/bin/hirai-notify"
  sed 's|^  worktree_comment "完了報告済み"|  true|' "$ROOT/bin/hirai-notify" > "$d/b/bin/hirai-notify"
  sed 's|^NOTE_MAX_CHARS=60|NOTE_MAX_CHARS=600|' "$ROOT/bin/hirai-notify" > "$d/c/bin/hirai-notify"
  chmod +x "$d"/*/bin/hirai-notify
  for m in a b c; do
    cmp -s "$ROOT/bin/hirai-notify" "$d/$m/bin/hirai-notify" && { fail 10 "壊した写し $m を作れた" "当たらず元と同じ"; return; }
    [ -n "$(check10 "$d/$m")" ] || { fail 10 "壊した写し $m で検査が FAIL する" "壊したのに通った"; return; }
  done
  pass 10 "hirai-notify note（60 字・空で消す・off と orca なしは exit 0）・done 後の「完了報告済み」・親がいない会話は送らず、親がいる/判定不能は送る（壊した写し 3 つで FAIL）"
}

# case 11: 設定の読み先 (6b(b)): notify-attention.sh と開始時の 1 行目が、settings の env の TKM_HARNESS_NOTIFY を読む
check11() { # check11 <プラグインの root> -> 食い違いの文
  local plug="$1" s bad="" rc out
  s="$(mk)"; mkdir -p "$s/fake" "$s/home" "$s/data"; mk_fake_orca "$s/fake/orca"
  mk_repo "$s/on" ""; printf '{"env":{"TKM_HARNESS_NOTIFY":"orca"}}\n' > "$s/on/.claude/settings.json"
  mk_repo "$s/off" ""
  local j='{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission","cwd":"REPO","session_id":"s1"}'
  na11() { : > "$s/log"; printf '%s' "${j//REPO/$1}" | ( cd "$1" && env -i PATH="$s/fake:$BASE_PATH" HOME="$s/home" FAKE_LOG="$s/log" FAKE_MODE=absent HIRAI_COORDINATOR=run:C CLAUDE_PLUGIN_DATA="$s/data/$2" "$BASH" "$plug/hooks/notify-attention.sh" >"$s/out" 2>"$s/err" ); rc=$?; }
  na11 "$s/on" a
  { [ "$rc" = 0 ] && [ ! -s "$s/out" ] && grep -q '^orchestration send --type question' "$s/log"; } || bad="$bad settings の env の TKM_HARNESS_NOTIFY=orca で notify-attention が送らない(rc=$rc log=$(cat "$s/log"));"
  na11 "$s/off" b
  { [ "$rc" = 0 ] && [ ! -s "$s/log" ]; } || bad="$bad notify の設定が無いのに notify-attention が送った;"
  out="$( cd "$s/on" && env -i PATH="$s/fake:$BASE_PATH" HOME="$s/home" HARNESS_UPDATE_CHECK=off CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$s/on" bash "$plug/hooks/session-start.sh" </dev/null 2>/dev/null )"
  printf '%s' "$out" | head -1 | grep -q 'notify: orca' || bad="$bad 開始時の 1 行目の notify: が settings の値（orca）にならない($(printf '%s' "$out" | head -1));"
  out="$( cd "$s/off" && env -i PATH="$s/fake:$BASE_PATH" HOME="$s/home" HARNESS_UPDATE_CHECK=off CLAUDE_PLUGIN_ROOT="$plug" CLAUDE_PROJECT_DIR="$s/off" bash "$plug/hooks/session-start.sh" </dev/null 2>/dev/null )"
  printf '%s' "$out" | head -1 | grep -q 'notify: off' || bad="$bad 設定が無いとき開始時の 1 行目が notify: off にならない;"
  printf '%s' "$bad"
}
case_11() {
  local bad d
  bad="$(check11 "$ROOT")"
  [ -z "$bad" ] || { fail 11 "settings の env の notify の読み先" "$bad"; return; }
  # 壊した写し: notify-attention.sh が土台の設定を読まず、HC_NOTIFY だけ見る
  d="$(mk)"; mkdir -p "$d/a"; cp -R "$ROOT/hooks" "$ROOT/scripts" "$ROOT/bin" "$ROOT/VERSION" "$d/a/"
  sed 's|harness_notify "\$PWD"|echo off|' "$ROOT/hooks/notify-attention.sh" > "$d/a/hooks/notify-attention.sh"
  cmp -s "$ROOT/hooks/notify-attention.sh" "$d/a/hooks/notify-attention.sh" && { fail 11 "壊した写しを作れた" "sed が当たらず元と同じ"; return; }
  [ -n "$(check11 "$d/a")" ] || { fail 11 "壊した写しで検査が FAIL する" "壊したのに通った"; return; }
  pass 11 "settings の env の TKM_HARNESS_NOTIFY=orca で notify-attention が送り、開始時の 1 行目が notify: orca になる（設定が無ければ off。壊した写しで FAIL）"
}

# case 12: 設定の読みの分岐 (TKS-R1・R2.2・R2.3): Project の番号・リポの形の誤りは exit 2、設定の番号なら projectsV2 を打たない、
# リポは設定が git remote に勝つ。偽の gh は呼び出しを記録する（応答は常に失敗）。
check12() { # check12 <プラグインの root> -> 食い違いの文
  local plug="$1" s bad="" rc
  s="$(mk)"; mkdir -p "$s/fake" "$s/home"
  printf '#!/usr/bin/env bash\necho "$*" >> "$FAKE_LOG"; exit 1\n' > "$s/fake/gh"; chmod +x "$s/fake/gh"
  mk_repo "$s/r" ""; git -C "$s/r" remote add origin https://github.com/acme/widgets.git
  local task="$plug/bin/hirai-task"
  r12() { # r12 <settings.json の中身> [VAR=値 ...] -> rc。log は $s/log
    printf '%s\n' "$1" > "$s/r/.claude/settings.json"; shift; : > "$s/log"
    ( cd "$s/r" && env -i PATH="$s/fake:$BASE_PATH" HOME="$s/home" FAKE_LOG="$s/log" "$@" "$task" ready >"$s/out" 2>"$s/err" </dev/null )
  }
  r12 '{"env":{"TKM_HARNESS_PROJECT":"abc"}}'; rc=$?
  { [ "$rc" = 2 ] && grep -q 'TKM_HARNESS_PROJECT' "$s/err" && ! grep -q 'projectsV2' "$s/log"; } || bad="$bad TKM_HARNESS_PROJECT=abc が exit 2 で断られない(rc=$rc err=$(head -c 200 "$s/err"));"
  r12 '{"env":{"TKM_HARNESS_PROJECT":"7"}}'; rc=$?
  { ! grep -q 'projectsV2' "$s/log" && grep -q 'api' "$s/log"; } || bad="$bad TKM_HARNESS_PROJECT=7 でも Project を探しに行った/gh を呼ばない(log=$(head -c 200 "$s/log"));"
  r12 '{"env":{"TKM_HARNESS_REPO":"noslash"}}'; rc=$?
  { [ "$rc" = 2 ] && grep -q 'owner/name' "$s/err" && [ ! -s "$s/log" ]; } || bad="$bad TKM_HARNESS_REPO=noslash が exit 2 で断られない(rc=$rc);"
  r12 '{"env":{"TKM_HARNESS_PROJECT":"7","TKM_HARNESS_REPO":"o/r"}}'; rc=$?
  grep -q 'o/r\|-f owner=o\|owner=o' "$s/log" || bad="$bad 設定の repo=o/r が git remote に勝たない(log=$(head -c 300 "$s/log"));"
  r12 '{"env":{"TKM_HARNESS_PROJECT":"7"}}' HIRAI_TASK_PROJECT=oops; rc=$?
  { [ "$rc" = 2 ] && grep -q 'HIRAI_TASK_PROJECT' "$s/err"; } || bad="$bad 一時の上書き HIRAI_TASK_PROJECT が settings に勝たない(rc=$rc);"
  printf '%s' "$bad"
}
case_12() {
  local bad d m
  bad="$(check12 "$ROOT")"
  [ -z "$bad" ] || { fail 12 "設定の読みの分岐" "$bad"; return; }
  d="$(mk)"; mkdir -p "$d/a" "$d/b" "$d/c"
  for m in a b c; do cp -R "$ROOT/bin" "$ROOT/scripts" "$d/$m/"; done
  python3 -I - "$ROOT/bin/hirai-task" "$d" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
a = s.replace("        if not re.fullmatch(r'[1-9][0-9]*', PROJECT_NUMBER_OVERRIDE):", "        if False:", 1)
b = s.replace("    if _REPO_SETTING and not _REPO_SHAPE_RE.fullmatch(_REPO_SETTING):", "    if False:", 1)
c = s.replace("[_TEMP_OVERRIDES[key]] if key in _TEMP_OVERRIDES else []", "[]", 1)
for m, v in (("a", a), ("b", b), ("c", c)):
    open(sys.argv[2] + "/" + m + "/bin/hirai-task", "w", encoding="utf-8").write(v)
PY
  chmod +x "$d"/*/bin/hirai-task
  for m in a b c; do
    cmp -s "$ROOT/bin/hirai-task" "$d/$m/bin/hirai-task" && { fail 12 "壊した写し $m を作れた" "当たらず元と同じ"; return; }
    [ -n "$(check12 "$d/$m")" ] || { fail 12 "壊した写し $m で検査が FAIL する" "壊したのに通った"; return; }
  done
  pass 12 "設定の Project の番号が正の整数でなければ exit 2・番号があれば projectsV2 を打たない・repo の形の誤りは exit 2・一時の上書きが settings に勝つ（壊した写し 3 つで FAIL）"
}

# case 13: 振り出し・完了のあとに進みの表を出す hook (TKS-R5)。偽の hirai-task で is-coordinator と load --cached の答えを決める
# 要件 → 検査: R5.1 = 10 通りの振り出し・完了で 1 つの JSON に systemMessage と additionalContext の両方（load は --cached だけ・gh を叩かない）
#   R5.2 = 対象外のコマンド・担当（1）・判定できない（3）・load の失敗/空/時間切れで 1 バイトも出ず exit 0 / R5.3 = 知らせの 1 行は今までどおり・両方に当たれば表だけ
#   R5.4 = 10,000 字を超える表は末尾が 1 行に切られる・hooks.json は 1 本のまま / 壊した写し 3 つで FAIL
mk13() { # mk13 <dir> <hook の写し>: 偽の hirai-task と偽の gh を置いた土台を作る
  mkdir -p "$1/hooks" "$1/bin" "$1/repo" "$1/fake"; cp "$2" "$1/hooks/coordinator-load.sh"
  cat > "$1/bin/hirai-task" <<'FAKE'
#!/usr/bin/env bash
echo "$@" >> "$FAKE_LOG"
case "$1" in
  is-coordinator) exit "${FAKE_COORD:-0}" ;;
  load)
    case "${FAKE_LOAD:-ok}" in
      ok) printf '%s\n' '全体 40% (2/5)' '| 担当 | 進捗 |' '| a | 60% |' ;;
      fail) echo 'エラー' >&2; exit 1 ;;
      empty) : ;;
      sleep) exec sleep 9 ;;
      big) python3 -c 'print("あ" * 12000)' ;;
    esac ;;
esac
exit 0
FAKE
  printf '%s\n' '#!/usr/bin/env bash' 'echo GH >> "$FAKE_LOG"; exit 1' > "$1/fake/gh"
  chmod +x "$1/bin/hirai-task" "$1/fake/gh"
}
run13() { # run13 <土台> <is-coordinator の exit> <load の型> <command> [tool_response]  → out・rc・$1/log
  : > "$1/log"
  out="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"tool_response":{"stdout":sys.argv[3]},"cwd":sys.argv[2]}))' "$4" "$1/repo" "${5:-ok}" \
    | env -i PATH="$1/fake:$PATH" HOME="$1" FAKE_COORD="$2" FAKE_LOAD="$3" FAKE_LOG="$1/log" CLAUDE_PLUGIN_ROOT="$1" bash "$1/hooks/coordinator-load.sh" 2>"$1/err")"; rc=$?
}
check13() { # check13 <土台> → 壊れている所を文字で返す（空なら全部通った）
  local s="$1" bad="" c
  local starts=(
    "orca orchestration worker-start --agent claude --spec x"
    "orca worktree set --worktree id:1 --issue 12"
    "hirai-task assign 12 w1"
    "hirai-task start 12"
    "bash scripts/gh-task.sh assign 12 w1"
    "bash scripts/gh-task.sh start 12 | tail -3"
    "hirai-task done 12"
    "cd x && hirai-task after-merge 5"
    "bash scripts/gh-task.sh done 12; echo ok"
    "gh pr merge 5 --squash"
  )
  for c in "${starts[@]}"; do
    run13 "$s" 0 ok "$c"
    { [ "$rc" = 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert set(d)=={"systemMessage","hookSpecificOutput"}, list(d)
h=d["hookSpecificOutput"]; assert h["hookEventName"]=="PostToolUse" and set(h)=={"hookEventName","additionalContext"}, h
assert "| a | 60% |" in d["systemMessage"] and "| a | 60% |" in h["additionalContext"] and "人の画面にも出ています" in h["additionalContext"] and "人の画面にも出ています" not in d["systemMessage"]
' 2>/dev/null; } || bad="$bad [$c] で表が両方に出ない(rc=$rc);"
    grep -qx 'load --cached' "$s/log" && ! grep -q 'GH\|--refresh' "$s/log" || bad="$bad [$c] で load --cached だけを呼んでいない($(tr '\n' ' ' < "$s/log"));"
  done
  for c in "hirai-task ready" "hirai-task show 1" "git status" "echo hirai-task start 1" "hirai-task start --help" "hirai-task done -h" "gh pr view 5" "orca worktree set --worktree id:1 --display-name x" "orca worktree list"; do
    run13 "$s" 0 ok "$c"; { [ -z "$out" ] && [ "$rc" = 0 ] && [ ! -s "$s/log" ]; } || bad="$bad 対象外 [$c] で出たか呼んだ;"
  done
  run13 "$s" 1 ok "hirai-task start 1"; { [ -z "$out" ] && [ "$rc" = 0 ] && ! grep -q '^load' "$s/log"; } || bad="$bad 担当の会話（is-coordinator=1）で出たか load を呼んだ;"
  run13 "$s" 3 ok "hirai-task start 1"; { [ -z "$out" ] && [ "$rc" = 0 ]; } || bad="$bad 判定できない（3）で出た;"
  for c in fail empty; do run13 "$s" 0 "$c" "hirai-task start 1"; { [ -z "$out" ] && [ "$rc" = 0 ]; } || bad="$bad load が $c なのに出たか exit が 0 でない;"; done
  run13 "$s" 0 sleep "hirai-task start 1"; { [ -z "$out" ] && [ "$rc" = 0 ]; } || bad="$bad load が時間切れなのに出たか exit が 0 でない;"
  run13 "$s" 0 big "hirai-task start 1"
  printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for v in (d["systemMessage"], d["hookSpecificOutput"]["additionalContext"]):
    assert len(v)<=10000 and v.endswith("（続きは hirai-task load）") and v.count("\n")>=1, (len(v), v[-30:])
' 2>/dev/null || bad="$bad 10,000 字を超える表が切られない;"
  run13 "$s" 0 ok "orca orchestration check --wait" '{"messages":[{"id":"msg_ab12"}]}'
  printf '%s' "$out" | grep -q 'load --changed' && ! printf '%s' "$out" | grep -q systemMessage && ! grep -q '^load' "$s/log" || bad="$bad 知らせの 1 行が今までどおりでない($out);"
  run13 "$s" 0 ok "hirai-task start 1 && orca orchestration check --wait" '{"messages":[{"id":"msg_ab12"}]}'
  [ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = 0 ] && printf '%s' "$out" | grep -q '| a | 60% |' && ! printf '%s' "$out" | grep -q 'load --changed' || bad="$bad 両方に当たったとき表だけでない;"
  printf '%s' "$bad"
}
case_13() {
  local h="$ROOT/hooks/coordinator-load.sh" s d bad v
  bash -n "$h" || { fail 13 "coordinator-load.sh の構文" "bash -n が落ちた"; return; }
  s="$(mk)"; mk13 "$s" "$h"
  bad="$(check13 "$s")"
  [ -z "$bad" ] || { fail 13 "進みの表の hook" "$bad"; return; }
  # 壊した写し 3 つ: 振り出しの判定を外す・systemMessage を出さない・is-coordinator を見ない・表を切らない
  for v in 1 2 3 4; do
    d="$(mk)"; mk13 "$d" "$h"
    case "$v" in
      1) sed 's/|gh\\s+pr\\s+merge\\b//' "$h" > "$d/hooks/coordinator-load.sh" ;;
      2) sed 's/emit(cut(head + table), cut(table))/emit(cut(head + table))/' "$h" > "$d/hooks/coordinator-load.sh" ;;
      3) sed 's/^"\$task" is-coordinator .*$/true/' "$h" > "$d/hooks/coordinator-load.sh" ;;
      4) sed 's/return text if len(text) <= LIMIT else .*$/return text/' "$h" > "$d/hooks/coordinator-load.sh" ;;
    esac
    cmp -s "$h" "$d/hooks/coordinator-load.sh" && { fail 13 "壊した写し $v を作れた" "sed が当たらず元と同じ"; return; }
    [ -n "$(check13 "$d")" ] || { fail 13 "壊した写し $v で検査が FAIL する" "壊したのに通った"; return; }
  done
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["hooks"]; assert len(d["PostToolUse"])==1 and d["PostToolUse"][0]["hooks"][0]["timeout"]==10' "$ROOT/hooks/hooks.json" 2>/dev/null \
    || { fail 13 "hooks.json の PostToolUse は 1 本・timeout 10 秒（load の 8 秒より長い）" "形が違う"; return; }
  pass 13 "振り出し・完了の 10 通りで表が systemMessage と additionalContext の両方に出る（load --cached だけ）。対象外・担当・判定不能・load 失敗/空/時間切れでは出ず、10,000 字で切る。知らせの 1 行は従来どおり（壊した写し 4 つで FAIL）"
}

for n in ${SMOKE_CASES:-1 2 3 4 5 6 7 8 9 10 11 12 13}; do "case_$n"; done
[ "$FAILED" -eq 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
