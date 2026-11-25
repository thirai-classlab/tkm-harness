#!/usr/bin/env bash
# 台帳 / 設計 draft / 事故記録 / 進め方 / ルールの パス解決を 1 箇所に集める共通ライブラリ。source して使う。
#
# **プロジェクトの書類は常に docs/ に置く** (v1.9.0)。.claude/ 側を見続けるのは、v1.7.0 までに
# 導入した環境が /tkm-harness:update で docs/ へ移行するまでの間、および移行しない選択をした環境で
# 台帳を見失わないため。解決順そのものは v1.8.0 から 1 バイトも変えていない。
#
# 共通の解決順: env 上書き > 既存パス (docs 側 → .claude 側) > docs/ の有無で決める
#   台帳     : HARNESS_TASKS_FILE     > docs/tasks/list.md            > .claude/tasks/list.md
#   draft    : HARNESS_DRAFT_DIR      > docs/draft/                   > .claude/draft/
#   事故記録 : HARNESS_INCIDENTS_FILE > docs/rules-reference/…        > .claude/rules-reference/…
# 台帳が 1 つも無い場合は空文字 + exit 1 を返す (エラーにせず呼び出し側で分岐する)。
# draft / 事故記録は未作成でも「これから作るべきパス」を返す (rc 0)。
#
# 進め方 / ルールは配置先が 2 通りある (プロジェクト側 = .claude/ と 全プロジェクト共通 = $HOME/.claude/)。
# どちらに置いたかを決め打ちすると、片方に置いた利用者に対して黙って外れる。**在る側**を選ぶ。
#   進め方   : HC_MODE (env) > <root>/.claude/mode.yml の mode > $HOME/.claude/mode.yml の mode > normal (項目ごとに引く)
#   入れ替え : HC_AUTO_SYNC (env) > 項目ごとに プロジェクト > ホーム の auto_sync > off (既定は入れ替えない)
#   形       : harness_setting (下記「機能の切り替え」) の tasks (ledger / github-project) > ledger
#   ルール   : HARNESS_RULES_DIR > <dir>/.claude/rules > <root>/.claude/rules > $HOME/.claude/rules > <root>/.claude/rules
#
# file-top に set -e / set -o pipefail を書かない。source 元の shell flags を汚染し、
# パイプ先の早期終了で呼び出し元ごと落ちる事故を防ぐため (関数内で局所化する)。

# _harness_phys <dir> -> dir の実体の絶対 path (symlink を解く)。解けなければ何も出さず rc 1。
# cd は CDPATH を空にし、builtin で呼び (chpwd・alias・関数を避け)、出力を捨てる (zsh の chpwd の ls が混ざらない)。
_harness_phys() {
  CDPATH= builtin cd -- "$1" >/dev/null 2>&1 && builtin pwd -P
}

# _harness_abs <dir> -> 絶対 path (. や .. を畳み、symlink を解く。dir が無ければ $PWD を前に付けるだけ)。
_harness_abs() {
  local d="${1:-$PWD}" a
  a="$(_harness_phys "$d")" || { case "$d" in /*) a="$d" ;; *) a="$PWD/$d" ;; esac; }
  [ "$a" = / ] || a="${a%/}"
  printf '%s' "$a"
}

# _harness_resolve [dir] -> 上へ辿って 2 つを決め、_HR_TOP (git の toplevel。無ければ空) と
# _HR_FIRST (dir から toplevel までで最初に .claude/mode.yml・.claude/settings.json・.claude/rules が在る dir。無ければ空)、
# _HR_PKG (同じく最初に .claude/mode.yml が在る dir。無ければ空。mode:・tasks:・auto_sync: の「パッケージ」) に入れる。
# toplevel が HOME か HOME の祖先なら git でないものとして扱う (ホームの git を「リポ」と読まない)。
# ファイルの有無だけで決め、git を打たない (毎回動く画面下と hook を遅くしない)。常に rc 0。
_harness_resolve() {
  local d cur h
  d="$(_harness_abs "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  _HR_TOP=""; _HR_FIRST=""; _HR_PKG=""
  cur="$d"
  while :; do
    if [ -z "$_HR_PKG" ] && [ -f "$cur/.claude/mode.yml" ]; then _HR_PKG="$cur"; fi
    if [ -z "$_HR_FIRST" ] && { [ -f "$cur/.claude/mode.yml" ] || [ -f "$cur/.claude/settings.json" ] || [ -d "$cur/.claude/rules" ]; }; then
      _HR_FIRST="$cur"
    fi
    if [ -e "$cur/.git" ]; then _HR_TOP="$cur"; break; fi
    [ "$cur" = / ] && break
    cur="${cur%/*}"; [ -n "$cur" ] || cur=/
  done
  if [ -n "$_HR_TOP" ]; then
    h="${HOME:-}"; [ -z "$h" ] || h="$(_harness_phys "$h" 2>/dev/null || printf '%s' "$h")"; [ "$h" = / ] || h="${h%/}"
    if [ "$_HR_TOP" = / ] || { [ -n "$h" ] && { [ "$_HR_TOP" = "$h" ] || case "$h/" in "$_HR_TOP"/*) true ;; *) false ;; esac; }; }; then
      _HR_TOP=""
    fi
  fi
  [ -n "$_HR_TOP" ] || { _HR_FIRST=""; _HR_PKG=""; }
  return 0
}

# harness_top [dir] -> dir を含む git の toplevel を stdout。git でない・toplevel が HOME か HOME の祖先なら dir のまま。常に rc 0。
# worktree:・notify:・nightly_ci: の mode.yml はここだけから引く (worktree-guard・hirai-notify・orca-context と同じ root)。
harness_top() {
  local d
  d="$(_harness_abs "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  _harness_resolve "$d"
  if [ -n "$_HR_TOP" ]; then printf '%s' "$_HR_TOP"; else printf '%s' "$d"; fi
  return 0
}

# harness_root [dir] -> ハーネスの設定 (.claude/mode.yml・settings.json・rules・state・台帳) の root を stdout。常に rc 0。
# dir から git の toplevel まで上へ見て、最初に .claude/mode.yml か .claude/settings.json か .claude/rules が在る dir。
# どこにも無ければ toplevel (自分の .claude を持たない apps/api は toplevel、自分の .claude を持つパッケージはそこ)。
# git でない・toplevel が HOME か HOME の祖先なら dir のまま (HOME の .claude は「ホーム側」として別に引く)。
harness_root() {
  local d
  d="$(_harness_abs "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  _harness_resolve "$d"
  if [ -n "$_HR_FIRST" ]; then printf '%s' "$_HR_FIRST"
  elif [ -n "$_HR_TOP" ]; then printf '%s' "$_HR_TOP"
  else printf '%s' "$d"; fi
  return 0
}

# harness_state_dir [dir] -> 作業の控え (.claude/state) の dir を stdout。常に rc 0。
# 渡された dir → harness_root の順で、coordinator 以外のファイルが在る方。どちらにも無ければ新しく作る場所 (harness_root の下)。
# /state save・resume と開始時の「前回の続き」が同じこの 1 本を通す。
harness_state_dir() {
  local d r p
  d="$(_harness_abs "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  r="$(harness_root "$d")"
  for p in "$d/.claude/state" "$r/.claude/state"; do
    if [ -d "$p" ] && ls -A "$p" 2>/dev/null | grep -v '^coordinator' | grep -q .; then
      printf '%s' "$p"
      return 0
    fi
  done
  printf '%s' "$r/.claude/state"
  return 0
}

# harness_tasks_file [dir] -> 台帳パスを stdout、無ければ空 + rc 1
# 渡された dir → harness_root → toplevel の順で在るもの。
harness_tasks_file() {
  local d="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" r t p
  if [ -n "${HARNESS_TASKS_FILE:-}" ]; then
    printf '%s' "$HARNESS_TASKS_FILE"
    return 0
  fi
  r="$(harness_root "$d")"; t="$(harness_top "$d")"
  for p in "$d/docs/tasks/list.md" "$d/.claude/tasks/list.md" "$r/docs/tasks/list.md" "$r/.claude/tasks/list.md" "$t/docs/tasks/list.md" "$t/.claude/tasks/list.md"; do
    if [ -f "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# harness_draft_dir [dir] -> 設計 draft の置き場を stdout (末尾スラッシュなし)
# 既にある dir (渡された dir → harness_root → toplevel の順)。無ければ harness_root の下の作るべき場所。
harness_draft_dir() {
  local d="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" r t p
  if [ -n "${HARNESS_DRAFT_DIR:-}" ]; then
    printf '%s' "$HARNESS_DRAFT_DIR"
    return 0
  fi
  r="$(harness_root "$d")"; t="$(harness_top "$d")"
  for p in "$d/docs/draft" "$d/.claude/draft" "$r/docs/draft" "$r/.claude/draft" "$t/docs/draft" "$t/.claude/draft"; do
    if [ -d "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
  if [ -d "$r/docs" ]; then printf '%s' "$r/docs/draft"; else printf '%s' "$r/.claude/draft"; fi
}

# harness_incidents_file [dir] -> 事故記録 (T2) のパスを stdout
harness_incidents_file() {
  local d="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" r t p
  if [ -n "${HARNESS_INCIDENTS_FILE:-}" ]; then
    printf '%s' "$HARNESS_INCIDENTS_FILE"
    return 0
  fi
  r="$(harness_root "$d")"; t="$(harness_top "$d")"
  for p in "$d/docs/rules-reference/incidents.md" "$d/.claude/rules-reference/incidents.md" "$r/docs/rules-reference/incidents.md" "$r/.claude/rules-reference/incidents.md" "$t/docs/rules-reference/incidents.md" "$t/.claude/rules-reference/incidents.md"; do
    if [ -f "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
  if [ -d "$r/docs" ]; then
    printf '%s' "$r/docs/rules-reference/incidents.md"
  else
    printf '%s' "$r/.claude/rules-reference/incidents.md"
  fi
}

# --- 進め方 (mode) ------------------------------------------------------------
# 読む側 (SessionStart / 画面下部) と書く側 (/config) が別々の順で解決すると、
# 「セッション冒頭は normal・画面下部は loop」のように食い違う。3 箇所ともここを通す。

# _harness_yml_candidates <dir> <キー> -> そのキーを引く mode.yml のパスを _HY_PKG → _HY_TOP → _HY_HOME に入れる (無い所は空)。
# mode:・tasks:・auto_sync: などは「パッケージ (dir から toplevel までで最初に .claude/mode.yml を持つ dir) → toplevel → ホーム」。
# worktree:・notify:・nightly_ci: は「toplevel → ホーム」だけ (サブディレクトリのは読まない)。
# git でない・toplevel が HOME か HOME の祖先なら、toplevel の代わりに dir 自身。
_harness_yml_candidates() {
  local d top pkg
  d="$(_harness_abs "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  _harness_resolve "$d"
  pkg="$_HR_PKG"
  if [ -n "$_HR_TOP" ]; then top="$_HR_TOP"; else top="$d"; fi
  case "${2:-}" in
    worktree|notify|nightly_ci) pkg="" ;;
  esac
  _HY_PKG=""; _HY_TOP=""; _HY_HOME=""
  [ -z "$pkg" ] || _HY_PKG="$pkg/.claude/mode.yml"
  [ "$top" = "$pkg" ] || _HY_TOP="$top/.claude/mode.yml"
  [ -z "${HOME:-}" ] || _HY_HOME="$HOME/.claude/mode.yml"
}

# harness_mode_file [root] -> すでに在る mode.yml のパスを stdout。
# パッケージ → toplevel → ホーム側の順で探し、どこにも無ければ空 + rc 1。
harness_mode_file() {
  local p
  _harness_yml_candidates "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" mode
  for p in "$_HY_PKG" "$_HY_TOP" "$_HY_HOME"; do
    if [ -n "$p" ] && [ -f "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# harness_mode_write_file [root] -> /config が書き込むべきパスを stdout (常に rc 0)。
# **すでに在る側に書く。** 両方に無いときだけプロジェクト側に作る。
# (ホーム側に置いた人のプロジェクトへ mode.yml を新設すると、ホーム側を黙って覆い隠す)
harness_mode_write_file() {
  local root p
  root="$(harness_root "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  if p="$(harness_mode_file "$root")"; then
    printf '%s' "$p"
    return 0
  fi
  printf '%s' "$root/.claude/mode.yml"
}

# harness_mode [root] -> いまの進め方 (normal / loop / 未知の値) を stdout。常に rc 0。
# env HC_MODE > プロジェクトの mode.yml の mode: > ホームの mode.yml の mode: > normal。
# 項目ごとに引く (プロジェクト側に mode: が無ければホーム側の値を使う)。読めない・空・壊れている場合も normal。
harness_mode() {
  local root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" m=""
  if [ -n "${HC_MODE:-}" ]; then
    printf '%s' "$HC_MODE"
    return 0
  fi
  m="$(harness_yml_value "$root" mode)"
  [ -n "$m" ] || m="normal"
  printf '%s' "$m"
}

# --- 更新後の入れ替え (auto_sync) ---------------------------------------------
# プラグイン所有の 3 ファイル (statusline.sh / tasks-path.sh / context-usage.sh) を、
# プラグインが新しくなった後に自動で入れ替えるかどうか。**既定は off (入れ替えない)。**
# 更新は挙動の変更なので、黙って書き換わると「昨日と違う動きをする理由」を追えなくなる。
# 解決順: env HC_AUTO_SYNC > 在る側の mode.yml の auto_sync > off
# 進め方 (mode) と同じ 1 本を通す (置き場を自分で組み立てない)。

# harness_auto_sync [root] -> on / off (未知の値はそのまま) を stdout。常に rc 0。
harness_auto_sync() {
  local root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" v=""
  if [ -n "${HC_AUTO_SYNC:-}" ]; then
    printf '%s' "$HC_AUTO_SYNC"
    return 0
  fi
  v="$(harness_yml_value "$root" auto_sync)"
  [ -n "$v" ] || v="off"
  printf '%s' "$v"
}

# --- 機能の切り替え (tasks・worktree・notify) ---------------------------------
# 3 項目は各リポの .claude/settings.json の env (TKM_HARNESS_TASKS・TKM_HARNESS_WORKTREE・TKM_HARNESS_NOTIFY) で宣言する。
# プラグインがプロジェクトの settings.json から読めるのは env だけ (https://code.claude.com/docs/en/settings-reference.md#env)。
# tasks は Project の有無・remote・gh の成否からは見分けない (見分けに失敗して尋ねて止まる道を無くすため。GraphQL を打つのは github-project のときだけ)。
# 優先は上から:
#   1. シェルの HC_TASKS・HC_WORKTREE・HC_NOTIFY (一時の上書き。コーディネーターは HC_NOTIFY=off claude で開く)
#   2. 環境変数 TKM_HARNESS_<項目> (Claude Code の中では settings.local.json > settings.json の env が重なって届く。
#      実測 2.1.312: 同じ名前ならシェルの値より settings の値が勝つ。だから 1 は別の名前 HC_* にしてある)
#   3. Claude Code の外 (端末・CI) のための file 読み: 本体の checkout の settings.local.json → toplevel の settings.local.json
#      → toplevel の settings.json → ~/.claude/settings.json の env.TKM_HARNESS_<項目> (python3 が無ければ飛ばす)。
#      Claude Code の中でも 2 が空なら読む (開いたあとに書いた値と、移す前に開いた会話で既定に戻らないため)
#   4. .claude/mode.yml の tasks:・worktree:・notify: (移行用。4.x の間だけ読む)
#   5. 既定 (tasks=ledger・worktree=off・notify=off)。未知の値は既定に倒す

# harness_yml_file_value <file> <キー> -> その file の <キー>: の値を stdout。無ければ空。常に rc 0。
# 値の前後の空白と引用符 (" と ') と、行末のコメント (空白のあとの # から) を外す。
harness_yml_file_value() {
  local f="${1:-}" k="${2:-}"
  [ -n "$k" ] && [ -f "$f" ] || return 0
  sed -nE "s/^[[:space:]]*${k}:[[:space:]]*(.*)\$/\\1/p" "$f" 2>/dev/null | head -1 \
    | sed -E 's/(^|[[:space:]]+)#.*$//; s/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

# harness_yml_value <root> <キー> -> <キー>: の値を stdout。無ければ空。常に rc 0。
# 項目ごとに「パッケージ (最初に .claude/mode.yml を持つ dir) → toplevel → ホームの ~/.claude/mode.yml」の順で引く
# (片方のファイルだけを読まない。env の上書きと既定は呼び出し側で扱う)。
# ただし worktree・notify・nightly_ci は「toplevel → ホーム」だけ (_harness_yml_candidates)。
harness_yml_value() {
  local k="${2:-}" v="" p
  [ -n "$k" ] || return 0
  _harness_yml_candidates "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" "$k"
  for p in "$_HY_PKG" "$_HY_TOP" "$_HY_HOME"; do
    [ -n "$p" ] || continue
    v="$(harness_yml_file_value "$p" "$k")"
    [ -z "$v" ] || break
  done
  printf '%s' "$v"
}

# _harness_setting_files <root> [nohome] -> 3 の file 読みで見る settings の path を 1 行ずつ stdout (在るかは見ない)。
# 本体の checkout は git-common-dir の親 (harness_pm_install_dir の disabled() と同じ。worktree でも Claude Code は本体の settings.local.json を使う)。
_harness_setting_files() {
  local top common main=""
  top="$(harness_top "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  common="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ "${common##*/}" = ".git" ] && main="${common%/*}"
  [ -z "$main" ] || printf '%s\n' "$main/.claude/settings.local.json"
  printf '%s\n' "$top/.claude/settings.local.json" "$top/.claude/settings.json"
  [ "${2:-}" = "nohome" ] || [ -z "${HOME:-}" ] || printf '%s\n' "$HOME/.claude/settings.json"
}

# _harness_file_setting <項目> <root> [nohome] -> 3 の値 (settings の file の env.TKM_HARNESS_<項目>。最初に在った file の値)。無ければ空。
# python3 が無ければ空。値は文字列だけ読む。
_harness_file_setting() {
  local up files="" f
  command -v python3 >/dev/null 2>&1 || return 0
  case "${1:-}" in tasks) up=TASKS ;; worktree) up=WORKTREE ;; notify) up=NOTIFY ;; *) return 0 ;; esac
  while IFS= read -r f; do [ -f "$f" ] && files="${files}${f}"$'\n'; done <<EOF_F
$(_harness_setting_files "${2:-}" "${3:-}")
EOF_F
  [ -n "$files" ] || return 0
  printf '%s' "$files" | python3 -I -c 'import json,sys
n = sys.argv[1]
for p in sys.stdin.read().split("\n"):
    if not p:
        continue
    try:
        v = (json.load(open(p, encoding="utf-8")).get("env") or {}).get(n)
    except Exception:
        continue
    if isinstance(v, str) and v.strip():
        print(v.strip(), end="")
        break' "TKM_HARNESS_$up" 2>/dev/null
}

# harness_setting <tasks|worktree|notify> [root] [files] -> 上の優先 1〜4 で決めた値をそのまま stdout (無ければ空。既定と未知の値の扱いは呼ぶ側)。常に rc 0。
# 3 つ目の引数 files は「この root は会話のリポでない」の印 (worktree-guard が別のリポの対象を決めるとき): 2 を使わず 3 を読む。
harness_setting() {
  local item="${1:-}" root="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}" up hc env v
  case "$item" in tasks) up=TASKS ;; worktree) up=WORKTREE ;; notify) up=NOTIFY ;; *) return 0 ;; esac
  hc="HC_$up"; env="TKM_HARNESS_$up"
  v="${!hc:-}"; v="${v%$'\n'}"
  if [ -z "$v" ] && [ "${3:-}" != "files" ]; then v="${!env:-}"; v="${v%$'\n'}"; fi
  if [ -z "$v" ]; then   # Claude Code の中でも環境変数が空なら file を読む (会話を開いたあとに書いた値・開く前の env が古い会話に効かせる)
    v="$(_harness_file_setting "$item" "$root")"
  fi
  [ -n "$v" ] || v="$(harness_yml_value "$root" "$item")"
  printf '%s' "$v"
  return 0
}

# harness_setting_from_yml_only <root> -> mode.yml にだけ値が在る項目 (1〜3 に無く 4 にだけ在る) を空白区切りで stdout。無ければ空。
# 会話の開始時の移行の案内 (HM-R2.4) が使う。
harness_setting_from_yml_only() {
  local root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" item up hc env out=""
  for item in tasks worktree notify; do
    case "$item" in tasks) up=TASKS ;; worktree) up=WORKTREE ;; notify) up=NOTIFY ;; esac
    hc="HC_$up"; env="TKM_HARNESS_$up"
    [ -z "${!hc:-}" ] && [ -z "${!env:-}" ] || continue
    [ -z "$(_harness_file_setting "$item" "$root")" ] || continue
    [ -z "$(harness_yml_value "$root" "$item")" ] || out="${out:+$out }$item"
  done
  printf '%s' "$out"
}

# harness_tasks_form [root] -> ledger / github-project を stdout。常に rc 0。項目が無い・空・未知の値は ledger (台帳。1.x と同じ動き)。
harness_tasks_form() {
  case "$(harness_setting tasks "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")" in
    github-project) printf 'github-project' ;;
    *) printf 'ledger' ;;
  esac
  return 0
}

# harness_worktree [root] [files] -> off / warn / block を stdout。未知の値は off。常に rc 0。
harness_worktree() {
  case "$(harness_setting worktree "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" "${2:-}")" in
    block) printf 'block' ;;
    warn) printf 'warn' ;;
    *) printf 'off' ;;
  esac
  return 0
}

# harness_notify [root] [files] -> off / orca を stdout。未知の値は off。常に rc 0。
harness_notify() {
  case "$(harness_setting notify "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" "${2:-}")" in
    orca) printf 'orca' ;;
    *) printf 'off' ;;
  esac
  return 0
}

# harness_yml_unset <file> <キー> -> その file の <キー>: の行を消す (他の行は 1 バイトも触らない)。file が無い・行が無いときは何もしない。
harness_yml_unset() (
  set -uo pipefail
  local f="${1:-}" k="${2:-}" tmp
  [ -n "$k" ] && [ -f "$f" ] || return 0
  grep -Eq "^[[:space:]]*${k}:" "$f" 2>/dev/null || return 0
  tmp="$f.tmp.$$"
  awk -v k="$k" '$0 !~ "^[[:space:]]*" k ":" { print }' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
)

# _harness_yml_after_set <項目> <値> <root> -> settings へ書いたあとの mode.yml の行の扱い。
# worktree は行を消す。tasks・notify は消さず値を settings と同じにそろえる (hirai-task の is_coordinator は今も mode.yml だけを読むため。読み先がそろうまで)。
_harness_yml_after_set() {
  local item="$1" val="$2" p tmp
  _harness_yml_candidates "$3" "$item"
  for p in "$_HY_PKG" "$_HY_TOP"; do
    [ -n "$p" ] || continue
    case "$item" in
      tasks|notify)
        [ -f "$p" ] && grep -Eq "^[[:space:]]*${item}:" "$p" 2>/dev/null || continue
        tmp="$p.tmp.$$"
        awk -v k="$item" -v v="$val" '$0 ~ "^[[:space:]]*" k ":" { print k ": " v; next } { print }' "$p" > "$tmp" 2>/dev/null \
          && mv -f "$tmp" "$p" 2>/dev/null || rm -f "$tmp" 2>/dev/null ;;
      *) harness_yml_unset "$p" "$item" || true ;;
    esac
  done
  return 0
}

# harness_settings_set <tasks|worktree|notify> <値> [root] [local] -> プロジェクト (toplevel) の .claude/settings.json の env.TKM_HARNESS_<項目> に書く
# (4 つ目の引数 local なら settings.local.json。自分だけ変えたいとき)。ほかのキーは触らない (python3 -I で読み、indent 2・ensure_ascii False で書き戻す)。
# 書けたら (local でないとき)、同じ項目の行がプロジェクトの mode.yml (パッケージと toplevel) にあれば、worktree は消し、tasks・notify は値をそろえる
# (hirai-task が今も mode.yml だけを読むため消さない)。JSON が読めない file は上書きしない (rc 1)。
# 書いた path を stdout に 1 行。値は項目ごとの許す値だけ (rc 2)。
harness_settings_set() {
  local item="${1:-}" val="${2:-}" root top up f
  root="${3:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  case "$item" in
    tasks) up=TASKS; case "$val" in ledger|github-project) ;; *) return 2 ;; esac ;;
    worktree) up=WORKTREE; case "$val" in off|warn|block) ;; *) return 2 ;; esac ;;
    notify) up=NOTIFY; case "$val" in off|orca) ;; *) return 2 ;; esac ;;
    *) return 2 ;;
  esac
  command -v python3 >/dev/null 2>&1 || return 1
  top="$(harness_top "$root")"
  f="$top/.claude/settings.json"; [ "${4:-}" = "local" ] && f="$top/.claude/settings.local.json"
  mkdir -p "$top/.claude" 2>/dev/null || return 1
  python3 -I -c 'import json,os,sys
p, name, val = sys.argv[1:4]
d = {}
if os.path.exists(p):
    with open(p, encoding="utf-8") as fh:
        raw = fh.read()
    if raw.strip():
        d = json.loads(raw)
    if not isinstance(d, dict):
        sys.exit(1)
env = d.get("env")
if env is None:
    env = {}
if not isinstance(env, dict):
    sys.exit(1)
env[name] = val
d["env"] = env
tmp = p + ".tmp." + str(os.getpid())
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
os.replace(tmp, p)' "$f" "TKM_HARNESS_$up" "$val" 2>/dev/null || return 1
  if [ "${4:-}" != "local" ]; then   # settings.local.json は自分だけの上書きなので、チームの mode.yml の行は残す
    _harness_yml_after_set "$item" "$val" "$root"
  fi
  printf '%s' "$f"
}

# harness_settings_migrate [root] -> プロジェクトの mode.yml (パッケージと toplevel) の tasks:・worktree:・notify: を、settings.json の env へ移す
# (/tkm-harness:update)。すでに settings の file (3 の file 読み) に値が在る項目は mode.yml 側だけ直す (worktree は行を消し、tasks・notify は値をそろえる。
# hirai-task が今も mode.yml を読むため tasks・notify の行は残す)。パッケージの tasks: は移さない (toplevel の env が先に効くため)。許さない値の項目は動かさず 1 行で言う。
# ホームの mode.yml は動かさない (ほかのリポにも効くため)。出力は項目ごとに 1 行。何も無ければ無出力。rc 0 (書けなかった項目があれば rc 1)。
harness_settings_migrate() {
  local root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" top item v cur path rc=0
  top="$(harness_top "$root")"
  for item in tasks worktree notify; do
    _harness_yml_candidates "$root" "$item"
    v=""
    [ -z "$_HY_PKG" ] || v="$(harness_yml_file_value "$_HY_PKG" "$item")"
    if [ "$item" = tasks ] && [ -n "$v" ] && [ "$_HY_PKG" != "$top/.claude/mode.yml" ]; then   # パッケージの tasks: は toplevel の env に上げると先に効いて変わるため移さない
      printf 'tasks: パッケージの mode.yml (%s) の %s は移しません (toplevel の env へ上げると、パッケージの値より先に効くため。mode.yml のまま)\n' "$_HY_PKG" "$v"
      continue
    fi
    [ -n "$v" ] || { [ -z "$_HY_TOP" ] || v="$(harness_yml_file_value "$_HY_TOP" "$item")"; }
    [ -n "$v" ] || continue
    cur="$(_harness_file_setting "$item" "$top" nohome)"
    if [ -n "$cur" ]; then
      [ "$item" != worktree ] && [ "$v" = "$cur" ] && continue   # tasks・notify は行を残すので、そろっていれば 2 度目は何も言わない
      _harness_yml_after_set "$item" "$cur" "$root"
      case "$item" in
        worktree) printf '%s: settings の env に %s が在るため、mode.yml の行だけ消しました\n' "$item" "$cur" ;;
        *) printf '%s: settings の env に %s が在るため、mode.yml の値をそろえました (hirai-task が mode.yml を読むので行は残します)\n' "$item" "$cur" ;;
      esac
      continue
    fi
    if path="$(harness_settings_set "$item" "$v" "$top")"; then
      case "$item" in
        worktree) printf '%s: %s を %s の env へ移しました (mode.yml の行は消しました)\n' "$item" "$v" "$path" ;;
        *) printf '%s: %s を %s の env へ移しました (mode.yml の行は hirai-task のために残しました)\n' "$item" "$v" "$path" ;;
      esac
    else
      printf '%s: %s を移せませんでした (値が許す形でない・settings.json が JSON として読めない・python3 が無い。mode.yml のまま残しています)\n' "$item" "$v"
      rc=1
    fi
  done
  return "$rc"
}

# harness_tasks_slug [root] -> origin の github.com の owner/repo から末尾の .git と / を外し、/ を - にした名前を stdout。
# 2.x の控えの名前と同じ作り方。github.com 以外・remote 無しは空。常に rc 0。
harness_tasks_slug() {
  local root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" url
  url="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
  case "$url" in
    *github.com*) printf '%s' "$url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#/+$##; s#/#-#g' 2>/dev/null ;;
  esac
  return 0
}

# harness_tasks_migrate [root] -> プロジェクトの settings.json の env に TKM_HARNESS_TASKS (と mode.yml の tasks:) が無いときだけ、1 度だけ書き込む
# (/tkm-harness:update の手順 2b)。プロジェクト側にだけ書く (ホームには書かない。ホームの値は他のリポにも効くため)。
# 2.x (hirai-lite-v2) の痕跡は、このリポの slug の控え (~/.claude/plugins/data/hirai-lite-v2-hirai-lite/
# tasks-<slug>.json) だけで見る (機械全体で見ない。別のリポの控えで書かない)。
#   控えの form が ghp                 -> github-project を書く
#   控えが在り form が ghp 以外        -> ledger を書く。ただしプロジェクトに .claude/settings.json か mode.yml が無いときは書かない
#                                         (ledger は既定と同じ。新しい .claude/ を作ると設定の置き場がそこへ移る)
#   控えが無い                          -> 書かない
# 出力は 1 行 (書いたら "tasks: <値> を <パス> に書きました (<理由>)"、書かなければ "tasks: 書きませんでした (<理由>)")。
# プロジェクト側にすでに tasks の値があれば何もしない (無出力・rc 0)。書けなかったら rc 1。以後は自動で見分けない。
harness_tasks_migrate() {
  local root top cur slug cache val why path
  root="$(harness_root "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  top="$(harness_top "$root")"
  cur="$(_harness_file_setting tasks "$top" nohome)"
  [ -n "$cur" ] || cur="$(harness_yml_file_value "$root/.claude/mode.yml" tasks)"
  [ -n "$cur" ] || cur="$(harness_yml_file_value "$top/.claude/mode.yml" tasks)"
  [ -z "$cur" ] || return 0
  slug="$(harness_tasks_slug "$root")"
  cache=""
  [ -z "$slug" ] || cache="$HOME/.claude/plugins/data/hirai-lite-v2-hirai-lite/tasks-${slug}.json"
  if [ -z "$cache" ] || [ ! -f "$cache" ]; then
    printf 'tasks: 書きませんでした (2.x の Project の控えが無い。tasks が無ければ ledger で動く。GitHub Project にするなら /tkm-harness:config の項目 8)\n'
    return 0
  fi
  if grep -Eq '"form"[[:space:]]*:[[:space:]]*"ghp"' "$cache" 2>/dev/null; then
    val="github-project"; why="2.x の Project の控え ($cache) が ghp のため"
  else
    val="ledger"; why="2.x の控え ($cache) が ghp ではないため"
    if [ ! -f "$top/.claude/settings.json" ] && [ ! -f "$top/.claude/mode.yml" ]; then
      printf 'tasks: 書きませんでした (ledger は既定と同じで、このリポに .claude/settings.json も mode.yml も無い。新しく作らない)\n'
      return 0
    fi
  fi
  path="$(harness_settings_set tasks "$val" "$top")" || return 1
  printf 'tasks: %s を %s の env に書きました (%s)\n' "$val" "$path" "$why"
}

# harness_pm_install_dir [root] -> プラグイン tkm-harness の、このリポの行のうち版が最大の installPath を stdout。
# 無ければ空 + rc 1 (python3 か installed_plugins.json が無いときも rc 1)。
# このリポの enabledPlugins (settings.local.json [本体の checkout のものも見る] → settings.json → ~/.claude/settings.json の順) で false なら「無い」とみなす。
# 「このリポの行」= scope が user・managed の行、または projectPath がこのリポと同じ git のリポの行。
# 同じ git のリポかは `git rev-parse --git-common-dir` (両方) が同じかで見る。worktree W1 で project の範囲に入れた行は、
# 本体の checkout・ほかの worktree からも同じリポとして当たる。projectPath が無い・git でないとき (消えた worktree など) だけ
# root との前方一致に落とす。行の絞りはここ 1 か所 (hirai-task の path・更新の知らせ・/update の見分けが使う)。
harness_pm_install_dir() {
  local root f="${HOME:-}/.claude/plugins/installed_plugins.json" p common
  root="$(harness_top "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  [ -f "$f" ] && command -v python3 >/dev/null 2>&1 || return 1
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  p="$(python3 -I -c 'import json,os,re,subprocess,sys
d = json.load(open(sys.argv[1]))
root = os.path.realpath(sys.argv[3]).rstrip("/")
common = os.path.realpath(sys.argv[4]) if sys.argv[4] else ""
def gc(path):
    try:
        o = subprocess.run(["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, timeout=5)
        return os.path.realpath(o.stdout.strip()) if o.returncode == 0 and o.stdout.strip() else ""
    except Exception:
        return ""
def disabled():
    # enabledPlugins で false なら「無い」とみなす。優先は local -> project -> user (最初に載っている値が決める)。
    # settings.local.json は git-common-dir の親 (本体の checkout) のものを先に見る (worktree でも Claude Code は本体のを使う)。
    main = os.path.dirname(common) if common and os.path.basename(common) == ".git" else ""
    cands = ([os.path.join(main, ".claude", "settings.local.json")] if main else []) + [os.path.join(root, ".claude", "settings.local.json"), os.path.join(root, ".claude", "settings.json"), os.path.join(os.path.expanduser("~"), ".claude", "settings.json")]
    for sp in cands:
        try:
            ep = json.load(open(sp)).get("enabledPlugins") or {}
        except Exception:
            continue
        for k, v in ep.items():
            if k.split("@", 1)[0] == sys.argv[2] and isinstance(v, bool):
                return v is False
    return False
def mine(x):
    if x.get("scope") in ("user", "managed"):
        return True
    pp = str(x.get("projectPath") or "").rstrip("/")
    if not pp:
        return False
    g = gc(pp) if os.path.isdir(pp) else ""
    if g and common:
        return g == common
    ppr = os.path.realpath(pp).rstrip("/")
    return root == ppr or root.startswith(ppr + "/")
rows = [] if disabled() else [x for k, v in d.get("plugins", {}).items() if k.split("@", 1)[0] == sys.argv[2] for x in v if x.get("installPath") and mine(x)]
rows.sort(key=lambda x: [int(n) if n.isdigit() else 0 for n in re.split(r"[.]", str(x.get("version", "0")).split("-", 1)[0])])
print(rows[-1]["installPath"] if rows else "")' "$f" tkm-harness "$root" "$common" 2>/dev/null)"
  [ -n "$p" ] || return 1
  printf '%s' "$p"
}

# harness_pm_task_bin [root] -> hirai-task の絶対 path を stdout。無ければ空 + rc 1。
# hook と画面下では、プラグインの bin/ は PATH に入らない (Bash ツールだけに入る)。PATH に頼らず探す:
#   1. ${CLAUDE_PLUGIN_ROOT}/bin/hirai-task (hook・command から呼ばれたとき。同じプラグインの中)
#   2. harness_pm_install_dir (installed_plugins.json の tkm-harness の行のうちこのリポの最大版) の bin/hirai-task
#   3. python3 が無いとき・installed_plugins.json が無いときだけ ~/.claude/plugins/cache/*/tkm-harness/ の最大版
#      (配布元の段は決め打ちしない。fork が別の配布元の名前で入れても当たる。
#       installed に行があるのに該当が無い = 外した・別のリポの install、のときは cache へ落ちない)
#   4. PATH の hirai-task
harness_pm_task_bin() {
  local root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}" f="${HOME:-}/.claude/plugins/installed_plugins.json" p="" c
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "${CLAUDE_PLUGIN_ROOT}/bin/hirai-task" ]; then
    printf '%s' "${CLAUDE_PLUGIN_ROOT}/bin/hirai-task"
    return 0
  fi
  if [ -f "$f" ] && command -v python3 >/dev/null 2>&1; then
    p="$(harness_pm_install_dir "$root" 2>/dev/null || true)"
    if [ -n "$p" ] && [ -x "$p/bin/hirai-task" ]; then
      printf '%s' "$p/bin/hirai-task"
      return 0
    fi
  else
    c="$(ls -d "${HOME:-}"/.claude/plugins/cache/*/tkm-harness/*/ 2>/dev/null | sort -V | tail -1)"
    c="${c%/}"
    if [ -n "$c" ] && [ -x "$c/bin/hirai-task" ]; then
      printf '%s' "$c/bin/hirai-task"
      return 0
    fi
  fi
  c="$(command -v hirai-task 2>/dev/null || true)"
  if [ -n "$c" ]; then
    printf '%s' "$c"
    return 0
  fi
  return 1
}

# harness_yml_set <file> <キー> <値> -> その 1 行だけを書き換える (他の行は 1 バイトも触らない)。
# キーの行が無ければ末尾に足し、file が無ければ作る。書けたら rc 0。
# mode.yml に 2 つ以上のキーが載るようになったため、丸ごと書き直すともう片方が消える。
harness_yml_set() (
  set -uo pipefail
  local f="${1:-}" k="${2:-}" v="${3:-}" tmp
  [ -n "$f" ] && [ -n "$k" ] || return 1
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 1
  [ -f "$f" ] || : > "$f" 2>/dev/null || return 1
  tmp="$f.tmp.$$"
  # awk は 1 行ずつ print するので、元が改行で終わっていなくても行が繋がらない。
  awk -v k="$k" -v v="$v" '
    $0 ~ "^[[:space:]]*" k ":" && !d { print k ": " v; d = 1; next }
    { print }
    END { if (!d) print k ": " v }
  ' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
)

# --- ルール (rules) -----------------------------------------------------------
# /add-rule の予算計算と /rules-audit の棚卸しが見る置き場。プロジェクト側を決め打ちすると、
# 全プロジェクト共通 (/init user) に置いた利用者に対して「既存ルール 0 件」と誤判定する。

# harness_rules_dir [dir] -> ルールの置き場 (渡された dir に在ればそれ → harness_root → ホームの順。どこにも無ければ harness_root の下)を stdout (末尾スラッシュなし、常に rc 0)。
# 両方に在る場合はプロジェクト側を返すが、それは二重ロード状態なので
# scripts/scope-check.sh の警告に従って先に片方を消す (予算は 2 か所の合計で効いている)。
harness_rules_dir() {
  local d root p
  d="$(_harness_abs "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}")"
  root="$(harness_root "$d")"
  if [ -n "${HARNESS_RULES_DIR:-}" ]; then
    printf '%s' "$HARNESS_RULES_DIR"
    return 0
  fi
  for p in "$d/.claude/rules" "$root/.claude/rules" "${HOME:+$HOME/.claude/rules}"; do
    [ -n "$p" ] || continue
    if [ -d "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
  printf '%s' "$root/.claude/rules"
}

# harness_open_tasks <list.md> -> 未完了 (完了 / done / ✅ 以外) の行数を stdout
harness_open_tasks() {
  local f="${1:-}" total done_n n
  [ -f "$f" ] || { printf '0'; return 0; }
  # grep -c は 0 件のとき "0" を出しつつ exit 1 を返す。数字以外を捨てて必ず整数にする。
  total="$(grep -c '^|[[:space:]]*[0-9]' "$f" 2>/dev/null | tr -cd '0-9')"
  done_n="$(grep '^|[[:space:]]*[0-9]' "$f" 2>/dev/null | grep -c -e '✅' -e '完了' -e '[Dd]one' | tr -cd '0-9')"
  n=$(( ${total:-0} - ${done_n:-0} ))
  [ "$n" -ge 0 ] 2>/dev/null || n=0
  printf '%s' "$n"
}
