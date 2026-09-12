"""s27: record scratch-project form fixtures for the unit tests.

Read-only. Saves, under test/fixtures/forms/ (scratch project only, no client
data): the full `wit/workitemtypes/{Bug,User Story}` payload (xmlForm,
states, transitions), each type's `fields?$expand=All`, the org field list
filtered to the fields those two types use, and the scratch team's
backlogconfiguration / workitemtypecategories. Also prints the
portfolioBacklogs ranks, which spike s25 did not record.
"""
import json, os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result  # noqa: E402

PROJECT = 'DevOps Mobile App'
TYPES = ['Bug', 'User Story']
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
OUT = os.path.join(REPO, 'test', 'fixtures', 'forms')
os.makedirs(OUT, exist_ok=True)
P = urllib.parse.quote(PROJECT)
out = ['# Spike s27 — form fixtures for the unit tests', '']


def save(name, payload):
    path = os.path.join(OUT, name)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(payload, f, indent=1, ensure_ascii=False, sort_keys=False)
        f.write('\n')
    size = os.path.getsize(path)
    print(f'  wrote {name} ({size} bytes)')
    out.append(f'- `test/fixtures/forms/{name}` — {size} bytes')


used_fields = set()
for tname in TYPES:
    slug = tname.lower().replace(' ', '_')
    s, h, wt = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/{urllib.parse.quote(tname)}?api-version=7.1')
    print(f'{tname}: type HTTP {s}, keys {sorted(wt.keys()) if isinstance(wt, dict) else wt}')
    out.append(f'## {tname} — type HTTP {s}, xmlForm {len(wt.get("xmlForm") or "") if isinstance(wt, dict) else 0} bytes')
    if s == 200:
        used_fields.update(f.get('referenceName') for f in (wt.get('fields') or []))
        # fieldInstances repeats fields and _links is noise: both double the
        # fixture size without adding anything the parser reads.
        save(f'scratch_{slug}_type.json', {k: v for k, v in wt.items() if k not in ('fieldInstances', '_links')})
    s, h, fl = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/{urllib.parse.quote(tname)}/fields?$expand=All&api-version=7.1')
    print(f'{tname}: fields HTTP {s}, count {len(fl.get("value", [])) if isinstance(fl, dict) else 0}')
    if s == 200:
        save(f'scratch_{slug}_fields.json', fl)
        used_fields.update(f.get('referenceName') for f in fl.get('value', []))

s, h, org_fields = get(f'{ORG_URL}/_apis/wit/fields?api-version=7.1')
print(f'org fields HTTP {s}, count {len(org_fields.get("value", [])) if isinstance(org_fields, dict) else 0}')
if s == 200:
    # Only the fields the two scratch types use, so no client process field
    # names (Custom.*) land in the repository, and only the keys the parser
    # reads.
    wanted = ('referenceName', 'name', 'type', 'isIdentity', 'isPicklist', 'readOnly', 'usage',
              'canSortBy', 'isQueryable', 'description')
    keep = [{k: f[k] for k in wanted if k in f}
            for f in org_fields.get('value', []) if f.get('referenceName') in used_fields]
    save('org_fields.json', {'count': len(keep), 'value': keep})
    out.append(f'org field list filtered to the two types: {len(keep)} of {len(org_fields.get("value", []))}')
    print('  types present:', sorted({f.get('type') for f in keep}))
    out.append('types present: ' + json.dumps(sorted({f.get('type') for f in keep})))

T = urllib.parse.quote(f'{PROJECT} Team')
s, h, bc = get(f'{ORG_URL}/{P}/{T}/_apis/work/backlogconfiguration?api-version=7.1')
if s == 200:
    ranks = [(b.get('name'), b.get('rank'), b.get('id'), [w.get('name') for w in b.get('workItemTypes') or []])
             for b in bc.get('portfolioBacklogs') or []]
    print('portfolioBacklogs (api order):', ranks)
    out += ['', '## backlogconfiguration', '', 'portfolioBacklogs in API order: ' + json.dumps(ranks),
            f'requirementBacklog rank: {(bc.get("requirementBacklog") or {}).get("rank")}',
            f'taskBacklog rank: {(bc.get("taskBacklog") or {}).get("rank")}', '']
    save('scratch_backlogconfiguration.json', bc)

s, h, cats = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypecategories?api-version=7.1')
if s == 200:
    save('scratch_workitemtypecategories.json', cats)

out.append(dump_costs())
write_result('s27_form_fixtures.md', '\n'.join(out))
print('done')
