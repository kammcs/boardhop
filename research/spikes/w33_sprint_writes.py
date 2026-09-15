"""w33 (SCRATCH PROJECT WRITES ONLY): the sprint / taskboard writes.

Everything here targets "DevOps Mobile App" and its default team. Nothing
touches a client project.

  1  customize the scratch taskboard columns (PUT work/taskboardcolumns) so the
     taskboardworkitems routes stop answering 400
  2  PATCH taskboardworkitems/{iterationId}/{workItemId}: which body moves a
     task, {state} or {column}?
  3  what a plain PATCH wit/workitems/{id} of System.State does to the column
  4  Remaining Work on a task
  5  set a team iteration's dates (classificationnodes) and read the timeFrame back
  6  add an iteration to the team (POST work/teamsettings/iterations {id})
  7  task order inside a cell: PATCH {team}/_apis/work/workitemsorder with parentId
"""
import os, sys, json, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402

API = 'api-version=7.1'
PROJECT = 'DevOps Mobile App'
TEAM = '8c08e1e1-7afd-411e-b414-4f9e1d14d8d6'
ITER = 'aa9f2381-54e4-499a-8b8b-e3f981aac964'   # scratch "Iteration 1"
P = urllib.parse.quote(PROJECT, safe='')
WORK = f'{ORG_URL}/{P}/{TEAM}/_apis/work'
WIT = f'{ORG_URL}/{P}/_apis/wit'
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


def put(url, body):
    return call('PUT', url, body)


def jpatch(url, body):
    return call('PATCH', url, body, headers={'Content-Type': 'application/json-patch+json'})


def mpatch(url, body):
    return call('PATCH', url, body, headers={'Content-Type': 'application/json'})


def item(wid, fields=None):
    url = f'{WIT}/workitems/{wid}?{API}'
    if fields:
        url += '&fields=' + urllib.parse.quote(','.join(fields))
    s, h, r = get(url)
    return r


def summary(wid):
    r = item(wid)
    f = r.get('fields') or {} if isinstance(r, dict) else {}
    return (f'#{wid} rev={r.get("rev")} type={f.get("System.WorkItemType")} '
            f'state={f.get("System.State")!r} reason={f.get("System.Reason")!r} '
            f'BoardColumn={f.get("System.BoardColumn")!r} '
            f'Remaining={f.get("Microsoft.VSTS.Scheduling.RemainingWork")} '
            f'StackRank={f.get("Microsoft.VSTS.Common.StackRank")}')


# ------------------------------------------------- 0 what is in the sprint now
blk('0  the scratch sprint as it stands')
s, h, wi = get(f'{WORK}/teamsettings/iterations/{ITER}/workitems?{API}')
rels = wi.get('workItemRelations') or []
ids = sorted({r['target']['id'] for r in rels if r.get('target')})
s, h, batch = post(f'{WIT}/workitemsbatch?{API}',
                   {'ids': ids, 'fields': ['System.Id', 'System.WorkItemType', 'System.State',
                                           'System.Parent', 'System.Title',
                                           'Microsoft.VSTS.Scheduling.RemainingWork',
                                           'Microsoft.VSTS.Common.StackRank']})
rows = {r['id']: (r.get('fields') or {}) for r in (batch.get('value') or [])}
for i in ids:
    f = rows.get(i, {})
    p(f'  {i} {f.get("System.WorkItemType"):11s} {str(f.get("System.State")):8s} '
      f'parent={f.get("System.Parent")} {str(f.get("System.Title"))[:48]!r}')
tasks = [i for i in ids if rows.get(i, {}).get('System.WorkItemType') in ('Task', 'Bug')]
parented = [i for i in tasks if rows.get(i, {}).get('System.Parent')]
p(f'  task-category items: {tasks}; with a parent: {parented}')
TARGET = parented[0] if parented else tasks[0]
p(f'  TARGET task for the column move: {TARGET}')

# ------------------------------------------ 1 customize the taskboard columns
blk('1  PUT work/taskboardcolumns (scratch): customize the taskboard')
s, h, before = get(f'{WORK}/taskboardcolumns?api-version=7.1-preview.1')
p(f'  before: HTTP {s} ' + short(before, 300))
body = {
    'columns': [
        {'name': 'To Do', 'order': 0,
         'mappings': [{'workItemType': 'Task', 'state': 'New'},
                      {'workItemType': 'Bug', 'state': 'New'}]},
        {'name': 'In Progress', 'order': 1,
         'mappings': [{'workItemType': 'Task', 'state': 'Active'},
                      {'workItemType': 'Bug', 'state': 'Active'}]},
        {'name': 'Done', 'order': 2,
         'mappings': [{'workItemType': 'Task', 'state': 'Closed'},
                      {'workItemType': 'Bug', 'state': 'Closed'}]},
    ]
}
s, h, r = put(f'{WORK}/taskboardcolumns?api-version=7.1-preview.1', body)
p(f'  PUT (wrapped in "columns"): HTTP {s}')
p('  ' + short(r, 900))
if s != 200:
    s, h, r = put(f'{WORK}/taskboardcolumns?api-version=7.1-preview.1', body['columns'])
    p(f'  PUT (bare array): HTTP {s}')
    p('  ' + short(r, 900))
s, h, cols = get(f'{WORK}/taskboardcolumns?api-version=7.1-preview.1')
p(f'  read back: HTTP {s} isCustomized={cols.get("isCustomized")} '
  f'isValid={cols.get("isValid")} columns={len(cols.get("columns") or [])}')
p('  ' + short(cols.get('columns'), 1200))
COLS = {c['name']: c for c in (cols.get('columns') or [])}

# ------------------------------------------------- 2 taskboardworkitems PATCH
blk('2  taskboardworkitems: read, then PATCH {state} vs {column}')
s, h, tw = get(f'{WORK}/taskboardworkitems/{ITER}?api-version=7.1-preview.1')
p(f'  GET taskboardworkitems/{{iteration}}: HTTP {s} count={len(tw.get("value") or [])}')
p('  ' + short(tw.get('value'), 900))
p('  work item before: ' + summary(TARGET))

for label, patch_body in (
    ('{"state": "Active"}', {'state': 'Active'}),
    ('{"column": "Done"}', {'column': 'Done'}),
    ('{"state": "Closed", "column": "Done"}', {'state': 'Closed', 'column': 'Done'}),
):
    url = f'{WORK}/taskboardworkitems/{ITER}/{TARGET}?api-version=7.1-preview.1'
    s, h, r = mpatch(url, patch_body)
    p(f'\n  PATCH {label}: HTTP {s} body={short(r, 300)}')
    s2, h2, tw = get(f'{WORK}/taskboardworkitems/{ITER}?api-version=7.1-preview.1')
    row = next((x for x in (tw.get('value') or []) if x.get('workItemId') == TARGET), None)
    p(f'    taskboard row now: {row}')
    p(f'    work item now: {summary(TARGET)}')

# --------------------------------- 3 plain System.State patch vs the column
blk('3  a plain PATCH wit/workitems/{id} of System.State')
r = item(TARGET)
rev = r.get('rev')
s, h, r2 = jpatch(f'{WIT}/workitems/{TARGET}?{API}',
                  [{'op': 'test', 'path': '/rev', 'value': rev},
                   {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'}])
p(f'  PATCH System.State=Active: HTTP {s}')
if s != 200:
    p('  ' + short(r2, 400))
s, h, tw = get(f'{WORK}/taskboardworkitems/{ITER}?api-version=7.1-preview.1')
row = next((x for x in (tw.get('value') or []) if x.get('workItemId') == TARGET), None)
p(f'  taskboard row after the plain state patch: {row}')
p(f'  work item: {summary(TARGET)}')
p('  -> does the taskboard column follow System.State with no column write? '
  f'{row and row.get("column")}')

# ------------------------------------------------------- 4 Remaining Work
blk('4  Remaining Work')
r = item(TARGET)
rev = r.get('rev')
s, h, r2 = jpatch(f'{WIT}/workitems/{TARGET}?{API}',
                  [{'op': 'test', 'path': '/rev', 'value': rev},
                   {'op': 'add', 'path': '/fields/Microsoft.VSTS.Scheduling.RemainingWork',
                    'value': 4.5}])
p(f'  PATCH RemainingWork=4.5: HTTP {s}')
if s != 200:
    p('  ' + short(r2, 500))
p(f'  {summary(TARGET)}')
# does it roll up to the parent automatically?
parent = rows.get(TARGET, {}).get('System.Parent')
if parent:
    pr = item(parent)
    pf = pr.get('fields') or {}
    p(f'  parent #{parent} RemainingWork={pf.get("Microsoft.VSTS.Scheduling.RemainingWork")} '
      f'(no server-side rollup expected)')
# set it back to a whole number and probe a null
r = item(TARGET)
s, h, r2 = jpatch(f'{WIT}/workitems/{TARGET}?{API}',
                  [{'op': 'test', 'path': '/rev', 'value': r.get('rev')},
                   {'op': 'add', 'path': '/fields/Microsoft.VSTS.Scheduling.RemainingWork',
                    'value': None}])
p(f'  PATCH RemainingWork=null (clear): HTTP {s} -> '
  f'{(r2.get("fields") or {}).get("Microsoft.VSTS.Scheduling.RemainingWork", "<absent>") if s == 200 else short(r2, 250)}')
r = item(TARGET)
jpatch(f'{WIT}/workitems/{TARGET}?{API}',
       [{'op': 'test', 'path': '/rev', 'value': r.get('rev')},
        {'op': 'add', 'path': '/fields/Microsoft.VSTS.Scheduling.RemainingWork', 'value': 3}])
p(f'  restored: {summary(TARGET)}')

# -------------------------------------------------- 5 iteration dates
blk('5  set the scratch team iteration dates')
s, h, node = get(f'{WIT}/classificationnodes/Iterations/Iteration%201?{API}')
p(f'  node before: HTTP {s} ' + short({k: node.get(k) for k in ('id', 'identifier', 'name', 'path', 'attributes')}, 400))
s, h, r = mpatch(f'{WIT}/classificationnodes/Iterations/Iteration%201?{API}',
                 {'attributes': {'startDate': '2026-09-08T00:00:00Z',
                                 'finishDate': '2026-09-21T00:00:00Z'}})
p(f'  PATCH classificationnodes attributes: HTTP {s}')
p('  ' + short(r, 500))
s, h, its = get(f'{WORK}/teamsettings/iterations?{API}')
for row in (its.get('value') or []):
    p(f'  team iteration {row.get("name")!r} attributes={row.get("attributes")}')
s, h, cur = get(f'{WORK}/teamsettings/iterations?{API}&$timeframe=current')
p(f'  $timeframe=current now: {[x.get("name") for x in (cur.get("value") or [])]}')

# ------------------------------------------- 6 add an iteration to the team
blk('6  add an iteration to the team')
s, h, its = get(f'{WORK}/teamsettings/iterations?{API}')
have = {x.get('name') for x in (its.get('value') or [])}
p(f'  team already subscribes to: {sorted(have)}')
# make sure a project node exists that the team does not have
s, h, tree = get(f'{WIT}/classificationnodes/Iterations?$depth=2&{API}')
children = {c.get('name'): c for c in (tree.get('children') or [])}
p(f'  project iteration nodes: {sorted(children)}')
NEWNAME = 'Boardhop Sprint Probe'
if NEWNAME not in children:
    s, h, created = post(f'{WIT}/classificationnodes/Iterations?{API}',
                         {'name': NEWNAME,
                          'attributes': {'startDate': '2026-09-22T00:00:00Z',
                                         'finishDate': '2026-10-05T00:00:00Z'}})
    p(f'  POST classificationnodes (create the node): HTTP {s}')
    p('  ' + short(created, 500))
    node_id = created.get('identifier') if isinstance(created, dict) else None
else:
    node_id = children[NEWNAME].get('identifier')
    p(f'  node already exists, identifier={node_id}')
if node_id:
    s, h, added = post(f'{WORK}/teamsettings/iterations?{API}', {'id': node_id})
    p(f'  POST work/teamsettings/iterations {{"id": "{node_id}"}}: HTTP {s}')
    p('  ' + short(added, 600))
    s, h, its = get(f'{WORK}/teamsettings/iterations?{API}')
    for row in (its.get('value') or []):
        p(f'    team iteration {row.get("name")!r} tf={(row.get("attributes") or {}).get("timeFrame")} '
          f'{(row.get("attributes") or {}).get("startDate")}..{(row.get("attributes") or {}).get("finishDate")}')
    # and remove it again so the scratch team stays tidy
    s, h, _ = call('DELETE', f'{WORK}/teamsettings/iterations/{node_id}?{API}')
    p(f'  DELETE work/teamsettings/iterations/{{id}} (unsubscribe): HTTP {s}')
    s, h, _ = call('DELETE', f'{WIT}/classificationnodes/Iterations/'
                   f'{urllib.parse.quote(NEWNAME)}?{API}')
    p(f'  DELETE the classification node: HTTP {s}')

# ------------------------------------------------- 7 order inside a cell
blk('7  workitemsorder with parentId (task order in a cell)')
siblings = [i for i in tasks if rows.get(i, {}).get('System.Parent') ==
            rows.get(TARGET, {}).get('System.Parent')]
p(f'  siblings under parent {rows.get(TARGET, {}).get("System.Parent")}: {siblings}')
if len(siblings) >= 2:
    a, b = siblings[0], siblings[1]
    s, h, r = mpatch(f'{WORK}/workitemsorder?{API}',
                     {'ids': [b], 'previousId': 0, 'nextId': a,
                      'parentId': rows.get(TARGET, {}).get('System.Parent') or 0})
    p(f'  PATCH workitemsorder move {b} before {a} (parentId set): HTTP {s}')
    p('  ' + short(r, 500))
    s, h, wi2 = get(f'{WORK}/teamsettings/iterations/{ITER}/workitems?{API}')
    kids = [x['target']['id'] for x in (wi2.get('workItemRelations') or [])
            if x.get('source') and x['source']['id'] == rows.get(TARGET, {}).get('System.Parent')]
    p(f'  child order from iterations/workitems now: {kids}')
    s, h, bb = post(f'{WIT}/workitemsbatch?{API}',
                    {'ids': siblings, 'fields': ['System.Id', 'Microsoft.VSTS.Common.StackRank',
                                                 'Microsoft.VSTS.Common.BacklogPriority']})
    for row in (bb.get('value') or []):
        p(f'    {row["id"]} {row.get("fields")}')
else:
    p('  fewer than two sibling tasks; nothing to reorder')

blk('8  final state of the scratch sprint')
s, h, cols = get(f'{WORK}/taskboardcolumns?api-version=7.1-preview.1')
p(f'  taskboardcolumns isCustomized={cols.get("isCustomized")} '
  f'names={[c.get("name") for c in (cols.get("columns") or [])]}')
s, h, tw = get(f'{WORK}/taskboardworkitems/{ITER}?api-version=7.1-preview.1')
p('  taskboardworkitems: ' + short(tw.get('value'), 900))
p(f'  {summary(TARGET)}')

OUT.append(dump_costs('w33 rate-limit cost log'))
write_result('w33_sprint_writes/raw.md', '\n'.join(OUT))
print(dump_costs('w33 rate-limit cost log'))
