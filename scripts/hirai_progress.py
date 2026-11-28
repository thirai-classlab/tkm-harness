#!/usr/bin/env python3
"""
hirai_progress.py — `hirai-task board --progress` が描く、進みの表（担当と「いまやっていること」つき）。

計算は hirai_load.build を使い回す（全体の数・セクション・段・止まりを二重に作らない）。ここが足すのは次の 3 つ。
  1. 担当: `orca worktree list --json` の作業ツリー（表示名・linkedIssue・linkedPR・comment）を第一の元にし、
     worker-list・task-list・inbox で補う。Orca が無い（PATH に無い・exit が 0 でない・JSON が読めない）ときは
     開いている PR の head の branch 名の頭の番号 → issue の Assignees の順で引く
  2. いまやっていること: 作業ツリーの comment が第一。空のときだけ heartbeat の phase・最新の status か
     question の件名・最後の commit・PR と CI から 1 行に組む（引けないものは書かない）
  3. 「これから立てる」: Project で着手可なのに、どの作業ツリー・割り当て・PR にも無い task

Orca と git の呼び出しは runner を差し替えられる（試験は偽の応答で回す）。読み取りのコマンドだけを打つ。
標準ライブラリだけで動く。

失効: タスクの正本を GitHub Projects 以外へ移したとき、または Orca の CLI の JSON の形が変わったとき。
"""
from __future__ import annotations

import datetime
import json
import os
import re
import shutil
import signal
import subprocess
import time

ORCA_TIMEOUT_SECONDS = 20
LOAD_ORCA_SECONDS = 3  # hirai-task load が作業ツリーの一覧を待つ時間（TKS-R6.1）
OWNER_MAX = 30
SUBJECT_MAX = 40
COMMIT_SUBJECT_MAX = 40
NOW_SEPARATOR = ' ／ '
USER_MARKS = ('[User]', '[操作]')
STATE_RANK = {'worktree': 0, 'reported': 1, 'active': 2}
_HEAD_NUMBERS_RE = re.compile(r'^\s*((?:#\d+\s*[・,、]?\s*)+)')
_ISSUE_REF_RE = re.compile(r'#(\d+)')
_TREE_NUMBER_RE = re.compile(r'(?<!\d)(\d{3,6})(?!\d)')
_BRANCH_NUMBER_RE = re.compile(r'^(?:[^/\s]+/)?(\d+)(?!\d)')


def one_line(text) -> str:
    return ' '.join(str(text or '').split())


def clip(text: str, width: int) -> str:
    text = one_line(text)
    return text if len(text) <= width else text[:width - 1] + '…'


# ── Orca・git の呼び出し（読み取りだけ） ─────────────────────────────
def default_runner(argv: list[str]) -> tuple[int, str]:
    """(exit code, 標準出力)。コマンドが無い・時間切れは例外（呼ぶ側が「引けない」として扱う）。"""
    done = subprocess.run(argv, capture_output=True, text=True, timeout=ORCA_TIMEOUT_SECONDS, check=False)
    return done.returncode, done.stdout


def orca_json(args: list[str], runner=default_runner) -> dict | None:
    """`orca <args> --json` の result。引けない（無い・exit が 0 でない・JSON が読めない・ok でない）ときは None。"""
    try:
        rc, out = runner(['orca', *args, '--json'])
        if rc != 0:
            return None
        payload = json.loads(out)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if not isinstance(payload, dict) or payload.get('ok') is False or not isinstance(payload.get('result'), dict):
        return None
    return payload['result']


def orca_available() -> bool:
    return shutil.which('orca') is not None


# ── 番号と名前 ────────────────────────────────────────────────
def first_line(text) -> str:
    for line in str(text or '').splitlines():
        if line.strip():
            return line.strip()
    return ''


def head_numbers(text: str) -> list[int]:
    """題の頭の `#<番号>`（`#2035・#2036 …` は 2 つ）。"""
    match = _HEAD_NUMBERS_RE.match(text or '')
    return [int(n) for n in _ISSUE_REF_RE.findall(match.group(1))] if match else []


def linked_issue_numbers(value) -> list[int]:
    if isinstance(value, dict):
        value = value.get('number')
    if isinstance(value, bool):
        return []
    if isinstance(value, int) and value > 0:
        return [value]
    if isinstance(value, str) and value.strip().isdigit() and int(value) > 0:
        return [int(value)]
    return []


def owner_name(title: str, numbers: list[int]) -> str:
    """題から番号と飾りを外した 30 字まで。空になったら番号の並び。"""
    plain = re.sub(r'PR\s*#\d+', ' ', title or '')
    plain = re.sub(r'（\s*）', ' ', _ISSUE_REF_RE.sub(' ', plain))
    plain = re.sub(r'指示書\s*[:：]', ' ', plain)
    plain = re.sub(r'^[\s・:：、,\-—#]+', '', one_line(plain))
    plain = one_line(plain)
    return clip(plain, OWNER_MAX) if plain else '・'.join(f'#{n}' for n in numbers)


def _json_payload(raw) -> dict:
    if isinstance(raw, dict):
        return raw
    try:
        value = json.loads(raw) if isinstance(raw, str) and raw.strip() else {}
    except ValueError:
        return {}
    return value if isinstance(value, dict) else {}


def _path_of_worker(worker: dict) -> str:
    worktree_id = ((worker.get('resource') or {}).get('worktreeId')) or ''
    return worktree_id.split('::', 1)[1] if '::' in worktree_id else ''


def clock(iso_or_epoch, tz=None) -> str:
    """HH:MM（tz は試験が固定する。既定は手元の時刻）。読めなければ空。"""
    try:
        if isinstance(iso_or_epoch, (int, float)):
            moment = datetime.datetime.fromtimestamp(float(iso_or_epoch), tz)
        else:
            moment = datetime.datetime.fromisoformat(str(iso_or_epoch).replace('Z', '+00:00')).astimezone(tz)
    except (ValueError, OverflowError, OSError):
        return ''
    return moment.strftime('%H:%M')


# ── 作業ツリーの束ね ──────────────────────────────────────────
def _messages_by_dispatch(inbox: dict, workers: dict) -> dict:
    """{dispatchId: {'phase', 'phase_at', 'say', 'say_at', 'done'}}（sequence の最大が最新）。"""
    terminal_to_dispatch = {w.get('agentTerminalHandle'): w.get('dispatchId') for w in workers.values() if w.get('agentTerminalHandle')}
    out: dict[str, dict] = {}
    rows = [m for m in (inbox.get('messages') or []) if isinstance(m, dict)]
    for message in sorted(rows, key=lambda m: m.get('sequence') or 0):
        payload = _json_payload(message.get('payload'))
        dispatch = payload.get('dispatchId') or terminal_to_dispatch.get(message.get('from_handle'))
        if not dispatch:
            continue
        slot = out.setdefault(dispatch, {})
        kind, at = message.get('type'), message.get('created_at')
        if kind == 'heartbeat' and payload.get('phase'):
            slot['phase'], slot['phase_at'] = one_line(payload['phase']), at
        elif kind in ('status', 'question') and one_line(message.get('subject')):
            slot['say'] = ('質問: ' if kind == 'question' else '') + clip(message['subject'], SUBJECT_MAX)
            slot['say_at'] = at
        elif kind == 'worker_done':
            slot['done'] = True
    return out


def _worker_state(worker: dict | None, spoke: dict) -> str:
    if worker is None:
        return 'worktree'
    if worker.get('dispatchStatus') == 'dispatched':
        return 'active'
    if worker.get('dispatchStatus') == 'completed' or spoke.get('done'):
        return 'reported'
    return 'worktree'


def _commit_part(path: str, git_runner, tz) -> str:
    try:
        rc, out = git_runner(['git', '-C', path, 'log', '-1', '--format=%ct%x09%s'])
    except (OSError, subprocess.SubprocessError):
        return ''
    stamp, _, subject = (out or '').strip().partition('\t')
    if rc != 0 or not stamp.isdigit():
        return ''
    when = clock(int(stamp), tz)
    return f"最後の commit {when} {clip(subject, COMMIT_SUBJECT_MAX)}".strip() if when else ''


def live_trees(trees: list, repo: str = '') -> list[tuple[int, dict]]:
    """作業ツリーの行のうち、担当を持ちうるもの（main・archived・path 無し・別のリポを除く）を (一覧での位置, 行) で返す。
    collect（board --progress）と worktree_assign（load）が同じ読み方をする 1 本。"""
    out = []
    for index, tree in enumerate(t for t in trees if isinstance(t, dict)):
        if tree.get('isMainWorktree') or tree.get('isArchived') or not (tree.get('path') or ''):
            continue
        project = str(tree.get('projectId') or '').lower()
        if repo and project and project != f'github:{repo}'.lower():
            continue
        out.append((index, tree))
    return out


def limited_runner(seconds: float):
    """seconds 秒で返らなければ process group ごと止める runner（孫が出力の口を持ち続けて待たされない）。
    時間切れは TimeoutExpired（orca_json が「引けない」として扱う）。"""
    def run(argv: list[str]) -> tuple[int, str]:
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, start_new_session=True)
        try:
            out, _ = proc.communicate(timeout=seconds)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                pass
            proc.communicate()
            raise
        return proc.returncode, out
    return run


_LISTING_MEMO: dict = {'at': 0.0, 'listing': None}
LISTING_MEMO_SECONDS = 10  # worktree_assign が引いた一覧を、worktree_numbers が引き直さずに使える長さ


def worktree_assign(repo: str = '', runner=None, seconds: float = LOAD_ORCA_SECONDS) -> dict:
    """load の担当（TKS-R6.1）: `orca worktree list --json` だけを seconds 秒で引き、issue を紐づけた作業ツリーの
    表示名を担当にする。{番号: {'owner': 表示名, 'order': None}}。引けない（orca が無い・exit が 0 でない・JSON が読めない・
    時間切れ）ときは空。GitHub には出ない。"""
    listing = orca_json(['worktree', 'list'], runner or limited_runner(seconds))
    _LISTING_MEMO.update(at=time.monotonic(), listing=listing)
    if listing is None or not isinstance(listing.get('worktrees'), list):
        return {}
    out: dict[int, dict] = {}
    for _index, tree in live_trees(listing['worktrees'], repo):
        name = one_line(tree.get('displayName')) or os.path.basename(str(tree.get('path') or '').rstrip('/'))
        for number in linked_issue_numbers(tree.get('linkedIssue')):
            out.setdefault(number, {'owner': name, 'order': None})
    return out


def worktree_numbers(repo: str = '', runner=None, git_runner=None, seconds: float = LOAD_ORCA_SECONDS) -> set[int]:
    """作業ツリー（Orca の一覧と `git worktree list`）の path・branch・表示名・linkedIssue に現れる番号。
    担当の居ない行から「作業ツリーの担当が実際に動いている task」を外すのに使う。読み取りだけで、GitHub には出ない。
    引けないもの（orca が無い・git が失敗・時間切れ）は黙って飛ばす。"""
    numbers: set[int] = set()
    memo_fresh = _LISTING_MEMO['listing'] is not None and time.monotonic() - _LISTING_MEMO['at'] < LISTING_MEMO_SECONDS
    if runner is None and memo_fresh:
        listing = _LISTING_MEMO['listing']
    else:
        listing = orca_json(['worktree', 'list'], runner or limited_runner(seconds))
    if listing is not None and isinstance(listing.get('worktrees'), list):
        for _index, tree in live_trees(listing['worktrees'], repo):
            name = str(tree.get('displayName') or '')
            numbers |= {int(n) for n in _TREE_NUMBER_RE.findall(f"{tree.get('path') or ''} {tree.get('branch') or ''} {name}")}
            numbers |= set(linked_issue_numbers(tree.get('linkedIssue'))) | set(head_numbers(name))
    try:
        rc, out = (git_runner or limited_runner(seconds))(['git', 'worktree', 'list', '--porcelain'])
    except (OSError, subprocess.SubprocessError):
        return numbers
    if rc != 0:
        return numbers
    blocks = [b for b in (out or '').split('\n\n') if b.strip()][1:]  # 先頭は本体の checkout（担当ではない）
    for block in blocks:
        for line in block.splitlines():
            if line.startswith(('worktree ', 'branch ')):
                numbers |= {int(n) for n in _TREE_NUMBER_RE.findall(line.split(' ', 1)[1])}
    return numbers


def merge_assign(orca: dict, saved: dict, known: set | None = None) -> dict:
    """Orca の担当に、手元の控え（hirai-task assign）を補う。同じ番号は担当が Orca・順番が控え。
    Orca だけの番号は known（板にある issue の番号）に載るものだけ（板に無い issue の行を出さない）。"""
    merged = {n: dict(v) for n, v in saved.items()}
    for number, entry in orca.items():
        if number in merged or known is None or number in known:
            merged[number] = {'owner': entry['owner'], 'order': (saved.get(number) or {}).get('order')}
    return merged


def collect(repo: str = '', runner=default_runner, git_runner=default_runner, tz=None) -> dict | None:
    """Orca の読み取りだけで担当を組む。作業ツリーの一覧が引けなければ None（呼ぶ側は PR・Assignees の道へ落ちる）。
    戻り: {'assignments': [...], 'assign': {番号: {owner, order}}, 'info': {番号: 担当}, 'tree_numbers': set}"""
    listing = orca_json(['worktree', 'list'], runner)
    if listing is None or not isinstance(listing.get('worktrees'), list):
        return None
    worker_rows = (orca_json(['orchestration', 'worker-list'], runner) or {}).get('workers') or []
    task_rows = (orca_json(['orchestration', 'task-list'], runner) or {}).get('tasks') or []
    inbox = orca_json(['orchestration', 'inbox'], runner) or {}
    tasks = {t.get('id'): t for t in task_rows if isinstance(t, dict)}
    workers_by_path: dict[str, dict] = {}
    for worker in (w for w in worker_rows if isinstance(w, dict)):  # 新しい順。生きている担当を先に取る
        path = _path_of_worker(worker)
        if not path:
            continue
        prev = workers_by_path.get(path)
        if prev is None or (prev.get('dispatchStatus') != 'dispatched' and worker.get('dispatchStatus') == 'dispatched'):
            workers_by_path[path] = worker
    spoke = _messages_by_dispatch(inbox, {w.get('dispatchId'): w for w in workers_by_path.values()})
    assignments, tree_numbers = [], set()
    for index, tree in live_trees(listing['worktrees'], repo):
        path = tree.get('path') or ''
        tree_numbers |= {int(n) for n in _TREE_NUMBER_RE.findall(f"{path} {tree.get('branch') or ''} {tree.get('displayName') or ''}")}
        worker = workers_by_path.get(path)
        task = tasks.get((worker or {}).get('taskId')) or {}
        name = str(tree.get('displayName') or '')
        numbers = linked_issue_numbers(tree.get('linkedIssue')) or head_numbers(name)
        title = name
        if not numbers:  # 表示名にも linkedIssue にも番号が無いときだけ、割り当ての題（無ければ spec の 1 行目）
            for candidate in (task.get('display_name'), task.get('task_title'), first_line(task.get('spec'))):
                if one_line(candidate) and _ISSUE_REF_RE.search(str(candidate)):
                    numbers, title = [int(n) for n in _ISSUE_REF_RE.findall(str(candidate))], str(candidate)
                    break
        if not numbers:
            continue
        said = spoke.get((worker or {}).get('dispatchId'), {})
        comment = one_line(tree.get('comment'))
        live: list[str] = []
        if not comment:
            if said.get('phase'):
                when = clock(said.get('phase_at'), tz)
                live.append(f"{said['phase']}" + (f'（{when} 時点）' if when else ''))
            if said.get('say'):
                live.append(said['say'])
            commit = _commit_part(path, git_runner, tz)
            if commit:
                live.append(commit)
        pr = linked_issue_numbers(tree.get('linkedPR'))
        assignments.append({'owner': owner_name(title, numbers), 'numbers': sorted(set(numbers)), 'path': path,
                            'state': _worker_state(worker, said), 'comment': comment, 'live': live,
                            'pr': pr[0] if pr else None, 'order': index})
    assign, info = {}, {}
    for a in sorted(assignments, key=lambda a: (STATE_RANK[a['state']], -a['order'])):  # 強い状態が後から上書きする
        for n in a['numbers']:
            assign[n], info[n] = {'owner': a['owner'], 'order': a['order']}, a
    return {'assignments': assignments, 'assign': assign, 'info': info, 'tree_numbers': tree_numbers}


# ── Orca が無いときの落ちる道 ─────────────────────────────────
def fallback_assign(view: dict, prs: dict) -> dict:
    """開いている PR の head の branch 名の頭の番号 → issue の Assignees の順。{番号: {owner, order}}"""
    tasks = {i['number']: i for i in view['issues'] if (i.get('kind') or '') not in ('wave', 'feature', '設計メモ')}
    assign: dict[int, dict] = {}
    for pr in prs.get('open', []):
        match = _BRANCH_NUMBER_RE.match(pr.get('head') or '')
        if match and int(match.group(1)) in tasks:
            assign.setdefault(int(match.group(1)), {'owner': clip(pr['head'], OWNER_MAX), 'order': None})
    for number, logins in (prs.get('assignees') or {}).items():
        n = int(number)
        if n in tasks and n not in assign and logins:
            assign[n] = {'owner': '・'.join(logins), 'order': None}
    return assign


# ── 表の材料 ──────────────────────────────────────────────────
def now_text(info: dict | None, entry: dict) -> str:
    """その task の「いまやっていること」。comment が第一、無ければ組んだもの。引けないものは書かない。"""
    if entry['pct'] == 100:
        return '完了'
    parts: list[str] = []
    if info and info['state'] == 'reported':
        parts.append('完了報告済み')
    if info and info['comment']:
        parts.append(info['comment'])
    else:
        parts += (info or {}).get('live', [])
        if entry.get('note', '').startswith('PR'):
            parts.append(entry['note'])
        elif entry.get('stuck'):
            parts.append(entry['stuck'])
    return '、'.join(parts)


def upcoming_rows(view: dict, prs: dict, taken: set[int], tree_numbers: set[int]) -> list[dict]:
    """Project で着手可（ready の判定を通った task）なのに、割り当て・作業ツリー・開いている PR のどれにも無いもの。"""
    in_pr = {int(n) for pr in prs.get('open', []) for n in pr.get('closes') or []}
    by_number = {i['number']: i for i in view['issues']}
    rows = []
    for number in sorted(view.get('ready') or []):
        issue = by_number.get(number) or {}
        if number in taken or number in tree_numbers or number in in_pr or issue.get('state') == 'CLOSED':
            continue
        if any(mark in (issue.get('title') or '') for mark in USER_MARKS):
            continue
        rows.append({'number': number, 'title': one_line(issue.get('title'))})
    return rows


def build(load, view: dict, prs: dict, settings: dict, orca: dict | None) -> dict:
    """進みの表の材料（JSON にできる形）。orca が None なら PR・Assignees の道。"""
    assign = orca['assign'] if orca else fallback_assign(view, prs)
    info = orca['info'] if orca else {}
    tree_numbers = (orca or {}).get('tree_numbers', set())
    model = load.build(view, prs, assign, settings, tree_numbers)
    rows = []
    for person in model['people']:
        for entry in person['tasks']:
            entry['now'] = now_text(info.get(entry['number']), entry)
        for run in load.group_rows(person['tasks']):
            numbers = [n for g in run for n in g['numbers']]
            nows = []
            for entry in (e for e in person['tasks'] if e['number'] in numbers and e['pct'] != 100):
                if entry['now'] and entry['now'] not in nows:
                    nows.append(entry['now'])
            rows.append({'owner': person['owner'], 'section': run[0]['section'], 'groups': [
                {'numbers': g['numbers'], 'pr': g['pr'], 'pct': g['pct']} for g in run], 'now': NOW_SEPARATOR.join(nows)})
    taken = set(assign) | {n for pr in prs.get('open', []) for n in pr.get('closes') or []}
    model['rows'] = rows
    model['running'] = load.running_rows(model)  # now を足したあとで組み直す
    model['upcoming'] = upcoming_rows(view, prs, taken, tree_numbers)
    model['source'] = 'orca' if orca else 'fallback'
    return model


def render(load, model: dict, age_minutes: int | None = None) -> str:
    """load と同じ平文の 3 段。「いま動いている」の行に いまやっていること を添え、あとに「これから立てる」と
    担当の引き方の断りを足す。"""
    extra = []
    if model['upcoming']:
        extra.append('これから立てる（着手可で、作業ツリーも割り当ても無いもの）: ' + '、'.join(
            f"#{u['number']} {load.clip_width(u['title'], 30)}" for u in model['upcoming']))
    if model['source'] == 'fallback':
        extra.append('担当は Orca から引けなかったので、PR の branch 名と Assignees から出しています。')
    return load.render(model, age_minutes, extra)
