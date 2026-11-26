#!/usr/bin/env bash
# SessionStart hook: 現在の mode と効いている設定 / 未完了タスク数 / 直近 state を 5 行以内で出力する。
# 更新の合図と「更新後の入れ替え」の報告は、該当する回だけ末尾に 1 行ずつ足す。
# 対象ファイルが 1 つも無くても正常終了する (fail-open)。
#
# パス解決は 2 段構え。
#   plugin_root : $CLAUDE_PLUGIN_ROOT > このスクリプトの 1 つ上 ($BASH_SOURCE 起点)
#   root        : $CLAUDE_PROJECT_DIR > $PWD を harness_root で解いたもの (git の toplevel までで最初に .claude/mode.yml・settings.json・rules が在る dir。
#                 無ければ toplevel。導入先リポジトリ = ユーザーの資産)。worktree・notify は harness_top (toplevel) の mode.yml から引く
set -uo pipefail

here="$(CDPATH= builtin cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && builtin pwd -P)" || here="."
plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$plugin_root" ] || [ ! -d "$plugin_root" ]; then
  plugin_root="$(CDPATH= builtin cd -- "$here/.." >/dev/null 2>&1 && builtin pwd -P)" || plugin_root="."
fi
root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$root" ] || [ ! -d "$root" ]; then
  root="$PWD"
fi

# --- 共通ライブラリ: 進め方 (mode) と台帳のパス解決をここに集約している ---
if [ -f "$plugin_root/scripts/tasks-path.sh" ]; then
  # shellcheck source=../scripts/tasks-path.sh
  . "$plugin_root/scripts/tasks-path.sh" 2>/dev/null || true
fi

# root は harness_root に解く (自分の .claude を持たないサブディレクトリで開いても、mode.yml・台帳・更新の鍵が toplevel と同じ値になり、
# 自分の .claude を持つパッケージで開いたときはそこを読む)。
# 解くのはここ 1 回だけ。以降の関数は解いた root を受け取り、git を打ち直さない。
opened="$root"   # 開いた dir (台帳・控えは「開いた dir → root」の順で引く)
if command -v harness_root >/dev/null 2>&1; then
  root="$(harness_root "$root")"
fi

# --- mode: 解決順は harness_mode (HC_MODE > env TKM_HARNESS_MODE > settings の file の env > mode.yml [予備] > normal) ---
# 画面下部 (scripts/statusline.sh) と /config も同じ関数を通す。ここで独自に解決しない。
# 表示は「正式名（短い解説）」(normal（確認あり）/ loop（自動で進む）)。未知の値はそのまま出す。
if command -v harness_mode >/dev/null 2>&1; then
  mode="$(harness_mode "$root")"
else
  mode="${HC_MODE:-normal}"
fi
[ -n "$mode" ] || mode="normal"
case "$mode" in
  normal) mode_line="normal（確認あり） — 重要な分かれ道で確認します (自動で進めるなら /tkm-harness:config)" ;;
  loop)   mode_line="loop（自動で進む） — 確認を求めず進みます (止めるときは「stop」)" ;;
  *)      mode_line="$mode" ;;
esac

# --- タスク管理の形: .claude/settings.json の env TKM_HARNESS_TASKS が決める (4.x の間は mode.yml の tasks: も読む。自動では見分けない) ---
# ledger (既定) は台帳の件数 (1.x と同じ。通信しない)。github-project のときだけ、
# hirai-task を、プラグインの絶対 path で呼ぶ (session-start は GitHub の関数を直接呼ばない)。
tasks_form="ledger"
if command -v harness_tasks_form >/dev/null 2>&1; then
  tasks_form="$(harness_tasks_form "$root" 2>/dev/null || echo ledger)"
fi
if [ "$tasks_form" = "github-project" ]; then
  # hook の PATH にプラグインの bin/ は入らない (Bash ツールだけに入る)。PATH に頼らず
  # harness_pm_task_bin (CLAUDE_PLUGIN_ROOT の bin → installed_plugins.json の user・managed かこのリポ [git-common-dir が同じ] の行の最大版 → PATH。cache へは python3 が無いときだけ) で絶対 path を引く。
  pm_task=""
  if command -v harness_pm_task_bin >/dev/null 2>&1; then
    pm_task="$(harness_pm_task_bin "$root" 2>/dev/null || true)"
  elif command -v hirai-task >/dev/null 2>&1; then
    pm_task="$(command -v hirai-task)"
  fi
  if [ -n "$pm_task" ]; then
    # 件数は控えを読むだけ (通信しない)。取り直しは別に切り離して起こす。
    # **取り直しを $(...) の中で呼ばない。** hirai-task line --refresh は背景の子が出力の
    # パイプを持ったまま走るので、$(...) が子の終了まで戻らず、hook の timeout を食う。
    # 出力を捨て、stdin も閉じて、この shell の直下で切り離す。
    ghp_line="$(HIRAI_TASK_ROOT="$root" "$pm_task" line 2>/dev/null || true)"
    HIRAI_TASK_ROOT="$root" "$pm_task" line --refresh >/dev/null 2>&1 </dev/null &
    if [ -n "$ghp_line" ]; then
      task_line="Project: あなたの番 ${ghp_line}"
    else
      task_line="Project: 件数を取得中です (hirai-task today で見られます)"
    fi
  else
    task_line="tasks: github-project ですが hirai-task が見つかりません（プラグインが壊れている。/plugin install tkm-harness@tkm-harness で入れ直す）"
  fi
else
  list=""
  if command -v harness_tasks_file >/dev/null 2>&1; then
    list="$(harness_tasks_file "$opened" 2>/dev/null || true)"
  fi
  if [ -n "$list" ] && [ -f "$list" ]; then
    task_line="やること: $(harness_open_tasks "$list") 件 ($(d="${list#"$root"/}"; printf '%s' "${d#"$opened"/}"))"
  else
    task_line="やること一覧はまだありません (/tkm-harness:new-task で作れます)"
  fi
fi

# --- 更新検知: 取得は背景 + 24h に 1 回、表示は前回キャッシュ値 (通信を待たない) ---
# 版を比べる VERSION はプラグイン側にあるので plugin_root を渡す。
update_line=""
sync_line=""
if [ -f "$plugin_root/scripts/update-check.sh" ]; then
  # shellcheck source=../scripts/update-check.sh
  . "$plugin_root/scripts/update-check.sh" 2>/dev/null || true
  if command -v harness_update_notice >/dev/null 2>&1; then
    # 同じ理由で外側に >/dev/null 2>&1 を付けない (このすぐ上のコメント参照)。
    harness_update_fetch_async "$plugin_root" || true
    update_line="$(harness_update_notice "$plugin_root" "$root" 2>/dev/null || true)"
    # 複数行は 1 行にまとめる (区切り「 ／ 」・2 つ目の [harness] は落とす)。
    update_line="$(printf '%s\n' "$update_line" | awk 'NF{ if (n++) { sub(/^\[harness\] /, ""); printf " ／ %s", $0 } else printf "%s", $0 } END{ if (n) printf "\n" }')"
    update_line="${update_line%$'\n'}"
    # 画面下部のお知らせ枠へ結果を渡す (statusline はプラグインのパスを知れないため)。
    # フラグの鍵はプロジェクト側のパス (root) にする (plugin_root では 1.x/2.x や
    # 別案件どうしの「更新あり」表示が入れ替わる)。
    harness_update_flag_sync "$plugin_root" "$root" >/dev/null 2>&1 || true
  fi
  # --- 更新後の入れ替え: **既定 off**。/config で on にした人だけ、プラグインが
  # 新しくなった回に限り、複製された 3 ファイル (statusline.sh / tasks-path.sh /
  # context-usage.sh) を配布版に揃える。ルール・設定・CLAUDE.md・台帳には触らない。
  if command -v harness_sync_owned_scripts >/dev/null 2>&1; then
    sync_line="$(harness_sync_owned_scripts "$plugin_root" "$root" 2>/dev/null || true)"
  fi
fi

# --- 直近 state (導入先リポジトリ側) ---
state=""
# 控えの dir は /state save・resume と同じ harness_state_dir (渡された dir → harness_root の順で在る方)。docs/state は古い置き場。
state_dirs=("$root/.claude/state" "$root/docs/state")
command -v harness_state_dir >/dev/null 2>&1 && state_dirs=("$(harness_state_dir "$opened")" "$root/docs/state")
for d in "${state_dirs[@]}"; do
  [ -d "$d" ] || continue
  # coordinator は Orca の担当の宛先の控え (再開用の state ではない)。続きの判定から外す。
  f="$(ls -t "$d" 2>/dev/null | grep -v '^coordinator' | head -1)"
  [ -n "$f" ] && state="${d#"$root"/}/$f" && break
done

# --- 効いている設定: 版と tasks / worktree / notify を 1 行で (何が効いているかを 1 か所で見る) ---
plugin_version=""
command -v harness_local_version >/dev/null 2>&1 && plugin_version="$(harness_local_version "$plugin_root" 2>/dev/null || true)"
# 3 項目の値は harness_setting 系の 1 本から (HC_* > TKM_HARNESS_* > settings の file > mode.yml > 既定)。
cfg_worktree="${HC_WORKTREE:-}"; cfg_notify="${HC_NOTIFY:-}"
if command -v harness_worktree >/dev/null 2>&1; then
  cfg_worktree="$(harness_worktree "$root" 2>/dev/null || true)"
  cfg_notify="$(harness_notify "$root" 2>/dev/null || true)"
fi
# mode.yml にだけ在る項目があれば、settings の env への移し方を 1 行で言う (HM-R2.4・TKS-R3.2。mode は settings.local.json へ・ほかは settings.json へ)
migrate_line=""
if command -v harness_setting_from_yml_only >/dev/null 2>&1 && [ -n "$(harness_setting_from_yml_only "$root" 2>/dev/null || true)" ]; then
  migrate_line="[harness] mode.yml にだけある設定（$(harness_setting_from_yml_only "$root" 2>/dev/null | sed 's/ /・/g')）は settings の env（TKM_HARNESS_MODE など）へ移せます。mode は .claude/settings.local.json・ほかは .claude/settings.json（/tkm-harness:update）"
fi
settings_line="tkm-harness ${plugin_version:+v${plugin_version}・}tasks: ${tasks_form}・worktree: ${cfg_worktree:-off}・notify: ${cfg_notify:-off}"

emit_session_lines() {
# 5 行以内を守るため、効いている設定は進め方の行の後ろに足す (行を増やさない)
echo "[harness] 進め方: ${mode_line} ／ ${settings_line}"
echo "[harness] ${task_line}"
if [ -n "$state" ]; then
  echo "[harness] 前回の続き: ${state} (/tkm-harness:state resume で読み込めます)"
else
  echo "[harness] 前回の続き: なし"
fi
# 更新の合図と入れ替えの報告は、重なっても 1 行にまとめる
extra_line="$update_line"
if [ -n "$sync_line" ]; then
  if [ -n "$extra_line" ]; then extra_line="${extra_line} ／ ${sync_line#\[harness\] }"; else extra_line="$sync_line"; fi
fi
# 移行の案内もここへ足す (開始時の表示は 5 行以内)
if [ -n "$migrate_line" ]; then
  if [ -n "$extra_line" ]; then extra_line="${extra_line} ／ ${migrate_line#\[harness\] }"; else extra_line="$migrate_line"; fi
fi
[ -n "$extra_line" ] && echo "$extra_line"
# Orca の worktree の警告・知らせ方 (worktree / notify が off なら何も出ない)。
# 何行出ても 1 行にまとめる (開始時の表示は 5 行以内: 設定 / タスク / 前回 / 更新 / Orca)。
if [ -f "$plugin_root/scripts/orca-context.sh" ]; then
  orca_out="$(CLAUDE_PROJECT_DIR="$root" bash "$plugin_root/scripts/orca-context.sh" 2>/dev/null || true)"
  if [ -n "$orca_out" ]; then
    printf '%s\n' "$orca_out" | awk 'NR==1{printf "%s", $0; next} {sub(/^\[harness\] /, ""); printf " ／ %s", $0} END{printf "\n"}'
  fi
fi
}

# --- 進みの表 (TKM-R9.1): 親がいない会話 (コーディネーター) の会話の始まり・/clear・圧縮のあとにだけ、控えの表を丸ごと additionalContext で入れる ---
# GitHub は叩かない (--cached は控えだけ)。担当の会話・GitHub Project で回さないリポ・hirai-task が無いときは何も足さない。
# TKM_HARNESS_LOAD_ON_START=off (settings.json の env) なら入れない (TKM-R9.2)。
LOAD_LIMIT_SEC="${HARNESS_LOAD_LIMIT_SEC:-10}"   # load の呼び出しの上限 (秒)。試験だけが短くする
case "$LOAD_LIMIT_SEC" in ''|*[!0-9]*) LOAD_LIMIT_SEC=10 ;; esac
# run_limited <秒> <コマンド...> -> 標準出力をそのまま出す。時間切れは process group ごと止めて exit 124。それ以外はコマンドの exit
run_limited() {
  python3 -I -c '
import os, signal, subprocess, sys
p = subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
try:
    out, _ = p.communicate(timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except OSError:
        pass
    p.communicate()
    sys.exit(124)
sys.stdout.buffer.write(out)
sys.exit(p.returncode)
' "$@"
}
# session_load_context <hirai-task の絶対 path> <root> -> 入れる文 (入れないときは空)
session_load_context() {
  local task="$1" lroot="$2" rc=0 out=""
  command -v python3 >/dev/null 2>&1 || return 0
  [ "$(harness_setting load_on_start "$lroot" 2>/dev/null || true)" != "off" ] || return 0
  HIRAI_TASK_ROOT="$lroot" run_limited "$LOAD_LIMIT_SEC" "$task" is-coordinator >/dev/null || rc=$?
  case "$rc" in
    0) ;;
    3) printf '%s\n' "[harness] 進みの表: この会話に親（立てたコーディネーター）がいるか判定できなかったので入れていません（担当なら何もしない・コーディネーターなら \`hirai-task load\` で出す）"; return 0 ;;
    124) printf '%s\n' "[harness] 進みの表: 親の有無の判定が ${LOAD_LIMIT_SEC} 秒で終わらなかったので入れていません（\`hirai-task load\` で出せる）"; return 0 ;;
    *) return 0 ;;
  esac
  rc=0
  out="$(HIRAI_TASK_ROOT="$lroot" run_limited "$LOAD_LIMIT_SEC" "$task" load --cached)" || rc=$?
  case "$rc" in
    0) printf '%s\n%s\n' "[harness] 進みの表（\`hirai-task load --cached\`。GitHub は叩いていません）" "$out" ;;
    3) printf '%s\n' "[harness] 進みの表の控えがありません（\`hirai-task load\` で作る）" ;;
    124) printf '%s\n' "[harness] 進みの表: ${LOAD_LIMIT_SEC} 秒で出せなかったので入れていません（\`hirai-task load\` で出せる）" ;;
    *) printf '%s\n' "[harness] 進みの表を出せませんでした（\`hirai-task load --cached\` が exit ${rc}。\`hirai-task load\` で出す）" ;;
  esac
}
load_ctx=""
if [ "$tasks_form" = "github-project" ] && [ -n "${pm_task:-}" ] && command -v harness_setting >/dev/null 2>&1; then
  load_ctx="$(session_load_context "$pm_task" "$root" 2>/dev/null || true)"
fi

session_lines="$(emit_session_lines)"
if [ -z "$load_ctx" ]; then
  printf '%s\n' "$session_lines"
else
  # 開始時の行と表を、1 つの additionalContext にする (標準出力は JSON か平文のどちらか 1 つ)
  { printf '%s\n\n' "$session_lines"; printf '%s' "$load_ctx"; } | python3 -I -c '
import json, sys
text = sys.stdin.read().rstrip("\n")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}, ensure_ascii=False))
' 2>/dev/null || printf '%s\n' "$session_lines"
fi

exit 0
