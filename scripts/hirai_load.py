#!/usr/bin/env python3
"""
hirai_load.py — `hirai-task load` が描く、全体の進みと、振っているタスクの順番・進捗率。

入口は bin/hirai-task の load（gh で取り、設定と割り振りを読んで渡す）。ここは渡された形を描くだけで、
ネットワークにも gh にも出ない。標準ライブラリだけで動く。

進捗率は担当の申告でなく、PR と issue の実物で決める:
  0 着手前 ／ 20 進行中（PR なし） ／ 50 draft の PR ／ 60 ready で CI が走っているか赤 ／ 70 ready で CI が緑
  90 merge 済みで issue が開いている ／ 100 issue が閉じた

渡される形:
  view: bin/hirai-task の board_view（issues・open_prs など。木の組み方は hirai_board.build と同じ）
  prs: {'open': [PR], 'merged': [PR], 'me': 自分の login, 'assignees': {番号: [login]}}（PR は bin の fetch_load_prs の形）
  trees: {'numbers': 作業ツリー（Orca・git worktree）の名前に現れる番号（担当の居ない行から外す）, 'names': {番号: 作業ツリーの名前}}（無ければ空）
  assign: {番号: {'owner': 自分の作業のセッションの名前, 'order': 順（数値か None）}}（手元の控え）
  settings: {'deadline_label': …, 'deadline_date': …, 'deadline_open': 件数か None, 'mainline': …, 'mainline_label': …,
             'people': {GitHub の名前（小文字）: 表示名}}
            （無い設定は '' か {} で、その行・印を出さない）
  view の issue の 'assignees': [login]（板の控えが持つ。無い控え = 古い控えは、担当の列を「—」で出して取り直しを促す）

失効: タスクの正本を GitHub Projects 以外へ移したとき。
"""
from __future__ import annotations

import re
import unicodedata

import hirai_board

NO_OWNER_STATUSES = ('進行中', 'レビュー中')
HELD_STATUS = '保留'
CLOSED_SHOWN = 3  # 担当の行に出す、閉じた task の数（割り振りの順番の前のものから畳む）
TITLE_WIDTH = 34  # 次のタスクの題の幅（全角 2・半角 1）
NAME_WIDTH = 30  # セクション名の幅
FEATURE_TITLE_WIDTH = 22
TASKS_WIDTH = 72
OWNER_WIDTH = 30
NOW_WIDTH = 60
TURN_MAX = 3  # あなたの番の 判断 に番号を並べる数（残りは「ほか N」）
HUMAN_MARKS = ('[User]', '[操作]')  # 題にこの印がある task は人の作業
NO_ASSIGNEE = '—'  # 担当者のいない行の列
PEOPLE_TITLE_WIDTH = 40  # 人ごとの段の題の幅
PEOPLE_SHOWN = 3  # 人ごとの段で、状態ごとに題つきで出す件数（超えたら番号だけ先頭 3 件と「ほか N」）
# 人ごとの段の状態の並び（担当者のいる行）と、担当なしの行の並び
STATE_ORDER = ('進行中', 'レビュー中', '止まり', '判断待ち', '人の作業', '着手可', 'ほか')
REMAINING_ORDER = ('進行中', 'レビュー中', '着手可', '判断待ち', '承認待ち', '依存待ち', '保留', '人の作業', 'ほか')  # 残りの内訳の並び
UNASSIGNED_ORDER = ('着手可', '判断待ち', '人の作業', '進行中', 'レビュー中', '止まり', 'ほか')
MINE_AI, MINE_HUMAN, MINE_ORPHAN = 'AI の担当', '人の作業', '担当の居ないもの'  # 自分のアカウントの行の区分（残りは状態ごと）
MINE_ORDER = (MINE_AI, MINE_HUMAN, MINE_ORPHAN, '着手可', '判断待ち', '承認待ち', '依存待ち', '保留', 'ほか')
STALE_NOTE = '控えに担当者が無い。取り直す: hirai-task load'
STATUS_DECISION = '判断待ち'
STATUS_PENDING = '承認待ち'
# 段（率）を、画面に出す語にする。止まり（CI 赤・衝突）は率に関わらずその語を出す
STAGE_WORDS = {0: '未着手', 20: '着手', 50: 'draft', 60: 'ready', 70: 'CI 緑', 90: 'merge 済み', 100: '完了'}
DONE_STATUS = '完了'
# feature の段（PR が無いとき）: 承認待ち・着手可 → 0、進行中 → 20、レビュー中 → 60、完了 → 100
FEATURE_STATUS_PCT = {'承認待ち': 0, '着手可': 0, '進行中': 20, 'レビュー中': 60, DONE_STATUS: 100}
CI_GREEN = ('SUCCESS',)
CI_RED = ('FAILURE', 'ERROR')


def one_line(text) -> str:
    return ' '.join(str(text or '').split())


def plain(text) -> str:
    """画面に出す字（改行・制御文字を空白に畳む。端末の制御列を通さない）。"""
    return one_line(''.join(c if c.isprintable() else ' ' for c in str(text or '')))


def parse_people(text) -> dict:
    """設定 TKM_HARNESS_PEOPLE（`GitHub の名前=表示名,…`）を {小文字の名前: 表示名} にする。形の違う項（= が無い・片方が空）は読み飛ばす。"""
    out = {}
    for part in str(text or '').split(','):
        login, sep, name = part.partition('=')
        login, name = login.strip(), name.strip()
        if sep and login and name:
            out[login.casefold()] = name
    return out


def disp_width(text) -> int:
    """端末での幅。全角（W・F）は 2、結合文字は 0、それ以外は 1。"""
    width = 0
    for c in str(text):
        if unicodedata.combining(c):
            continue
        width += 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1
    return width


def pad(text, width: int) -> str:
    """幅 width まで右に空白を足す（はみ出しは切らない）。"""
    return str(text) + ' ' * max(0, width - disp_width(text))


def clip_width(text, width: int) -> str:
    """幅 width に収める。超えるときは幅 width - 1 までで切って「…」を付ける。"""
    text = plain(text)
    if disp_width(text) <= width:
        return text
    out, used = '', 0
    for c in text:
        w = disp_width(c)
        if used + w > width - 1:
            break
        out, used = out + c, used + w
    return out + '…'


def ci_state(pr: dict) -> str:
    """PR の CI の状態（緑・赤・実行中・検査なし）。検査の無いリポは 検査なし（70 に上げない）。"""
    checks = (pr.get('checks') or '').upper()
    if checks in CI_GREEN:
        return '緑'
    if checks in CI_RED:
        return '赤'
    return '実行中' if checks else '検査なし'


def stage_of(number: int, ctx: dict) -> tuple[int, str, str]:
    """(率, 注, 止まりの印)。控えに無い（Project に載っていない・新しい）issue は 0% で、完了に数えない。
    止まりの印は、止まっている理由（CI 赤・衝突）。無ければ空。"""
    task = ctx['tasks'].get(number)
    if task is None:
        return 0, '控えに無い（新しい）', ''
    if task.get('state') == 'CLOSED':
        return 100, '完了', ''
    prs = ctx['prs_of'].get(number, [])
    if prs:
        best = max(prs, key=lambda p: (not p['draft'], p['number']))
        stuck = '衝突' if best.get('conflict') else ''
        tail = f'・{stuck}' if stuck else ''
        if best['draft']:
            return 50, f"PR #{best['number']} draft{tail}", stuck
        ci = ci_state(best)
        if ci == '赤':
            stuck = 'CI 赤' + ('・衝突' if stuck else '')
        return (70 if ci == '緑' else 60), f"PR #{best['number']} ready・CI {ci}{tail}", stuck
    if number in ctx['merged_of']:
        nums = '・'.join(f'#{n}' for n in ctx['merged_of'][number])
        return 90, f'PR {nums} merge 済み（issue が開いている）', ''
    status = task.get('status') or ''
    if task.get('kind') == 'feature':  # feature は PR が無ければ Status で決める（TKS-R6.2）
        return FEATURE_STATUS_PCT.get(status, 0), (f'Status {status}' if status else 'Status 未設定'), ''
    if status == DONE_STATUS:
        return 90, 'Status 完了（issue が開いている）', ''
    if status in NO_OWNER_STATUSES:
        return 20, f'{status}・PR なし', ''
    return 0, status or 'Status 未設定', ''


def section_name(model: dict, number: int) -> str:
    wave, _feat = hirai_board.locate(model, number)
    title = (model['by_number'].get(wave) or {}).get('title') if wave else ''
    return re.sub(r'^\d+\.\s+', '', one_line(title)) or '—'


_SECTION_RE = re.compile(r'^(\d+(?:\.\d+)*)\.?\s+(.+)$')


def section_parts(wave: dict) -> tuple[str, str]:
    """(番号, 名前)。題が「2. 開発環境」「2.5 設計」の形なら番号を分け、そうでなければ番号は空。"""
    title = one_line(wave.get('title'))
    match = _SECTION_RE.match(title)
    return (match.group(1), match.group(2)) if match else ('', title or '—')


def strip_marks(title) -> str:
    """題の [User]・[操作] の印を外す（「［人］」の語で足りるので、幅を使わない）。"""
    text = str(title or '')
    for mark in HUMAN_MARKS:
        text = text.replace(mark, ' ')
    return plain(text)


def is_human(task: dict) -> bool:
    return any(mark in (task.get('title') or '') for mark in HUMAN_MARKS)


def pick_next(tasks: list) -> dict | None:
    """セクションの次のタスク: 着手順の小さい順（着手順の無い task は後ろ）→ 番号の若い順。ready の並び
    （bin/hirai-task の ready_sort_key。同じ wave の中では wave の位置が同じなので 着手順 → 番号）と同じ。
    保留は後回しにし、残りが保留だけのときだけ保留を出す。"""
    def key(t: dict):
        order = t.get('order')
        return (order is None, order if order is not None else 0.0, t['number'])
    live = [t for t in tasks if t.get('status') != HELD_STATUS]
    pool = live or list(tasks)
    return min(pool, key=key) if pool else None


def turn_tag(task: dict, not_ready: dict) -> str:
    """その task が今だれの番か（進行中・レビュー中・着手可・人・判断・承認待ち・依存待ち・保留。ほかの Status はその語）。"""
    status = task.get('status') or ''
    if status == HELD_STATUS:
        return '保留'
    if status == STATUS_DECISION:
        return '判断'
    if is_human(task):
        return '人'
    if status == '着手可':
        return '依存待ち' if task['number'] in not_ready else '着手可'
    return status or '未設定'


def _pr_index(prs: list, repo: str) -> dict:
    out: dict[int, list] = {}
    for pr in prs:
        for n in pr.get('closes') or []:
            out.setdefault(int(n), []).append(pr)
    return out


def _stage_and_stuck(n: int, ctx: dict) -> tuple:
    pct, _note, stuck = stage_of(n, ctx)
    return pct, stuck


def stage_word(pct: int, stuck: str) -> str:
    return stuck or STAGE_WORDS.get(pct, f'{pct}%')


_NUMBER_PREFIX_RE = re.compile(r'^\d+(?:\.\d+)*\.?\s*')
_TRAILING_PAREN_RE = re.compile(r'\s*[（(]([^（）()]*)[）)]\s*$')


def strip_section_suffix(title: str, wave_title: str) -> str:
    """feature の題の末尾の括弧が、親のセクション名（番号つきでも）と同じなら外す（「堅牢化（13 本番環境の構築）」→「堅牢化」）。"""
    match = _TRAILING_PAREN_RE.search(title)
    if not match:
        return title
    bare = lambda x: _NUMBER_PREFIX_RE.sub('', one_line(x))
    return title[:match.start()] if bare(match.group(1)) and bare(match.group(1)) == bare(wave_title) else title


def _ticket(model: dict, n: int) -> dict:
    """行に付ける feature の情報（親の feature が分からない task は番号なし）。"""
    wave, feat = hirai_board.locate(model, n)
    title = one_line((model['by_number'].get(feat) or {}).get('title')) if feat else ''
    return {'feature': feat, 'feature_title': strip_section_suffix(title, (model['by_number'].get(wave) or {}).get('title') or '')}


def task_state(task: dict, stuck: str) -> str:
    """人ごとの段の状態: 止まり（CI 赤・衝突）・判断待ち・人の作業・進行中・レビュー中・着手可。保留・ほかの Status は ほか。"""
    status = task.get('status') or ''
    if status == HELD_STATUS:
        return 'ほか'
    if stuck:
        return '止まり'
    if status == STATUS_DECISION:
        return STATUS_DECISION
    if is_human(task):
        return '人の作業'
    return status if status in ('進行中', 'レビュー中', '着手可') else 'ほか'


def mine_state(task: dict, has_worker: bool) -> str:
    """自分のアカウントの task の区分: 作業ツリーがある = AI の担当／題に [User]・[操作] = 人の作業／進行中・レビュー中なのに
    作業ツリーも印も無い = 担当の居ないもの／それ以外は Status ごと。"""
    status = task.get('status') or ''
    if has_worker:
        return MINE_AI
    if is_human(task):
        return MINE_HUMAN
    if status in NO_OWNER_STATUSES:
        return MINE_ORPHAN
    return status if status in MINE_ORDER else 'ほか'


def remaining_state(task: dict, not_ready: dict) -> str:
    """残り（開いている task）の内訳の区分。保留・判断待ち・人の作業（題の印）・依存待ち（着手可で未完了の blocked by）を先に決め、
    あとは Status（進行中・レビュー中・着手可・承認待ち）。ほかの Status は ほか。"""
    status = task.get('status') or ''
    if status == HELD_STATUS:
        return '保留'
    if status == STATUS_DECISION:
        return STATUS_DECISION
    if is_human(task):
        return '人の作業'
    if status == '着手可' and task['number'] in not_ready:
        return '依存待ち'
    return status if status in REMAINING_ORDER else 'ほか'


def pr_part(number: int, ctx: dict) -> dict | None:
    """その task の PR 1 本（draft でない・番号の大きいものを優先）と、段の語（止まり・draft・CI の状態）。無ければ None。"""
    mine = ctx['prs_of'].get(number, [])
    if not mine:
        return None
    best = max(mine, key=lambda p: (not p['draft'], p['number']))
    _pct, _note, stuck = stage_of(number, ctx)
    return {'number': best['number'], 'word': stuck or ('draft' if best['draft'] else f'CI {ci_state(best)}')}


def _task_key(entry: dict):
    order = entry.get('order')
    return (order is None, order if order is not None else 0.0, entry['number'])


def _groups(entries: list, order: tuple, state_key: str = 'state') -> list[dict]:
    out = []
    for state in order:
        picked = sorted((e for e in entries if e[state_key] == state), key=_task_key)
        if picked:
            out.append({'state': state, 'count': len(picked),
                        'tasks': [{k: e[k] for k in ('number', 'title', 'pr')} for e in picked]})
    return out


def build(view: dict, prs: dict, assign: dict, settings: dict, trees: dict | None = None) -> dict:
    """表の材料（JSON にできる形）を組む。"""
    model = hirai_board.build(view)
    # 担当の行は task と、控え（assign）に載った feature（割り振りの単位は feature。ADR-0815）。
    # 全体の数（sections の total・done）は task だけで数え、feature を足して二重に数えない。
    tasks = {i['number']: i for i in view['issues'] if hirai_board.is_task(i)}
    tasks.update({i['number']: i for i in view['issues'] if i.get('kind') == 'feature' and i['number'] in assign})
    ctx = {'tasks': tasks, 'prs_of': _pr_index(prs['open'], view['repo']),
           'merged_of': {n: [p['number'] for p in ps] for n, ps in _pr_index(prs['merged'], view['repo']).items()}}
    not_ready = view.get('not_ready') or {}
    me, assignees = prs.get('me') or '', prs.get('assignees') or {}
    me_key = me.casefold()
    people_map = {str(k).casefold(): v for k, v in (settings.get('people') or {}).items()}

    def name_of(login: str) -> str:
        return people_map.get(str(login).casefold(), login)

    by_number = {i['number']: i for i in view['issues']}
    live_issues = [i for i in view['issues'] if hirai_board.is_task(i) and hirai_board.is_open(i)]
    # 担当者は板の控え（issue の 'assignees'）が持つ。古い控えには鍵が無い。PR の問い合わせで引いた分（新しい）があればそちらを先に見る
    assignees_known = not live_issues or any('assignees' in i for i in live_issues)

    def assignees_of(n: int):
        """task の担当者の login（無ければ []）。控えにも問い合わせにも無ければ None。"""
        if str(n) in assignees:
            return [x for x in assignees[str(n)] if x]
        issue = by_number.get(n)
        if issue is not None and 'assignees' in issue:
            return [x for x in (issue['assignees'] or []) if x]
        return None

    sections = []
    for wave in model['waves']:
        rows = hirai_board.wave_tasks(model, wave['number'])
        if not rows:
            continue
        done = sum(1 for t in rows if not hirai_board.is_open(t))
        held = sum(1 for t in rows if hirai_board.is_open(t) and t.get('status') == HELD_STATUS)
        number, name = section_parts(wave)
        following = pick_next([t for t in rows if hirai_board.is_open(t)])
        logins = (assignees_of(following['number']) or []) if following else []
        sections.append({'name': section_name(model, wave['number']), 'number': number, 'label': name,
                         'total': len(rows), 'done': done, 'held': held,
                         'next': ({'number': following['number'], 'title': strip_marks(following.get('title')),
                                   'tag': turn_tag(following, not_ready), 'assignees': logins,
                                   'assignee_names': [name_of(x) for x in logins]} if following else None)})
    total, done, held = (sum(s[k] for s in sections) for k in ('total', 'done', 'held'))
    named = dict(assign)
    others_of: dict[str, str] = {}
    for n in list(named):  # 作業ツリーが手元に残っていても、Assignees が自分以外だけの task はその人の行に出す
        if n in tasks and hirai_board.is_open(tasks[n]):
            people_of = assignees_of(n) or []
            if people_of and me_key not in {x.casefold() for x in people_of}:
                others_of[n] = '・'.join(name_of(x) for x in people_of)
                named[n] = {'owner': others_of[n], 'order': None}
    for t in tasks.values():
        n = t['number']
        if n in named or not hirai_board.is_open(t) or t.get('status') not in NO_OWNER_STATUSES:
            continue
        people_of = assignees_of(n) or []
        if people_of and me_key not in {x.casefold() for x in people_of}:
            others_of[n] = '・'.join(name_of(x) for x in people_of)
            named[n] = {'owner': others_of[n], 'order': None}
    owners: dict[str, list[int]] = {}
    for n in sorted(named, key=lambda x: (x in others_of, named[x].get('order') is None, named[x].get('order') or 0, x)):
        owners.setdefault(named[n]['owner'], []).append(n)
    people = []
    for owner in sorted(owners, key=lambda o: (any(n in others_of for n in owners[o]),
                                               min((named[n].get('order') if named[n].get('order') is not None else 1e9)
                                                   for n in owners[o]), o)):
        entries = []
        for n in owners[owner]:
            pct, note, stuck = stage_of(n, ctx)
            mine = ctx['prs_of'].get(n, [])
            pr = max(mine, key=lambda p: (not p['draft'], p['number']))['number'] if mine else None
            entry = {'number': n, 'pct': pct, 'note': note, 'pr': pr, 'stuck': stuck, 'section': section_name(model, n),
                     'order': named[n].get('order'),
                     'is_feature': (tasks[n].get('kind') == 'feature') if n in tasks else False, **_ticket(model, n)}
            if entry['is_feature']:  # feature の行は、その子の task のうち動いているものを番号に出す
                entry['children'] = sorted(c['number'] for c in model['tasks_of'].get(n, [])
                                           if hirai_board.is_open(c) and c.get('status') in NO_OWNER_STATUSES)
                entry['children_stages'] = {c: list(_stage_and_stuck(c, ctx)) for c in entry['children']}  # 子の task 自身の段（PR・CI から）
                entry['children_prs'] = {c: (pr_part(c, ctx) or {}).get('number') for c in entry['children'] if pr_part(c, ctx)}
            entries.append(entry)
        if all(x['pct'] == 100 for x in entries):
            continue  # 全部閉じた担当は、古い割り振りの控えが残っているだけ。出さない
        closed = [x for x in entries if x['pct'] == 100]
        folded = closed[:-CLOSED_SHOWN] if len(closed) > CLOSED_SHOWN else []
        entries = [x for x in entries if x not in folded]  # 閉じた行は新しいほうだけ（古いものは畳む）
        people.append({'owner': owner, 'other': any(n in others_of for n in owners[owner]), 'tasks': entries})
    others = {}
    for pr in sorted(prs['open'], key=lambda p: p['number']):
        author = pr.get('author') or ''
        if me and author and author != me:
            for n in pr.get('closes') or []:
                n = int(n)
                if n not in named and n in tasks and hirai_board.is_open(tasks[n]) and n not in others:  # 同じ task を閉じる PR が複数でも 1 行
                    pct, _note, stuck = stage_of(n, ctx)
                    others[n] = {'number': n, 'pr': pr['number'], 'author': author, 'author_name': name_of(author),
                                 'pct': pct, 'stuck': stuck, **_ticket(model, n)}
    others = sorted(others.values(), key=lambda o: (o['pr'], o['number']))
    other_numbers = {o['number'] for o in others}
    in_trees = {int(x) for x in (trees or {}).get('numbers', ())}

    def has_worker(n: int) -> bool:  # 作業ツリーの名前に task か親の feature の番号がある = 担当が動いている
        return n in in_trees or _ticket(model, n)['feature'] in in_trees

    rem = {state: 0 for state in REMAINING_ORDER}
    for t in live_issues:
        rem[remaining_state(t, not_ready)] += 1
    remaining = {'count': len(live_issues), 'states': [[state, rem[state]] for state in REMAINING_ORDER if rem[state]]}
    by_assignee, unassigned = [], {'count': 0, 'states': []}
    if assignees_known:
        by_name: dict[str, dict] = {}
        free = []
        for t in live_issues:
            logins = assignees_of(t['number'])
            if logins is None:
                continue
            pct, _note, stuck = stage_of(t['number'], ctx)
            entry = {'number': t['number'], 'title': strip_marks(t.get('title')), 'state': task_state(t, stuck),
                     'pr': pr_part(t['number'], ctx), 'order': t.get('order'),
                     'mine_state': mine_state(t, has_worker(t['number']))}
            if not logins:
                free.append(entry)
            for login in logins:
                person = by_name.setdefault(name_of(login), {'name': name_of(login), 'logins': [], 'entries': {}})
                if login not in person['logins']:
                    person['logins'].append(login)
                person['entries'][t['number']] = entry
        for person in by_name.values():
            entries = list(person['entries'].values())
            is_me = bool(me_key) and any(x.casefold() == me_key for x in person['logins'])
            by_assignee.append({'name': person['name'], 'logins': person['logins'], 'me': is_me, 'count': len(entries),
                                'groups': _groups(entries, MINE_ORDER if is_me else STATE_ORDER,
                                                  'mine_state' if is_me else 'state')})
        by_assignee.sort(key=lambda p: (p['me'], -p['count'], p['name']))
        counts = {state: sum(1 for e in free if e['state'] == state) for state in UNASSIGNED_ORDER}
        unassigned = {'count': len(free), 'states': [[state, counts[state]] for state in UNASSIGNED_ORDER if counts[state]]}

    stray = [t['number'] for t in tasks.values()
             if hirai_board.is_open(t) and t.get('status') in NO_OWNER_STATUSES and t['number'] not in named
             and t['number'] not in other_numbers  # ほかの開発者の PR がある行は、担当の居ない行に出さない
             and not has_worker(t['number'])]
    stuck_tasks = [{'number': t['number'], 'stuck': t['stuck']} for p in people for t in p['tasks'] if t['stuck']]
    stray_rows = [(n, stage_of(n, ctx)[2]) for n in sorted(stray)]  # 担当の無い行の CI 赤・衝突も止まりに出す
    stuck_tasks += [{'number': n, 'stuck': mark} for n, mark in stray_rows if mark]
    open_total = prs.get('open_total')
    model_out = {'total': total, 'done': done, 'held': held, 'sections': sections, 'people': people,
                 'stray': sorted(stray), 'others': others, 'stuck': stuck_tasks, 'settings': settings,
                 'truncated': open_total if isinstance(open_total, int) and open_total > len(prs['open']) else 0,
                 'unknown_assignees': prs.get('unknown_assignees') or 0,
                 'me': me, 'remaining': remaining, 'assignees_known': assignees_known, 'by_assignee': by_assignee, 'unassigned': unassigned,
                 'tree_names': {int(k): v for k, v in ((trees or {}).get('names') or {}).items()},
                 'signature': signature(people), 'fetched_at': view.get('fetched_at', ''), 'how': view.get('how', '')}
    model_out['running'] = running_rows(model_out)
    model_out['turn'] = turn_rows(view, prs, tasks)
    return model_out


def signature(people: list) -> dict:
    """段・担当・順番の控え（--changed が前回と比べる）。"""
    out = {}
    for person in people:
        for i, t in enumerate(person['tasks']):
            out[str(t['number'])] = [t['pct'], person['owner'], i, t['stuck']]
    return out


def pct_of(done: int, total: int) -> int:
    return 100 * done // total if total > 0 else 0


def group_rows(entries: list) -> list[list[dict]]:
    """同じ PR の隣り合う task を 1 つにまとめ、セクションが変わる所で行を分ける（board --progress の rows の形）。"""
    groups: list[dict] = []
    for e in entries:
        last = groups[-1] if groups else None
        if last and e['pr'] is not None and last['pr'] == e['pr'] and last['section'] == e['section']:
            last['numbers'].append(e['number'])
        else:
            groups.append({'numbers': [e['number']], 'pr': e['pr'], 'pct': e['pct'], 'section': e['section']})
    runs: list[list[dict]] = []
    for g in groups:
        if runs and runs[-1][0]['section'] == g['section']:
            runs[-1].append(g)
        else:
            runs.append([g])
    return runs


_OWNER_PREFIX_RE = re.compile(r'^#\d+\s*')


def join_owners(owners: list[str], width: int, sep: str = '・') -> str:
    """担当（task の番号も同じ）を sep（既定は「・」。順番のある行は「→」）でつなぐ。幅を超えるときは後ろを落として「・ほか N」にする。"""
    for shown in range(len(owners), 0, -1):
        text = sep.join(owners[:shown]) + (f'・ほか {len(owners) - shown}' if shown < len(owners) else '')
        if disp_width(text) <= width:
            return text
    return clip_width(owners[0], width) if owners else ''


def running_rows(model: dict) -> list[dict]:
    """「いま動いている」の行。同じ feature の task は 1 行にまとめるが、自分の側（作業ツリー・控えの担当）とほかの開発者
    （GitHub の名前。開発者ごと）は別の行にする。task の番号は「・」でつなぎ、段は行に入った task 自身の段（PR・CI から出した段）の
    うちいちばん遅れているもの（止まり〔CI 赤・衝突〕があればそれ）。feature の Status では決めない。task が 1 件も入らない行は出さない。
    親の feature が分からない task は担当ごと。担当は作業ツリーの名前（無ければ控えの名前から先頭の `#番号 ` を落としたもの）。"""
    names = {int(k): v for k, v in (model.get('tree_names') or {}).items()}
    rows: list[dict] = []
    index: dict[tuple, dict] = {}

    def add(side: str, owner: str, entry: dict, stages: dict, prs: dict | None = None) -> None:
        if not stages:
            return
        key = (entry.get('feature'), side if entry.get('feature') else owner)
        row = index.get(key)
        if row is None:
            row = index[key] = {'feature': entry.get('feature'), 'feature_title': entry.get('feature_title') or '',
                                'numbers': [], 'stage': '', 'owner': '', 'owners': [], 'pct': 100, 'stuck': '',
                                'prs': {}, 'order_of': {}}
            if 'now' in entry:
                row['now'] = ''
            rows.append(row)
        row['numbers'] = sorted(set(row['numbers']) | set(stages))
        for k, v in (prs or {}).items():
            if v is not None:
                row['prs'][str(k)] = v
        if entry.get('order') is not None:
            for k in stages:
                row['order_of'][str(k)] = entry['order']
        if owner and owner not in row['owners']:
            row['owners'].append(owner)
        for pct, stuck in stages.values():
            if stuck and not row['stuck']:
                row['stuck'], row['pct'] = stuck, pct
            elif not row['stuck'] and pct < row['pct']:
                row['pct'] = pct
        row['stage'] = stage_word(row['pct'], row['stuck'])
        row['owner'] = '・'.join(row['owners'])
        if entry.get('now') and entry['now'] not in row.get('now', '').split(' ／ '):
            row['now'] = ' ／ '.join(x for x in (row.get('now', ''), entry['now']) if x)

    theirs = {o['number'] for o in model['others']} | {e['number'] for p in model['people'] if p.get('other') for e in p['tasks']}
    for person in model['people']:
        for entry in person['tasks']:
            if entry['pct'] == 100:
                continue
            if entry.get('is_feature'):  # 子の task のうち、ほかの開発者の行に出るものは自分の行に入れない
                stages = {int(k): tuple(v) for k, v in (entry.get('children_stages') or {}).items() if int(k) not in theirs}
                numbers = list(stages)
                prs = {int(k): v for k, v in (entry.get('children_prs') or {}).items()}
            else:
                stages, numbers = {entry['number']: (entry['pct'], entry['stuck'])}, [entry['number']]
                prs = {entry['number']: entry.get('pr')}
            name = next((names[k] for k in [entry['number'], *numbers] if k in names), '') \
                or _OWNER_PREFIX_RE.sub('', plain(person['owner'])) or plain(person['owner'])
            if person.get('other'):
                name = plain(person['owner'])
            add('dev:' + name if person.get('other') else 'own', name, entry, stages, prs)
    for o in model['others']:
        author = plain(o.get('author_name') or o['author'])
        add('dev:' + author, author, o, {o['number']: (o['pct'], o['stuck'])}, {o['number']: o.get('pr')})
    return rows


def turn_rows(view: dict, prs: dict, tasks: dict) -> list[dict]:
    """「あなたの番」の行（いま材料が取れるものだけ。GitHub は叩かない）: 取り込み待ちの PR・判断待ち・人の作業。"""
    rows: list[dict] = []
    me = prs.get('me') or ''
    ready_prs = []
    for pr in sorted(prs['open'], key=lambda p: p['number']):
        if me and (pr.get('author') or '') == me and ci_state(pr) == '緑' and not pr.get('conflict'):
            ready_prs.append({'number': pr['number'], 'draft': bool(pr.get('draft'))})
    if ready_prs:
        rows.append({'kind': '取り込み', 'prs': ready_prs, 'numbers': []})
    live = [t for t in sorted(tasks.values(), key=lambda t: t['number'])
            if hirai_board.is_task(t) and hirai_board.is_open(t) and t.get('kind') != 'feature']
    decide = [t['number'] for t in live if t.get('status') == STATUS_DECISION]
    if decide:
        rows.append({'kind': '判断', 'prs': [], 'numbers': decide})
    human = [t['number'] for t in live if is_human(t) and t.get('status') in ('着手可', '進行中', 'レビュー中')]
    if human:
        rows.append({'kind': '人の作業', 'prs': [], 'numbers': human})
    return rows


def deadline_part(settings: dict) -> str:
    """期限の行（1 行目に寄せる）。設定が無ければ空。"""
    date = settings.get('deadline_date') or ''
    label = one_line(settings.get('deadline_label') or '')
    if not date or not label:
        return ''
    match = re.fullmatch(r'\d{4}-(\d{2})-(\d{2})', date)
    short = f'{int(match.group(1))}/{int(match.group(2))}' if match else date
    label = re.split(r'[（(]', label)[0].strip() or label  # 「ベータ（12/15・…）」は「ベータ」だけ（日付は別に出す）
    n = settings.get('deadline_open')
    if n is None:
        return f'{label} {short} の件数は引けませんでした'
    return f'{label} {short} まで残り {n} 件'


def headline(model: dict) -> str:
    total, done, held = model['total'], model['done'], model['held']
    parts = [f'全体 {done}/{total}（{pct_of(done, total)}%）']
    if held:
        parts.append(f'保留 {held} を除くと {pct_of(done, total - held)}%')
    parts.append(deadline_part(model['settings']))
    return '  '.join(x for x in parts if x)


def _section_lines(model: dict) -> list[str]:
    s = model['settings']
    mainline = s.get('mainline') or ''
    mark = f"（{one_line(s.get('mainline_label') or '本線')}）"
    open_sections = [x for x in model['sections'] if x['done'] < x['total']]
    if not open_sections:
        return []
    numw = max(disp_width(x['number']) for x in open_sections)
    names = [clip_width(x['label'] + (mark if mainline and mainline in x['name'] else ''), NAME_WIDTH) for x in open_sections]
    left = max(1 + numw + (1 if numw else 0) + max(disp_width(n) for n in names), disp_width('セクション'))
    raw = [f"{x['done']}/{x['total']}" for x in open_sections]
    rw = max(disp_width(c) for c in raw)
    pcts = [f"{pct_of(x['done'], x['total'])}%" for x in open_sections]
    pw = max(disp_width(c) for c in pcts)
    counts = [' ' * (rw - disp_width(c)) + c + '  ' + ' ' * (pw - disp_width(q)) + q for c, q in zip(raw, pcts)]
    cw = max([disp_width(c) for c in counts] + [disp_width('完了')])
    nxt = [x['next'] for x in open_sections]
    idw = max([disp_width(f"#{n['number']}") for n in nxt if n] + [0])
    titles = [clip_width(n['title'], TITLE_WIDTH) if n else '' for n in nxt]
    tw = max(max([disp_width(t) for t in titles] + [0]), disp_width('次のタスク') - idw - 1)
    tags = [f"［{n['tag']}］" if n else '' for n in nxt]
    tagw = max([disp_width(t) for t in tags] + [disp_width('誰の番')])
    who = [(('・'.join(n.get('assignee_names') or [])) or NO_ASSIGNEE) if n else '' for n in nxt]
    out = [pad('セクション', left) + '  ' + ' ' * (cw - disp_width('完了')) + '完了' + '  '
           + pad('次のタスク', idw + 1 + tw) + '  ' + pad('誰の番', tagw) + '  担当']
    for x, name, count, n, title, tag, owner in zip(open_sections, names, counts, nxt, titles, tags, who):
        line = ' ' + pad(x['number'], numw) + (' ' if numw else '') + pad(name, left - 1 - numw - (1 if numw else 0))
        line += '  ' + ' ' * (cw - disp_width(count)) + count + '  '
        if n:
            line += pad(f"#{n['number']}", idw) + ' ' + pad(title, tw) + '  ' + pad(tag, tagw) + '  ' + clip_width(owner, OWNER_WIDTH)
        out.append(line.rstrip())
    return out


def _row_tasks(row: dict) -> list[str]:
    """行の task の番号（PR があれば `#n（PR #m）`）。控えの順番がある行は、順番 → 番号の順に並べる。"""
    order_of, prs = row.get('order_of') or {}, row.get('prs') or {}
    numbers = sorted(row['numbers'], key=lambda n: (str(n) not in order_of, order_of.get(str(n), 0), n)) if order_of else row['numbers']
    groups: list[list] = []  # 同じ PR の隣り合う task は「#a・#b（PR #n）」にまとめる
    for n in numbers:
        pr = prs.get(str(n))
        if groups and pr is not None and groups[-1][0] == pr:
            groups[-1][1].append(n)
        else:
            groups.append([pr, [n]])
    return ['・'.join(f'#{n}' for n in ns) + (f'（PR #{pr}）' if pr is not None else '') for pr, ns in groups]


def _running_lines(model: dict) -> list[str]:
    rows = model['running']
    out = [f'いま動いている {len(rows)}']
    if not rows:
        return out
    feats = [clip_width(f"F#{r['feature']} {r['feature_title']}" if r['feature'] else 'F#—', FEATURE_TITLE_WIDTH + 8).rstrip() for r in rows]
    tasks = [join_owners(_row_tasks(r), TASKS_WIDTH, '→' if r.get('order_of') else '・') or '—' for r in rows]
    # 止まり（衝突・CI 赤）の行は % を出さず、止まる前の段を括弧で出す（止まっているのに 70% と読めないように）
    stages = [f"{r['stage']}（{STAGE_WORDS.get(r['pct'], str(r['pct']) + '%')}）" if r['stuck'] else f"{r['stage']} {r['pct']}%" for r in rows]
    owners = [join_owners(r['owners'], OWNER_WIDTH) for r in rows]
    fw, tw, sw = (max(disp_width(x) for x in col) for col in (feats, tasks, stages))
    show_now = any(r.get('now') for r in rows)
    ow = max(disp_width(x) for x in owners)
    for r, f, t, st, o in zip(rows, feats, tasks, stages, owners):
        line = f' {pad(f, fw)}  {pad(t, tw)}  {pad(st, sw)}  {pad(o, ow) if show_now else o}'
        if show_now and r.get('now'):
            line += '  ' + clip_width(r['now'], NOW_WIDTH)
        out.append(line.rstrip())
    return out


def _pr_text(pr) -> str:
    return f"（PR #{pr['number']}・{pr['word']}）" if pr else ''


def _group_lines(group: dict, label_width: int) -> list[str]:
    """状態 1 つ分の行。件数が PEOPLE_SHOWN 以内なら 1 件 1 行（題と PR・CI の段つき）。超えるときは番号だけ先頭 3 件と「ほか N」の 1 行。"""
    tasks, label = group['tasks'], pad(group['state'], label_width)
    if len(tasks) <= PEOPLE_SHOWN:
        return [f"   {label if i == 0 else pad('', label_width)}  #{t['number']} {clip_width(t['title'], PEOPLE_TITLE_WIDTH)}{_pr_text(t.get('pr'))}".rstrip()
                for i, t in enumerate(tasks)]
    shown = '・'.join(f"#{t['number']}" + (f"（PR #{t['pr']['number']}）" if t.get('pr') else '') for t in tasks[:PEOPLE_SHOWN])
    return [f'   {label}  {shown} ほか {len(tasks) - PEOPLE_SHOWN}']


def _people_lines(model: dict) -> list[str]:
    """人ごと（開いている task）。担当者ごとに状態ごと。自分のアカウントは AI の担当（作業ツリーがある task）と人の作業に分ける。"""
    people, free = model.get('by_assignee') or [], model.get('unassigned') or {'count': 0, 'states': []}
    if not people and not free['count']:
        return []
    out = ['人ごと（開いている task）']
    label_width = max([disp_width(g['state']) for p in people for g in p['groups']] + [0])
    for person in people:
        out.append(f" {person['name']} {person['count']}（" + '・'.join(f"{g['state']} {g['count']}" for g in person['groups']) + '）')
        for group in person['groups']:
            out += _group_lines(group, label_width)
    if free['count']:
        out.append(f" 担当なし {free['count']}（" + '・'.join(f'{state} {n}' for state, n in free['states']) + '）')
    return out


def _turn_lines(model: dict) -> list[str]:
    rows = model.get('turn') or []
    if not rows:
        return []
    out = [f'あなたの番 {len(rows)}']
    width = max(disp_width(r['kind']) for r in rows)
    for r in rows:
        if r['prs']:
            body = '、'.join(f"PR #{p['number']}（{'Draft・' if p['draft'] else ''}緑）" for p in r['prs'])
        else:
            shown = r['numbers'][:TURN_MAX]
            body = '・'.join(f'#{n}' for n in shown) + (f' ほか {len(r["numbers"]) - TURN_MAX}' if len(r['numbers']) > TURN_MAX else '')
        out.append(f' {pad(r["kind"], width)}  {body}')
    return out


def render(model: dict, age_minutes: int | None = None, extra: list | tuple = ()) -> str:
    """桁をそろえた平文の段（全体と期限の 1 行・セクションごとの次のタスクと担当・いま動いている・人ごと・あなたの番）と、
    担当の居ないもの。Markdown の表は使わない（hook の出力では描かれない）。age_minutes があれば先頭に控えの古さの 1 行。
    extra は、あなたの番のあとに足す行（board --progress の「これから立てる」など）。"""
    out: list[str] = []
    if not model.get('assignees_known', True):
        out += [STALE_NOTE, '']
    if age_minutes is not None:
        out += [f'控えは {age_minutes} 分前の数です。取り直す: hirai-task load', '']
    out += [headline(model)]
    rem = model.get('remaining') or {'count': 0, 'states': []}
    if rem['count']:
        out += [f"残り {rem['count']}: " + '・'.join(f'{state} {n}' for state, n in rem['states'])]
    out += ['']
    sections = _section_lines(model)
    out += sections + ([''] if sections else [])
    out += _running_lines(model)
    people = _people_lines(model)
    out += [''] + people if people else []
    turn = _turn_lines(model)
    out += [''] + turn if turn else []
    notes: list[str] = []
    if model['stray']:
        marks = {t['number']: t['stuck'] for t in model['stuck']}
        notes.append('担当の居ないもの（進行中・レビュー中）: ' + '、'.join(
            f'#{n}' + (f'（{marks[n]}）' if marks.get(n) else '') for n in model['stray']))
    notes += list(extra)
    if model['truncated']:
        notes.append(f"開いている PR が {model['truncated']} 本あり、新しいほうだけで数えています。")
    if model['unknown_assignees']:
        notes.append(f"Assignees を見ていない 進行中・レビュー中 の task が {model['unknown_assignees']} 件あります。")
    out += [''] + notes if notes else []
    return '\n'.join(out) + '\n'


def changed(model: dict, previous: dict | None) -> bool:
    """前回の控えと比べて、どれかの段・担当・順番が動いたか（初回は控えが無いので True）。"""
    return (previous or {}).get('signature') != model['signature']
