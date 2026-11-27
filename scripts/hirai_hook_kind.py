#!/usr/bin/env python3
"""PostToolUse(Bash) の入力（標準入力の JSON）から、進みの表を出す操作か（hooks/coordinator-load.sh が呼ぶ）。
標準出力は 2 行: 1 行目 = table（振り出し・完了）/ notice（担当からの知らせを受けた）/ 0、2 行目 = cwd。
heredoc の本文を除き、区切った各部分を語に分け、コマンドの位置の語で決める（代入・制御の語・env・timeout・time・nice・command・exec・sudo は引数ごと飛ばし、bash -c の文はもう一度判定する）。
引用の中の文（指示文・commit の文・grep の引数）と、閉じない引用では table にしない。"""
import json
import os
import re
import shlex
import sys

SUBS = ("assign", "start", "done", "after-merge")
SQ, DQ = chr(39), chr(34)


def segments(cmd):
    # ; && || | & 改行 ( ) で区切る（引用の中は区切らない）。引用が閉じていなければ None
    quote, cur, segs, i = "", [], [], 0
    while i < len(cmd):
        c = cmd[i]
        if quote:
            cur.append(c)
            if c == "\\" and quote == DQ and i + 1 < len(cmd):
                i += 1
                cur.append(cmd[i])
            elif c == quote:
                quote = ""
        elif c == "\\" and i + 1 < len(cmd):
            cur.append(c)
            i += 1
            cur.append(cmd[i])
        elif c in (SQ, DQ):
            quote = c
            cur.append(c)
        elif c in ";&|()\n":
            segs.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    if quote:
        return None
    segs.append("".join(cur))
    return segs


HEREDOC = re.compile(r"<<-?[ \t]*(?:'([^']*)'|\"([^\"]*)\"|\\?([A-Za-z0-9_]+))")
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
# 制御の語: 次の語をコマンドの位置として見る
CTRL = ("for", "while", "until", "if", "then", "else", "elif", "do", "done", "fi", "{", "}", "!", "case", "esac", "select")
SHELLS = ("bash", "sh", "zsh", "dash")
MAX_DEPTH = 3


def strip_heredocs(cmd):
    # heredoc（<<EOF・<<'EOF'・<<-EOF）の本文を、終わりの印の行まで取り除く。本文の ' や hirai-task start の行を見ないため
    out, i, quote, pending, n = [], 0, "", [], len(cmd)
    while i < n:
        c = cmd[i]
        if quote:
            out.append(c)
            if c == "\\" and quote == DQ and i + 1 < n:
                i += 1
                out.append(cmd[i])
            elif c == quote:
                quote = ""
        elif c == "\\" and i + 1 < n:
            out.append(c)
            i += 1
            out.append(cmd[i])
        elif c in (SQ, DQ):
            quote = c
            out.append(c)
        elif cmd.startswith("<<", i) and not cmd.startswith("<<<", i) and HEREDOC.match(cmd, i):
            m = HEREDOC.match(cmd, i)
            tag = next(g for g in m.groups() if g is not None)
            pending.append((tag, cmd.startswith("<<-", i)))
            out.append(m.group(0))
            i = m.end()
            continue
        elif c == "\n" and pending:
            out.append(c)
            i += 1
            for tag, dash in pending:
                while i < n:
                    j = cmd.find("\n", i)
                    j = n if j < 0 else j
                    line = cmd[i:j]
                    i = j + 1
                    if (line.lstrip("\t") if dash else line) == tag:
                        break
            pending = []
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def skip_flags(r, with_value=()):
    # 先頭の -x を飛ばす。with_value の flag は次の語も飛ばす
    while r and r[0].startswith("-") and r[0] != "-":
        r = r[2:] if r[0] in with_value else r[1:]
    return r


def strip_prefix(w, depth):
    # 前置き（代入・制御の語・env・timeout・time・nice・command・exec・sudo・nohup）を引数ごと飛ばす。
    # bash -c '<文>' は文をもう一度判定にかけ、その真偽（bool）を返す。残った語の並び（list）を返すこともある
    while w:
        base = os.path.basename(w[0])
        if ASSIGN.match(w[0]) or w[0] in CTRL:
            w = w[1:]
        elif base == "env":
            w = skip_flags(w[1:], ("-u", "--unset", "-C", "--chdir", "-S"))
        elif base in SHELLS:
            r = w[1:]
            while r and r[0].startswith("-") and r[0] != "-":
                if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", r[0]) and len(r) > 1:
                    return starts(r[1], depth + 1)
                r = r[1:]
            w = r
        elif base == "timeout":
            r = skip_flags(w[1:], ("-s", "--signal", "-k", "--kill-after"))
            w = r[1:] if r and re.fullmatch(r"[0-9.]+[smhd]?", r[0]) else r
        elif base == "nice":
            w = skip_flags(w[1:], ("-n", "--adjustment"))
        elif base == "command":
            if any(a.startswith("-") and ("v" in a or "V" in a) for a in w[1:2]):
                return False
            w = skip_flags(w[1:])
        elif base == "exec":
            w = skip_flags(w[1:], ("-a",))
        elif base == "sudo":
            w = skip_flags(w[1:], ("-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U"))
        elif base in ("time", "nohup"):
            w = skip_flags(w[1:])
        else:
            break
    return w


def is_start(seg, depth=0):
    # コマンドの位置の語だけで決める。引用の中の文は語の 1 つになるので当たらない
    try:
        w = shlex.split(seg)
    except ValueError:
        return False
    w = strip_prefix(w, depth)
    if isinstance(w, bool):
        return w
    if not w:
        return False
    base, rest = os.path.basename(w[0]), w[1:]
    if "--help" in rest or "-h" in rest:
        return False
    if base in ("hirai-task", "gh-task.sh"):
        for a in rest:
            if a.startswith("-"):
                continue
            return a in SUBS
        return False
    if base == "gh":
        return rest[:2] == ["pr", "merge"]
    if base == "orca":
        if rest[:2] == ["orchestration", "worker-start"]:
            return True
        return rest[:2] == ["worktree", "set"] and any(a == "--issue" or a.startswith("--issue=") for a in rest)
    return False


def starts(cmd, depth=0):
    if depth > MAX_DEPTH:
        return False
    return any(is_start(seg, depth) for seg in (segments(strip_heredocs(cmd)) or []))


try:
    d = json.load(sys.stdin)
    cmd = (d.get("tool_input") or {}).get("command") or ""
    kind = "0"
    if d.get("tool_name") == "Bash":
        if starts(cmd):
            kind = "table"
        if kind == "0":
            out = json.dumps(d.get("tool_response"), ensure_ascii=False)
            if re.search(r"(^|[;&|\s])orca\s+orchestration\s+check(\s|$)", cmd) and (re.search(r"msg_[0-9a-z]", out) or re.search(r"\s--ack\b", cmd)):
                kind = "notice"
    print(kind)
    print(d.get("cwd") or "")
except Exception:
    print("0")
