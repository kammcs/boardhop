"""w02: does writing the WEF Kanban column field auto-derive System.State, and vice versa?"""
from scratch import *

out = ['# w02 — Kanban column patch vs System.State (scratch project)', f'Project: {SCRATCH} · Team: {TEAM}', '']

s, h, boards = get(f'{ORG_URL}/{P}/{T}/_apis/work/boards?api-version=7.1')
bid = next(b['id'] for b in boards['value'] if b['name'] == 'Stories')
s, h, board = get(f'{ORG_URL}/{P}/{T}/_apis/work/boards/{bid}?api-version=7.1')
col = board['fields']['columnField']['referenceName']
done = board['fields']['doneField']['referenceName']
lane = board['fields']['rowField']['referenceName']
cols = {c['name']: c for c in board['columns']}
out += [f'column field `{col}`; columns: {list(cols)}', '']


def snap(wid):
    s, h, w = get(f'{ORG_URL}/_apis/wit/workitems/{wid}?api-version=7.1')
    f = w['fields']
    return {'rev': w['rev'], 'State': f.get('System.State'), 'BoardColumn': f.get('System.BoardColumn'),
            'WEF.Column': f.get(col), 'WEF.Done': f.get(done), 'WEF.Lane': f.get(lane), 'Reason': f.get('System.Reason')}


s, h, c = wi_create('User Story', [{'op': 'add', 'path': '/fields/System.Title', 'value': '[spike] w02 column-only patch'}])
s, h, d = wi_create('User Story', [{'op': 'add', 'path': '/fields/System.Title', 'value': '[spike] w02 state-only patch'}])
s, h, e = wi_create('User Story', [{'op': 'add', 'path': '/fields/System.Title', 'value': '[spike] w02 both-fields patch'}])
out += [f'created #{c["id"]}, #{d["id"]}, #{e["id"]}', f'initial C: `{snap(c["id"])}`', '']

s, h, r = wi_patch(c['id'], [{'op': 'add', 'path': '/fields/' + col, 'value': 'Active'}])
out += [f'## Test 1 — PATCH only WEF column = "Active" on #{c["id"]} — HTTP {s}', f'after: `{snap(c["id"]) if s < 300 else short(r, 400)}`', '']

s, h, r = wi_patch(d['id'], [{'op': 'add', 'path': '/fields/System.State', 'value': 'Active'}])
out += [f'## Test 2 — PATCH only System.State = "Active" on #{d["id"]} — HTTP {s}', f'after: `{snap(d["id"]) if s < 300 else short(r, 400)}`', '']

s, h, r = wi_patch(e['id'], [{'op': 'add', 'path': '/fields/' + col, 'value': 'Resolved'}, {'op': 'add', 'path': '/fields/System.State', 'value': 'Resolved'}])
out += [f'## Test 3 — PATCH WEF column and System.State = "Resolved" on #{e["id"]} — HTTP {s}', f'after: `{snap(e["id"]) if s < 300 else short(r, 400)}`', '']

before = snap(c['id'])['State']
s, h, r = wi_patch(c['id'], [{'op': 'add', 'path': '/fields/' + col, 'value': 'Closed'}])
out += [f'## Test 4 — PATCH only WEF column = "Closed" on #{c["id"]} (state was {before}) — HTTP {s}', f'after: `{snap(c["id"]) if s < 300 else short(r, 400)}`', '']

s, h, r = wi_patch(d['id'], [{'op': 'add', 'path': '/fields/' + col, 'value': 'NoSuchColumn'}])
out += [f'## Test 5 — PATCH WEF column = "NoSuchColumn" — HTTP {s}', '```json', short(r if s >= 300 else snap(d['id']), 500), '```', '']

s, h, r = wi_patch(d['id'], [{'op': 'add', 'path': '/fields/' + done, 'value': True}])
out += [f'## Test 6 — PATCH WEF Column.Done = true on a non-split column — HTTP {s}', f'after: `{snap(d["id"]) if s < 300 else short(r, 400)}`', '']

s, h, r = wi_patch(e['id'], [{'op': 'add', 'path': '/fields/' + col, 'value': 'New'}, {'op': 'add', 'path': '/fields/System.State', 'value': 'New'}], extra='&validateOnly=true')
out += [f'## Test 7 — validateOnly=true column move back to New — HTTP {s} (should not change)', f'after: `{snap(e["id"])}`', '']

s, h, r = wi_patch(e['id'], [{'op': 'add', 'path': '/fields/System.BoardColumn', 'value': 'New'}])
out += [f'## Test 8 — PATCH System.BoardColumn directly — HTTP {s}', '```json', short(r if s >= 300 else snap(e['id']), 400), '```', '']

out.append(f'Work items left in place: #{c["id"]}, #{d["id"]}, #{e["id"]}')
out.append(dump_costs())
write_result('w02_kanban_column_patch.md', '\n'.join(out))
