#!/usr/bin/env python3
"""PostToolUse(Bash) の入力（標準入力の JSON）から、進みの表を出す操作か（hooks/coordinator-load.sh が呼ぶ）。
標準出力は 2 行: 1 行目 = table（振り出し・完了）/ notice（担当からの知らせを受けた）/ 0、2 行目 = cwd。
区切った各部分を語に分け、コマンドの位置の語（VAR=x の代入・env・bash・sh の次の語も見る）で決める。
引用の中の文（指示文・commit の文・grep の引数）と、閉じない引用では table にしない。"""
import json
import os
import re
import shlex
import sys

SUBS = ("assign", "start", "done", "after-merge")
WRAP = ("env", "bash", "sh", "command", "exec", "nohup", "time")
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


def is_start(seg):
    # コマンドの位置の語（VAR=x の代入・env・bash・sh の次の語も見る）だけで決める。引用の中の文は語の 1 つになるので当たらない
    try:
        w = shlex.split(seg)
    except ValueError:
        return False
    while w:
        if re.match(r"[A-Za-z_][A-Za-z0-9_]*=", w[0]):
            w = w[1:]
        elif os.path.basename(w[0]) in WRAP:
            w = w[1:]
            while w and w[0].startswith("-"):
                w = w[1:]
        else:
            break
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


try:
    d = json.load(sys.stdin)
    cmd = (d.get("tool_input") or {}).get("command") or ""
    kind = "0"
    if d.get("tool_name") == "Bash":
        if any(is_start(seg) for seg in (segments(cmd) or [])):
            kind = "table"
        if kind == "0":
            out = json.dumps(d.get("tool_response"), ensure_ascii=False)
            if re.search(r"(^|[;&|\s])orca\s+orchestration\s+check(\s|$)", cmd) and (re.search(r"msg_[0-9a-z]", out) or re.search(r"\s--ack\b", cmd)):
                kind = "notice"
    print(kind)
    print(d.get("cwd") or "")
except Exception:
    print("0")
