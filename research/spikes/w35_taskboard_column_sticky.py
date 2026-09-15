"""w35 (SCRATCH WRITES ONLY): does an explicit taskboard column survive a state change?

w34 settled that `PATCH taskboardworkitems/{iter}/{id}` only accepts a column whose
mapping matches the item's CURRENT state, and never writes System.State itself.
Two columns in the scratch taskboard ("In Progress" and "Verify") both map Task ->
Active, so this asks: after parking a task in "Verify" and then patching
System.State away and back, which column does it land in?

Also: the error shape when the item is not in that iteration, and whether a Bug
(bugsBehavior=asTasks) is patchable the same way.
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, call, dump_costs, write_result, short  # noqa: E402

API = 'api-version=7.1'
PREV = 'api-version=7.1-preview.1'
PROJECT = 'DevOps Mobile App'
TEAM = '8c08e1e1-7afd-411e-b414-4f9e1d14d8d6'
ITER = 'aa9f2381-54e4-499a-8b8b-e3f981aac964'
P = urllib.parse.quote(PROJECT, safe='')
WORK = f'{ORG_URL}/{P}/{TEAM}/_apis/work'
WIT = f'{ORG_URL}/{P}/_apis/wit'
TASK = 15550
BUG = 15547
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


def row(wid):
    s, h, tw = get(f'{WORK}/taskboardworkitems/{ITER}?{PREV}')
    return next((x for x in (tw.get('value') or []) if x.get('workItemId') == wid), None)


def set_state(wid, state):
    s, h, r = get(f'{WIT}/workitems/{wid}?{API}')
    s2, h2, r2 = jpatch(f'{WIT}/workitems/{wid}?{API}',
                        [{'op': 'test', 'path': '/rev', 'value': r.get('rev')},
                         {'op': 'add', 'path': '/fields/System.State', 'value': state}])
    return s2, r2


blk('1  park the task in "Verify", then change state away and back')
s, h, r = mpatch(f'{WORK}/taskboardworkitems/{ITER}/{TASK}?{PREV}', {'newColumn': 'Verify'})
p(f'  PATCH newColumn=Verify: HTTP {s}; row now {row(TASK)}')
s, _ = set_state(TASK, 'Closed')
p(f'  PATCH System.State=Closed: HTTP {s}; row now {row(TASK)}')
s, _ = set_state(TASK, 'Active')
p(f'  PATCH System.State=Active: HTTP {s}; row now {row(TASK)}')
p('  -> the explicit "Verify" placement is lost / kept: see the column above')

blk('2  park in Verify, then re-read without any state change')
s, h, r = mpatch(f'{WORK}/taskboardworkitems/{ITER}/{TASK}?{PREV}', {'newColumn': 'Verify'})
p(f'  PATCH newColumn=Verify: HTTP {s}; row now {row(TASK)}')
p(f'  re-read again: {row(TASK)}')

blk('3  a Bug under bugsBehavior=asTasks')
s, h, before = get(f'{WIT}/workitems/{BUG}?{API}')
p(f'  #{BUG} state before = {(before.get("fields") or {}).get("System.State")!r}; row {row(BUG)}')
s, r = set_state(BUG, 'Active')
p(f'  set Active: HTTP {s}; row {row(BUG)}')
s, h, rr = mpatch(f'{WORK}/taskboardworkitems/{ITER}/{BUG}?{PREV}', {'newColumn': 'Verify'})
p(f'  PATCH newColumn=Verify (Bug/Verify maps to Resolved, state is Active): HTTP {s}')
p('  ' + short(rr, 400))
s, r = set_state(BUG, 'Resolved')
p(f'  set Resolved: HTTP {s}; row {row(BUG)}')
s, r = set_state(BUG, 'New')
p(f'  restored to New: HTTP {s}; row {row(BUG)}')

blk('4  error shapes')
s, h, rr = mpatch(f'{WORK}/taskboardworkitems/{ITER}/999999?{PREV}', {'newColumn': 'To Do'})
p(f'  unknown work item id: HTTP {s} ' + short(rr, 300))
s, h, rr = mpatch(f'{WORK}/taskboardworkitems/{ITER}/{TASK}?{PREV}', {'newColumn': 'Nope'})
p(f'  unknown column name: HTTP {s} ' + short(rr, 300))
s, h, rr = mpatch(f'{WORK}/taskboardworkitems/{ITER}/15546?{PREV}', {'newColumn': 'To Do'})
p(f'  a requirement (User Story 15546), not a task: HTTP {s} ' + short(rr, 300))
s, h, rr = mpatch(f'{WORK}/taskboardworkitems/{ITER}/{TASK}?{PREV}',
                  {'newColumnId': 'dcefc9e2-be24-4ea0-a3a6-90fd3de38b20'})
p(f'  newColumnId instead of newColumn: HTTP {s} ' + short(rr, 300))

blk('5  leave the scratch tidy')
s, _ = set_state(TASK, 'New')
p(f'  #{TASK} back to New: HTTP {s}; row {row(TASK)}')
s, h, tw = get(f'{WORK}/taskboardworkitems/{ITER}?{PREV}')
p('  taskboard now: ' + short(tw.get('value'), 1400))

OUT.append(dump_costs('w35 rate-limit cost log'))
write_result('w35_taskboard_column_sticky/raw.md', '\n'.join(OUT))
print(dump_costs('w35 rate-limit cost log'))
