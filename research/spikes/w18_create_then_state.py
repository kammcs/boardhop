"""w18: a board-column create needs the card in the column's state, but
w16 showed a Bug cannot be created directly as Active. Scratch project
only: create a Bug as New, then patch State (with test /rev) to Active
in a second call, and check which states a fresh Bug may move to."""
import json, os, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P, wi_create, wi_patch  # noqa: E402

out = ['# Spike w18 — create, then move to the column state (scratch project)', '']
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == SCRATCH, proj

s, h, wt = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/Bug?api-version=7.1')
tr = wt.get('transitions') or {}
print('Bug transitions from "" :', [t['to'] for t in tr.get('', [])], '| from New:', [t['to'] for t in tr.get('New', [])])
out += [f'Bug transitions: from "" → {[t["to"] for t in tr.get("", [])]}; from New → {[t["to"] for t in tr.get("New", [])]}', '']

s, h, bug = wi_create('Bug', [
    {'op': 'add', 'path': '/fields/System.Title', 'value': '[spike] w18 bug created for a board column'},
    {'op': 'add', 'path': '/fields/Microsoft.VSTS.Common.Severity', 'value': '2 - High'},
    {'op': 'add', 'path': '/fields/System.Tags', 'value': 'spike; w18'},
])
print('create as New:', s, bug.get('id') if isinstance(bug, dict) else str(bug)[:200])
out += [f'## create (state left to the server) — HTTP {s}: #{bug.get("id")} state {bug["fields"].get("System.State")!r} rev {bug.get("rev")}', '']
assert s == 200, bug

s, h, moved = wi_patch(bug['id'], [
    {'op': 'test', 'path': '/rev', 'value': bug['rev']},
    {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
])
print('patch to Active:', s, moved['fields'].get('System.State') if isinstance(moved, dict) else str(moved)[:200], moved.get('fields', {}).get('System.Reason') if isinstance(moved, dict) else '')
out += [f'## patch State=Active with test /rev — HTTP {s}: state {moved.get("fields", {}).get("System.State")!r}, reason {moved.get("fields", {}).get("System.Reason")!r}, rev {moved.get("rev")}', '']
if s != 200:
    out += ['```json', short(moved, 600), '```', '']

# and one illegal jump, to see the message the form would show
s, h, bad = wi_patch(bug['id'], [
    {'op': 'test', 'path': '/rev', 'value': moved.get('rev')},
    {'op': 'add', 'path': '/fields/System.State', 'value': 'Closed'},
    {'op': 'add', 'path': '/fields/System.Reason', 'value': 'Not a real reason'},
], extra='&validateOnly=true')
print('dry run Closed with a bad reason:', s, (bad.get('message') or '')[:160] if isinstance(bad, dict) else str(bad)[:160])
out += [f'## dry run State=Closed + bad Reason — HTTP {s}', '```json', short({k: bad.get(k) for k in ('message', 'typeKey')} | {'errors': (bad.get('customProperties') or {}).get('RuleValidationErrors')} if isinstance(bad, dict) else bad, 800), '```', '']

out.append(dump_costs())
write_result('w18_create_then_state.md', '\n'.join(out))
