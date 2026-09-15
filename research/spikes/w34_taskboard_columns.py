"""w34 (SCRATCH PROJECT WRITES ONLY): finish what w33 left open.

  1  PUT work/taskboardcolumns with a mapping for EVERY state of EVERY
     task-backlog type (w33's 400 said Bug/Resolved was unmapped)
  2  PATCH taskboardworkitems/{iterationId}/{workItemId}: the real body
     (w33's 400 named the parameter `newColumn`)
  3  after a column move, what happened to System.State? and after a plain
     System.State patch, what happened to the taskboard column?
  4  where the column value is stored on the work item
  5  the team-iteration attribute lag w33 saw after a classificationnodes PATCH

Scratch project "DevOps Mobile App" only.
"""
import os, sys, json, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402

API = 'api-version=7.1'
PREV = 'api-version=7.1-preview.1'
PROJECT = 'DevOps Mobile App'
TEAM = '8c08e1e1-7afd-411e-b414-4f9e1d14d8d6'
ITER = 'aa9f2381-54e4-499a-8b8b-e3f981aac964'
P = urllib.parse.quote(PROJECT, safe='')
WORK = f'{ORG_URL}/{P}/{TEAM}/_apis/work'
WIT = f'{ORG_URL}/{P}/_apis/wit'
TARGET = 15550          # Task, child of User Story 15546, in Iteration 1
SIBLING = 15553
OUT = []


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def blk(t):
    p('')
    p('=' * 78)
    p('===', t)
    p('=' * 78)


def jpatch(url, body):
    return call('PATCH', url, body, headers={'Content-Type': 'application/json-patch+json'})


def mpatch(url, body):
    return call('PATCH', url, body, headers={'Content-Type': 'application/json'})


def wi(wid):
    s, h, r = get(f'{WIT}/workitems/{wid}?{API}')
    return r if isinstance(r, dict) else {}


def summary(wid):
    r = wi(wid)
    f = r.get('fields') or {}
    extra = {k: v for k, v in f.items() if 'Kanban' in k or 'Board' in k or 'Column' in k}
    return (f'#{wid} rev={r.get("rev")} state={f.get("System.State")!r} '
            f'reason={f.get("System.Reason")!r} column-ish fields={extra}')


def board_row(wid):
    s, h, tw = get(f'{WORK}/taskboardworkitems/{ITER}?{PREV}')
    if s != 200:
        return f'HTTP {s}'
    return next((x for x in (tw.get('value') or []) if x.get('workItemId') == wid), None)


# ------------------------------------------------ 1 customize with full mappings
blk('1  PUT work/taskboardcolumns with every state mapped')
s, h, bc = get(f'{ORG_URL}/{P}/{TEAM}/_apis/work/backlogconfiguration?{API}')
task_types = [t.get('name') for t in ((bc.get('taskBacklog') or {}).get('workItemTypes') or [])]
p(f'  task backlog types: {task_types}')
states = {}
for t in task_types:
    s, h, st = get(f'{WIT}/workitemtypes/{urllib.parse.quote(t)}/states?{API}')
    states[t] = [(r.get('name'), r.get('category')) for r in (st.get('value') or [])]
    p(f'    {t}: {states[t]}')

columns = [
    {'name': 'To Do', 'order': 0,
     'mappings': [{'workItemType': 'Task', 'state': 'New'},
                  {'workItemType': 'Bug', 'state': 'New'}]},
    {'name': 'In Progress', 'order': 1,
     'mappings': [{'workItemType': 'Task', 'state': 'Active'},
                  {'workItemType': 'Bug', 'state': 'Active'}]},
    {'name': 'Verify', 'order': 2,
     'mappings': [{'workItemType': 'Task', 'state': 'Active'},
                  {'workItemType': 'Bug', 'state': 'Resolved'}]},
    {'name': 'Done', 'order': 3,
     'mappings': [{'workItemType': 'Task', 'state': 'Closed'},
                  {'workItemType': 'Bug', 'state': 'Closed'}]},
]
s, h, r = call('PUT', f'{WORK}/taskboardcolumns?{PREV}', columns)
p(f'\n  PUT (bare array, all states mapped): HTTP {s}')
p('  ' + short(r, 1400))
s, h, cols = get(f'{WORK}/taskboardcolumns?{PREV}')
p(f'  read back: isCustomized={cols.get("isCustomized")} isValid={cols.get("isValid")}')
COLNAMES = [c.get('name') for c in (cols.get('columns') or [])]
COLIDS = {c.get('name'): c.get('id') for c in (cols.get('columns') or [])}
p(f'  columns: {COLNAMES}')
p(f'  ids: {COLIDS}')

# ------------------------------------------------------------ 2 the PATCH body
blk('2  PATCH taskboardworkitems/{iterationId}/{workItemId}')
s, h, tw = get(f'{WORK}/taskboardworkitems/{ITER}?{PREV}')
rows = tw.get('value') or [] if isinstance(tw, dict) else []
p(f'  GET taskboardworkitems now: HTTP {s} count={len(rows)}')
p('  ' + short(rows, 1200))
p(f'  before: {summary(TARGET)}')
p(f'  board row before: {board_row(TARGET)}')

url = f'{WORK}/taskboardworkitems/{ITER}/{TARGET}?{PREV}'
attempts = [
    ('{"newColumn": "Done"}', {'newColumn': 'Done'}),
    ('{"newColumn": "To Do"}', {'newColumn': 'To Do'}),
    ('{"newColumn": "Verify", "newState": "Active"}', {'newColumn': 'Verify', 'newState': 'Active'}),
    ('{"newColumn": "In Progress"}', {'newColumn': 'In Progress'}),
]
for label, body in attempts:
    s, h, r = mpatch(url, body)
    p(f'\n  PATCH {label}: HTTP {s} cost={h.get("X-RateLimit-Cost")}')
    p('    response: ' + short(r, 400))
    p(f'    board row: {board_row(TARGET)}')
    p(f'    work item: {summary(TARGET)}')

# ---------------------------------------- 3 plain state patch -> column follows?
blk('3  a plain PATCH of System.State with the taskboard now customized')
for state in ('New', 'Closed', 'Active'):
    r = wi(TARGET)
    s, h, r2 = jpatch(f'{WIT}/workitems/{TARGET}?{API}',
                      [{'op': 'test', 'path': '/rev', 'value': r.get('rev')},
                       {'op': 'add', 'path': '/fields/System.State', 'value': state}])
    p(f'\n  PATCH System.State={state}: HTTP {s}')
    if s != 200:
        p('    ' + short(r2, 300))
        continue
    p(f'    board row: {board_row(TARGET)}')
    p(f'    work item: {summary(TARGET)}')

# ------------------------------------ 3b a column whose mapping is ambiguous
blk('3b  moving to "Verify" (Task maps to the same state as "In Progress")')
s, h, r = mpatch(url, {'newColumn': 'Verify'})
p(f'  PATCH newColumn=Verify: HTTP {s} ' + short(r, 300))
p(f'  board row: {board_row(TARGET)}')
p(f'  work item: {summary(TARGET)}')
s, h, r = mpatch(url, {'newColumn': 'In Progress'})
p(f'  PATCH newColumn="In Progress": HTTP {s} ' + short(r, 300))
p(f'  board row: {board_row(TARGET)}')
p('  -> does a state-only patch land the item back in the FIRST column that maps '
  'that state, losing the Verify placement?')

# ------------------------------------------- 4 where is the column stored?
blk('4  the work item fields after a taskboard column move')
r = wi(TARGET)
f = r.get('fields') or {}
p(f'  all fields on #{TARGET}: {sorted(f.keys())}')
p(f'  multilineFieldsFormat / extras: {[k for k in r.keys() if k not in ("id","rev","fields","_links","url")]}')
s, h, one = get(f'{WIT}/workitems/{TARGET}?$expand=all&{API}')
p(f'  $expand=all keys: {sorted(one.keys()) if isinstance(one, dict) else one}')
if isinstance(one, dict):
    p(f'  relations: {[(x.get("rel"), x.get("url","")[-12:]) for x in (one.get("relations") or [])]}')

# ------------------------------------------ 5 the team-iteration attribute lag
blk('5  classificationnodes PATCH -> how fast does teamsettings/iterations see it?')
s, h, node = get(f'{WIT}/classificationnodes/Iterations/Iteration%202?{API}')
p(f'  Iteration 2 node attributes before: {node.get("attributes")}')
t0 = time.time()
s, h, r = mpatch(f'{WIT}/classificationnodes/Iterations/Iteration%202?{API}',
                 {'attributes': {'startDate': '2026-09-22T00:00:00Z',
                                 'finishDate': '2026-10-05T00:00:00Z'}})
p(f'  PATCH: HTTP {s} attributes now {r.get("attributes") if isinstance(r, dict) else r}')
for attempt in range(6):
    s, h, its = get(f'{WORK}/teamsettings/iterations?{API}')
    row = next((x for x in (its.get('value') or []) if x.get('name') == 'Iteration 2'), None)
    p(f'    +{round(time.time()-t0, 1)}s teamsettings/iterations sees: {row.get("attributes") if row else None}')
    if row and (row.get('attributes') or {}).get('startDate'):
        break
    time.sleep(2)
s, h, its = get(f'{WORK}/teamsettings/iterations?{API}')
for row in (its.get('value') or []):
    p(f'  {row.get("name")!r} {row.get("attributes")}')
s, h, cur = get(f'{WORK}/teamsettings/iterations?{API}&$timeframe=current')
p(f'  $timeframe=current: {[x.get("name") for x in (cur.get("value") or [])]}')

blk('6  final scratch state')
s, h, cols = get(f'{WORK}/taskboardcolumns?{PREV}')
p(f'  taskboardcolumns isCustomized={cols.get("isCustomized")} '
  f'{[c.get("name") for c in (cols.get("columns") or [])]}')
s, h, tw = get(f'{WORK}/taskboardworkitems/{ITER}?{PREV}')
p('  taskboardworkitems: ' + short(tw.get('value'), 1200))

OUT.append(dump_costs('w34 rate-limit cost log'))
write_result('w34_taskboard_columns/raw.md', '\n'.join(OUT))
print(dump_costs('w34 rate-limit cost log'))
