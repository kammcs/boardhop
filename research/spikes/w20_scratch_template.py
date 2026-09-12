"""w20: create ONE work item template on the scratch team so the type
chooser's template expansion can finally be exercised (phase 4). Scratch
project only. Records the create response shape, the list shape (does the
list carry `fields`?) and the single-template read."""
import json, os, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, call, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P, T  # noqa: E402

out = ['# Spike w20 — a team template on the scratch team', '']

s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == SCRATCH, proj

base = f'{ORG_URL}/{P}/{T}/_apis/wit/templates'

s, h, before = get(f'{base}?api-version=7.1')
existing = before.get('value') if isinstance(before, dict) else None
print('templates before:', s, [t.get('name') for t in (existing or [])])
out += [f'## list before — HTTP {s}: {[t.get("name") for t in (existing or [])]}', '']

mine = [t for t in (existing or []) if t.get('name') == 'Boardhop spike task']
if mine:
    tid = mine[0]['id']
    print('template already exists:', tid)
    out += [f'Template already existed: `{tid}`', '']
else:
    s, h, created = call('POST', f'{base}?api-version=7.1', {
        'name': 'Boardhop spike task',
        'workItemTypeName': 'Task',
        'description': 'Scratch template for the Boardhop type chooser',
        'fields': {
            'System.Title': '[template] ',
            'Microsoft.VSTS.Common.Priority': '1',
            'System.Tags': 'template; boardhop',
        },
    })
    print('create:', s, short(created, 400))
    out += [f'## create — HTTP {s}', '```json', short(created, 900), '```', '']
    assert s in (200, 201), created
    tid = created['id']

s, h, after = get(f'{base}?api-version=7.1')
rows = after.get('value') if isinstance(after, dict) else []
print('templates after:', s, [(t.get('name'), t.get('workItemTypeName'), 'fields' in t) for t in rows])
out += [
    f'## list after — HTTP {s}',
    '',
    '| name | workItemTypeName | has `fields` | id |',
    '|---|---|---|---|',
    *[f'| {t.get("name")} | {t.get("workItemTypeName")} | {"yes" if t.get("fields") else "no"} | `{t.get("id")}` |' for t in rows],
    '',
    '```json', short(rows[0] if rows else {}, 700), '```', '',
]

s, h, one = get(f'{base}/{tid}?api-version=7.1')
print('single read:', s, json.dumps(one.get('fields') if isinstance(one, dict) else one))
out += [f'## single read `templates/{{id}}` — HTTP {s}', '```json', short(one, 900), '```', '']

# by type, the filter the chooser uses
s, h, byType = get(f'{base}?workitemtypename=Task&api-version=7.1')
print('by type Task:', s, len((byType or {}).get('value') or []))
out += [f'## `?workitemtypename=Task` — HTTP {s}: {len((byType or {}).get("value") or [])} row(s)', '']

out.append(dump_costs())
write_result('w20_scratch_template.md', '\n'.join(out))
