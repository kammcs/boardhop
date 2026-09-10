"""Spike 10 (+ the read half of spike 7): board config, raw card settings and rule settings schema,
WEF field names from board.fields, and whether work items expose those fields via batch.
"""
from lib import *

P = urllib.parse.quote(DEFAULT_PROJECT)
out = ['# Spike 10 — Board schema, card settings, WEF fields (read-only)', f'Org: {ORG_URL} · Project: {DEFAULT_PROJECT}', '']

s, h, teams = get(f'{ORG_URL}/_apis/projects/{P}/teams?api-version=7.1')
tlist = teams.get('value', []) if isinstance(teams, dict) else []
team = tlist[0]['name'] if tlist else None
out.append(f'teams: {[t["name"] for t in tlist]} → using `{team}`')
if not team:
    write_result('s10_board_schema_and_wef.md', '\n'.join(out + [dump_costs()]))
    sys.exit()
T = urllib.parse.quote(team)

s, h, bc = get(f'{ORG_URL}/{P}/{T}/_apis/work/backlogconfiguration?api-version=7.1')
view = {k: bc.get(k) for k in ['bugsBehavior', 'backlogFields', 'workItemTypeMappedStates']} if isinstance(bc, dict) else bc
out += ['', '## backlogconfiguration', f'HTTP {s}', '```json', short(view, 1500), '```']

s, h, boards = get(f'{ORG_URL}/{P}/{T}/_apis/work/boards?api-version=7.1')
blist = boards.get('value', []) if isinstance(boards, dict) else []
out += ['', '## boards', f'HTTP {s}', f'{[b["name"] for b in blist]}']
if not blist:
    write_result('s10_board_schema_and_wef.md', '\n'.join(out + [dump_costs()]))
    sys.exit()
bid = blist[0]['id']

s, h, board = get(f'{ORG_URL}/{P}/{T}/_apis/work/boards/{bid}?api-version=7.1')
out += ['', f'## boards/{{id}} ({blist[0]["name"]})', f'HTTP {s}', '```json',
        short({k: board.get(k) for k in ['fields', 'columns', 'rows', 'canEdit', 'isValid', 'revision']}, 3000), '```']
for name in ['cardsettings', 'cardrulesettings']:
    s, h, cs = get(f'{ORG_URL}/{P}/{T}/_apis/work/boards/{bid}/{name}?api-version=7.1')
    out += ['', f'## boards/{{id}}/{name} (undocumented schema — captured raw)', f'HTTP {s}', '```json', short(cs, 3000), '```']

fields = board.get('fields', {}) if isinstance(board, dict) else {}
refs = [fields[k]['referenceName'] for k in ['columnField', 'rowField', 'doneField'] if fields.get(k)]
out += ['', f'WEF reference names from board.fields: `{refs}`']
guid_check = bid.replace('-', '').upper()
out.append(f'Does the WEF guid equal Board.id with dashes stripped and upper-cased? {bool(refs) and all(guid_check in r for r in refs)}')

wiql = {'query': "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject]=@project AND [System.State] NOT IN ('Closed','Done','Removed') ORDER BY [System.ChangedDate] DESC"}
s, h, q = post(f'{ORG_URL}/{P}/_apis/wit/wiql?$top=10&api-version=7.1', wiql)
ids = [w['id'] for w in q.get('workItems', [])] if isinstance(q, dict) else []
if ids and refs:
    s, h, batch = post(f'{ORG_URL}/{P}/_apis/wit/workitemsbatch?api-version=7.1',
                       {'ids': ids, 'fields': ['System.Id', 'System.Title', 'System.State', 'System.WorkItemType', 'System.BoardColumn', 'System.BoardLane'] + refs, 'errorPolicy': 'omit'})
    out += ['', '## workitemsbatch with WEF fields requested', f'HTTP {s}',
            '| id | type | state | System.BoardColumn | WEF column | WEF lane | WEF done |', '|---|---|---|---|---|---|---|']
    col = refs[0]; lane = refs[1] if len(refs) > 1 else None; done = refs[2] if len(refs) > 2 else None
    for w in batch.get('value', []) if isinstance(batch, dict) else []:
        f = w['fields']
        out.append(f'| {w["id"]} | {f.get("System.WorkItemType")} | {f.get("System.State")} | {f.get("System.BoardColumn")} | {f.get(col)} | {f.get(lane) if lane else ""} | {f.get(done) if done else ""} |')
out.append(dump_costs())
write_result('s10_board_schema_and_wef.md', '\n'.join(out))
