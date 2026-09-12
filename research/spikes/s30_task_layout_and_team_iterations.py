"""s30 (read-only): three questions phase 2 of the work item form needs.

1. The scratch Task's `xmlForm`: what exactly labels the Description group
   and its control, so the form stops printing "Description" twice.
2. `work/teamsettings/iterations` without `$timeframe`: the whole team
   iteration list for the iteration picker's Team section.
3. `graph/descriptors/{project}`: does the project *name* work, or only the
   project id (the people search is scoped with it)?
"""
import os, sys, urllib.parse
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)

print('=== 1. Task xmlForm, Details tab ===')
s, h, wt = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/Task?api-version=7.1')
xml = wt.get('xmlForm') if isinstance(wt, dict) else None
print('HTTP', s, 'xmlForm', len(xml or ''), 'bytes')
if xml:
    root = ET.fromstring(xml)
    layout = root.find('.//WebLayout')
    if layout is None:
        layout = root.find('Layout')
    tab = None
    for t in layout.iter('Tab'):
        if (t.get('Label') or '').lower() == 'details':
            tab = t
            break

    def walk(el, depth):
        for child in el:
            if child.tag == 'Control':
                print('  ' * depth + f"Control Field={child.get('FieldName')!r} "
                      f"Label={child.get('Label')!r} Type={child.get('Type')!r}")
            else:
                print('  ' * depth + f"{child.tag} Label={child.get('Label')!r} "
                      f"PercentWidth={child.get('PercentWidth')!r}")
                walk(child, depth + 1)

    if tab is not None:
        walk(tab, 0)

print()
print('=== 1b. the Description field name as the type reports it ===')
s, h, fields = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/Task/fields/System.Description'
                   '?$expand=All&api-version=7.1')
print('HTTP', s, {k: fields.get(k) for k in ('referenceName', 'name', 'alwaysRequired',
                                             'helpText')} if isinstance(fields, dict) else fields)

print()
print('=== 2. team iterations without $timeframe ===')
s, h, teams = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
project_id = teams.get('id') if isinstance(teams, dict) else None
team = (teams.get('defaultTeam') or {}).get('id') if isinstance(teams, dict) else None
print('project id', project_id, 'default team', team)
s, h, iters = get(f'{ORG_URL}/{P}/{team}/_apis/work/teamsettings/iterations?api-version=7.1')
print('HTTP', s, 'count', iters.get('count') if isinstance(iters, dict) else None)
for it in (iters.get('value') or [])[:20]:
    print('  ', {k: it.get(k) for k in ('id', 'name', 'path')},
          'attributes', it.get('attributes'))

print()
print('=== 3. graph/descriptors: project name vs project id ===')
for label, key in (('name', PROJECT), ('id', project_id)):
    s, h, d = get(f'https://vssps.dev.azure.com/{ORG_URL.rsplit("/", 1)[-1]}'
                  f'/_apis/graph/descriptors/{urllib.parse.quote(str(key))}'
                  '?api-version=7.1-preview.1')
    value = d.get('value') if isinstance(d, dict) else str(d)[:120]
    print(f'  by {label}: HTTP {s} ->', value)

dump_costs()
