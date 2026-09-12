"""s24: can the app read the web form layout? Read-only. For an inherited
process (CloudCover 2.0) and the scratch project's process: project
capabilities -> process id -> process work item types -> form layout for
Bug, User Story, Task and a custom type. Also the org-wide field list so
every control can be matched to a field type. Prints shapes and counts,
nothing is written to the service."""
import json, os, sys, urllib.parse
from collections import Counter

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402

PROJECTS = ['CloudCover 2.0', 'DevOps Mobile App']
WANTED = ['Bug', 'User Story', 'Product Backlog Item', 'Issue', 'Task', 'Tech Task', 'QA Task', 'Epic']
out = ['# Spike s24 — process form layout', '']

# --- org-wide field types (one call) ---
s, h, fields = get(f'{ORG_URL}/_apis/wit/fields?api-version=7.1')
ftype = {}
if isinstance(fields, dict):
    for f in fields.get('value', []):
        ftype[f['referenceName']] = (f.get('type'), f.get('isIdentity'), f.get('isPicklist'), f.get('readOnly'), f.get('usage'))
print('wit/fields (org):', s, len(ftype))
out += [f'## `GET {{org}}/_apis/wit/fields` — HTTP {s}, {len(ftype)} fields', '',
        'field keys: ' + ', '.join(sorted((fields.get('value') or [{}])[0].keys())) if isinstance(fields, dict) else str(fields)[:300], '',
        'type counts: ' + json.dumps(Counter(v[0] for v in ftype.values()), sort_keys=True), '']

for project in PROJECTS:
    P = urllib.parse.quote(project)
    out += [f'# Project: {project}', '']
    s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?includeCapabilities=true&api-version=7.1')
    caps = (proj.get('capabilities') or {}).get('processTemplate') or {}
    pid = caps.get('templateTypeId')
    print(f'\n{project}: projects?includeCapabilities', s, caps)
    out += [f'## projects?includeCapabilities=true — HTTP {s}', '', f'processTemplate: `{json.dumps(caps)}`', '']
    if not pid:
        continue

    s, h, proc = get(f'{ORG_URL}/_apis/work/processes/{pid}?api-version=7.1')
    print('process:', s, {k: proc.get(k) for k in ('name', 'referenceName', 'customizationType', 'parentProcessTypeId', 'isEnabled')} if isinstance(proc, dict) else proc)
    out += [f'## processes/{{id}} — HTTP {s}', '', '```json', short(proc, 800), '```', '']

    s, h, wits = get(f'{ORG_URL}/_apis/work/processes/{pid}/workitemtypes?api-version=7.1')
    types = wits.get('value', []) if isinstance(wits, dict) else []
    print('process workitemtypes:', s, len(types))
    out += [f'## processes/{{id}}/workitemtypes — HTTP {s}, {len(types)} types', '',
            '| name | referenceName | customization | inherits | isDisabled |', '|---|---|---|---|---|']
    for t in types:
        out.append(f"| {t.get('name')} | `{t.get('referenceName')}` | {t.get('customization')} | `{t.get('inherits')}` | {t.get('isDisabled')} |")
    out.append('')
    if not types:
        out += ['```', short(wits, 600), '```', '']

    byname = {t['name']: t for t in types}
    for name in WANTED:
        t = byname.get(name)
        if not t:
            continue
        ref = t['referenceName']
        s, h, layout = get(f'{ORG_URL}/_apis/work/processes/{pid}/workitemtypes/{urllib.parse.quote(ref)}/layout?api-version=7.1')
        print(f'  layout {name} ({ref}):', s, sorted(layout.keys()) if isinstance(layout, dict) else str(layout)[:200])
        out += [f'## layout for {name} (`{ref}`) — HTTP {s}', '']
        if not isinstance(layout, dict) or 'pages' not in layout:
            out += ['```', short(layout, 800), '```', '']
            continue
        out += ['top-level keys: ' + ', '.join(sorted(layout.keys())), '']
        sysc = layout.get('systemControls') or []
        out += ['systemControls: ' + ', '.join(f"{c.get('id')}({c.get('controlType')}{', hidden' if c.get('visible') is False else ''})" for c in sysc), '']
        ctypes = Counter()
        for page in layout.get('pages', []):
            out.append(f"### page `{page.get('id')}` \"{page.get('label')}\" type={page.get('pageType')} visible={page.get('visible')} locked={page.get('locked')} inherited={page.get('inherited')}")
            for sec in page.get('sections', []):
                groups = sec.get('groups') or []
                out.append(f"- section `{sec.get('id')}`: {len(groups)} groups")
                for g in groups:
                    out.append(f"  - group \"{g.get('label')}\" (id `{g.get('id')}`, visible={g.get('visible')}, inherited={g.get('inherited')}, isContribution={g.get('isContribution')})")
                    for c in g.get('controls') or []:
                        ctypes[c.get('controlType')] += 1
                        ft = ftype.get(c.get('id'))
                        out.append(f"    - `{c.get('id')}` \"{c.get('label')}\" {c.get('controlType')} readOnly={c.get('readOnly')} visible={c.get('visible')} contribution={c.get('isContribution')} field={ft}")
            out.append('')
        out += ['control types: ' + json.dumps(ctypes, sort_keys=True), '']
        if name == 'Bug':
            out += ['raw sample (first page, truncated):', '```json', short(layout.get('pages', [None])[0], 2500), '```', '']

    # the project-scoped type: does xmlForm carry the same layout? (size only)
    s, h, wt = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/Bug?api-version=7.1')
    if isinstance(wt, dict):
        xml = wt.get('xmlForm') or ''
        tr = wt.get('transitions') or {}
        print('  project wit/workitemtypes/Bug:', s, 'xmlForm bytes', len(xml), 'transitions from "":', tr.get(''))
        out += [f'## project `wit/workitemtypes/Bug` — HTTP {s}: xmlForm {len(xml)} bytes, keys {sorted(wt.keys())}', '',
                f'transitions[""] (states a new item may start in): `{json.dumps(tr.get(""))}`', '']

out.append(dump_costs())
write_result('s24_process_layout.md', '\n'.join(out))
