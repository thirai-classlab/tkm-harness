#!/usr/bin/env bash
# PostToolUse(Bash) の hook。コーディネーターの会話にだけ、次の 2 つを足す（どちらか 1 回に JSON は 1 つ。両方に当たれば表のほう）。
#  1. 振り出し（orca orchestration worker-start・orca worktree set --issue・hirai-task / gh-task.sh の assign・start）か
#     完了（hirai-task / gh-task.sh の done・after-merge・gh pr merge）のあと
#     （区切った各部分を語に分け、コマンドの位置の語で決める。引用の中の文・閉じない引用では出ない）: `hirai-task load --cached --changed` の表を、
#     段・担当・順番が前回に出した表から動いたときだけ、systemMessage（人の画面に出る。F7）と additionalContext（AI に入る。F8）の両方に出す。
#     動いていなければ（load が exit 3）1 バイトも出さない。assign・start・done が自分の出力に表を出したあと（前回の控えを書き換えている）も
#     同じ表を重ねない。会話の始まり（session-start.sh）と手で打つ `hirai-task load` は、動いたかを問わず全部出す。
#  2. `orca orchestration check` で担当からの知らせを受けたとき: 「hirai-task load --changed を打つ」の 1 行を additionalContext に足す。
# 止めない: 操作の可否を変えず、常に exit 0。対象外・load の失敗・空・時間切れ（8 秒）は 1 バイトも出さない（_meta.md 条 5 の context を注ぐだけの hook）。
# GitHub を叩かない: 表は控え（--cached）から。各欄は 10,000 字の内に収め、超えたら末尾を切って「（続きは hirai-task load）」の 1 行にする。
# コーディネーターか（親がいない会話か・tasks が github-project か）の判定は `hirai-task is-coordinator` が持つ。担当の会話・判定できない会話・台帳のリポでは出ない。
# 失効: Claude Code が hook の出力を人の画面と AI の両方へ出す口を別に持ち、表を会話の外で見せられるようになったとき。
set -uo pipefail

# 入力は先に読み切る（読まずに終わると、呼ぶ側の書き込みが途中で切れる）。そのあとで安い分かれ道を見る
input="$(cat 2>/dev/null)" || exit 0
case "$input" in *orchestration*|*worktree*|*hirai-task*|*gh-task*|*merge*) ;; *) exit 0 ;; esac   # python も hirai-task も起こさない
command -v python3 >/dev/null 2>&1 || exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= builtin cd -- "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && builtin pwd -P)}"

# 1 行目 = table（振り出し・完了）/ notice（知らせを受けた）/ 0、2 行目 = cwd
hit="$(printf '%s' "$input" | python3 -I "$root/scripts/hirai_hook_kind.py" 2>/dev/null)" || exit 0
kind="${hit%%$'\n'*}"
case "$kind" in table|notice) ;; *) exit 0 ;; esac
cwd="${hit#*$'\n'}"
[ -n "$cwd" ] && [ -d "$cwd" ] && CDPATH= builtin cd -- "$cwd" >/dev/null 2>&1

task="$root/bin/hirai-task"
[ -x "$task" ] || exit 0
"$task" is-coordinator >/dev/null 2>&1 || exit 0
python3 -I -c '
import json, subprocess, sys
kind, task = sys.argv[1], sys.argv[2]
LIMIT, TAIL = 10000, "（続きは hirai-task load）"
def emit(ctx, message=None):
    out = {"systemMessage": message} if message else {}
    out["hookSpecificOutput"] = {"hookEventName": "PostToolUse", "additionalContext": ctx}
    print(json.dumps(out, ensure_ascii=False))
def cut(text):
    return text if len(text) <= LIMIT else text[: LIMIT - len(TAIL) - 1].rstrip() + "\n" + TAIL
if kind == "notice":
    emit("担当からの知らせを受けました。`hirai-task load --changed` を打ち、出力があればそのまま貼ります（段・担当・順番が動いていなければ何も出ません）。")
    sys.exit(0)
try:
    r = subprocess.run([task, "load", "--cached", "--changed"], capture_output=True, text=True, timeout=8)
except Exception:
    sys.exit(0)
table = r.stdout.strip()
if r.returncode != 0 or not table:
    sys.exit(0)
head = "この表は人の画面にも出ています（hook）。同じ表を貼り直さず、必要なら要点だけ述べます。\n"
emit(cut(head + table), cut(table))
' "$kind" "$task" 2>/dev/null || true
exit 0
