"""w05: give the scratch project's Stories board a split column and a swimlane so the
app's Doing/Done halves, lane filter and rank writes can be exercised. Writes only in
the scratch project. Idempotent: re-running leaves the same configuration."""
import json, os, sys, urllib.parse
sys.stdout.reconfigure(encoding='utf-8')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, call, get, COST_LOG  # noqa: E402

SCRATCH = 'DevOps Mobile App'
P = urllib.parse.quote(SCRATCH)
API = 'api-version=7.1'
out = ['# w05 — scratch board configuration (split column + swimlane)', '']

s, h, boards = get(f'{ORG_URL}/{P}/_apis/work/boards?{API}')
bid = next(b['id'] for b in boards['value'] if b['name'] == 'Stories')
s, h, cols = get(f'{ORG_URL}/{P}/_apis/work/boards/{bid}/columns?{API}')
out.append(f'columns before: {[(c["name"], c.get("isSplit"), c.get("itemLimit")) for c in cols["value"]]}')
changed = False
for c in cols['value']:
    if c['name'] == 'Active' and not (c.get('isSplit') and c.get('itemLimit') == 5):
        c['isSplit'] = True
        c['itemLimit'] = 5
        changed = True
if changed:
    s, h, r = call('PUT', f'{ORG_URL}/{P}/_apis/work/boards/{bid}/columns?{API}', cols['value'])
    got = r.get('value') if isinstance(r, dict) else r
    out.append(f'PUT columns → HTTP {s}: {[(c["name"], c.get("isSplit"), c.get("itemLimit")) for c in got] if isinstance(got, list) else str(r)[:600]}')
else:
    out.append('columns already configured')

s, h, rows = get(f'{ORG_URL}/{P}/_apis/work/boards/{bid}/rows?{API}')
out.append(f'rows before: {[(r.get("id"), r.get("name")) for r in rows["value"]]}')
if not any(r.get('name') == 'Expedite' for r in rows['value']):
    body = rows['value'] + [{'name': 'Expedite', 'color': '#FDE9B0'}]
    s, h, r = call('PUT', f'{ORG_URL}/{P}/_apis/work/boards/{bid}/rows?{API}', body)
    got = r.get('value') if isinstance(r, dict) else r
    out.append(f'PUT rows → HTTP {s}: {[(x.get("id"), x.get("name")) for x in got] if isinstance(got, list) else str(r)[:600]}')
else:
    out.append('lane already present')

# Put story 15507 in the Expedite lane through the WEF row field.
s, h, board = get(f'{ORG_URL}/{P}/_apis/work/boards/{bid}?{API}')
lane_field = board['fields']['rowField']['referenceName']
s, h, w = get(f'{ORG_URL}/_apis/wit/workitems/15507?{API}')
lane_exists = any(r.get('name') == 'Expedite' for r in get(f'{ORG_URL}/{P}/_apis/work/boards/{bid}/rows?{API}')[2]['value'])
want = 'Expedite' if lane_exists else ''
if (w['fields'].get(lane_field) or '') != want:
    ops = [{'op': 'test', 'path': '/rev', 'value': w['rev']},
           {'op': 'add', 'path': f'/fields/{lane_field}', 'value': want}]
    s, h, r = call('PATCH', f'{ORG_URL}/{P}/_apis/wit/workitems/15507?{API}', ops,
                   headers={'Content-Type': 'application/json-patch+json'})
    out.append(f'PATCH 15507 lane = {want!r} → HTTP {s}')
else:
    out.append(f'15507 lane already {want!r}')

out += ['', '## Cost log', *[f'- {m} {u} → {st} cost={c} delay={d} {t}s' for m, u, st, c, d, t in COST_LOG]]
os.makedirs(os.path.join(os.path.dirname(__file__), 'results'), exist_ok=True)
open(os.path.join(os.path.dirname(__file__), 'results', 'w05-board-config.md'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('\n'.join(out))
