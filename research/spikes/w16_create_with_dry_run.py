"""w16: what does creating a work item look like from the form's side?
Scratch project only. Dry runs (`validateOnly=true`) with a missing
title, an illegal picklist value and a bad state, then a real create of a
Task with a parent link, tags, a Markdown description and a second
create through a template-like field map; reads both back with
relations. Leaves the items in place for the emulator walkthrough."""
import json, os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, call, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P, wi_get  # noqa: E402

PARENT = 15503
out = ['# Spike w16 — create with dry run (scratch project)', '']

s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == SCRATCH, proj
s, h, parent = wi_get(PARENT)
assert parent['fields']['System.TeamProject'] == SCRATCH, 'parent is not in the scratch project'
ptype = parent['fields']['System.WorkItemType']
print(f'parent #{PARENT} is a {ptype}: {parent["fields"]["System.Title"]!r}')
out += [f'parent #{PARENT} ({ptype}): {parent["fields"]["System.Title"]!r}, area {parent["fields"]["System.AreaPath"]!r}, iteration {parent["fields"]["System.IterationPath"]!r}', '']


def create(wtype, ops, validate=False, expand=''):
    url = f'{ORG_URL}/{P}/_apis/wit/workitems/${urllib.parse.quote(wtype)}?api-version=7.1' + ('&validateOnly=true' if validate else '') + expand
    return call('POST', url, ops, headers={'Content-Type': 'application/json-patch+json'})


def errors(body):
    if not isinstance(body, dict):
        return body
    cp = body.get('customProperties') or {}
    rv = cp.get('RuleValidationErrors')
    return {'message': (body.get('message') or '')[:300], 'typeKey': body.get('typeKey'), 'errorCode': body.get('errorCode'),
            'RuleValidationErrors': rv, 'customPropertyKeys': sorted(cp.keys())}


def f(path, value):
    return {'op': 'add', 'path': f'/fields/{path}', 'value': value}


# --- dry runs ---
cases = [
    ('missing title', 'Task', [f('System.Description', 'no title')]),
    ('illegal priority', 'Task', [f('System.Title', '[spike] w16 dry run'), f('Microsoft.VSTS.Common.Priority', 9)]),
    ('bad state', 'Task', [f('System.Title', '[spike] w16 dry run'), f('System.State', 'Done')]),
    ('unknown field', 'Task', [f('System.Title', '[spike] w16 dry run'), f('Custom.DoesNotExist', 1)]),
    ('valid task', 'Task', [f('System.Title', '[spike] w16 dry run valid'), f('System.Tags', 'spike; w16')]),
    ('valid bug, no repro', 'Bug', [f('System.Title', '[spike] w16 dry run bug')]),
]
out += ['## Dry runs (`validateOnly=true`)', '']
for label, wtype, ops in cases:
    s, h, body = create(wtype, ops, validate=True)
    summary = errors(body) if s >= 400 else {'id': body.get('id'), 'rev': body.get('rev'), 'state': (body.get('fields') or {}).get('System.State'),
                                             'fieldCount': len(body.get('fields') or {}), 'keys': sorted(body.keys()),
                                             'defaults': {k: v for k, v in (body.get('fields') or {}).items() if k in ('System.State', 'System.Reason', 'System.AreaPath', 'System.IterationPath', 'Microsoft.VSTS.Common.Priority', 'Microsoft.VSTS.Common.Severity', 'System.CreatedBy', 'System.AssignedTo')}}
    print(f'  {label:22s} {wtype:5s} -> {s} {json.dumps(summary, default=str)[:300]}')
    out += [f'### {label} ({wtype}) — HTTP {s}', '```json', short(summary, 1200), '```', '']

# --- real create: Task under the parent with tags and a Markdown description ---
ops = [
    f('System.Title', '[spike] w16 child task with links'),
    f('System.Description', '# From the spike\n\nCreated by **w16** with a parent link, tags and Markdown.\n\n- one\n- two'),
    {'op': 'add', 'path': '/multilineFieldsFormat/System.Description', 'value': 'Markdown'},
    f('System.Tags', 'spike; w16; boardhop'),
    f('System.AreaPath', parent['fields']['System.AreaPath']),
    f('System.IterationPath', parent['fields']['System.IterationPath']),
    f('Microsoft.VSTS.Common.Priority', 3),
    f('Microsoft.VSTS.Scheduling.RemainingWork', 2.5),
    {'op': 'add', 'path': '/relations/-', 'value': {'rel': 'System.LinkTypes.Hierarchy-Reverse', 'url': parent['url'], 'attributes': {'comment': 'w16 parent link'}}},
]
s, h, dry = create('Task', ops, validate=True)
print('real create dry run:', s, errors(dry) if s >= 400 else 'ok')
out += [f'## Real create — dry run HTTP {s}', '```json', short(errors(dry) if s >= 400 else {'ok': True, 'relations': dry.get('relations')}, 600), '```', '']
s, h, created = create('Task', ops, expand='&$expand=relations')
print('real create:', s, created.get('id') if isinstance(created, dict) else str(created)[:200])
if s in (200, 201):
    wid = created['id']
    rel = created.get('relations')
    out += [f'## Real create — HTTP {s}: #{wid}', '', f'rev {created.get("rev")}, state {created["fields"].get("System.State")}, format {created.get("multilineFieldsFormat")}, tags {created["fields"].get("System.Tags")!r}', '',
            'relations: ' + json.dumps(rel)[:600], '']
    s, h, back = get(f'{ORG_URL}/_apis/wit/workitems/{wid}?$expand=relations&api-version=7.1')
    print('  read back:', s, back.get('multilineFieldsFormat'), [r.get('rel') for r in back.get('relations') or []], back['fields'].get('System.Parent'))
    out += [f'read back — HTTP {s}: multilineFieldsFormat {back.get("multilineFieldsFormat")}, relations {[r.get("rel") for r in back.get("relations") or []]}, System.Parent {back["fields"].get("System.Parent")}', '']
else:
    out += [f'## Real create — HTTP {s}', '```json', short(errors(created), 800), '```', '']

# --- second create: a Bug straight into a non-initial state with a "template" field map ---
template = {'System.Title': '[spike] w16 bug from a template', 'Microsoft.VSTS.Common.Severity': '2 - High',
            'Microsoft.VSTS.Common.Priority': 1, 'System.Tags': 'spike; template', 'Microsoft.VSTS.TCM.ReproSteps': '<ol><li>Open the app</li><li>Tap New</li></ol>'}
ops = [f(k, v) for k, v in template.items()] + [f('System.State', 'Active')]
s, h, bug = create('Bug', ops, validate=True)
print('bug in Active (dry):', s, errors(bug) if s >= 400 else 'ok')
out += [f'## Bug created directly as Active with template fields — dry run HTTP {s}', '```json', short(errors(bug) if s >= 400 else {'ok': True, 'state': bug['fields'].get('System.State'), 'reason': bug['fields'].get('System.Reason')}, 600), '```', '']
s, h, bug = create('Bug', ops)
print('bug in Active:', s, bug.get('id') if isinstance(bug, dict) else str(bug)[:200])
if s in (200, 201):
    out += [f'created #{bug["id"]}: state {bug["fields"].get("System.State")}, reason {bug["fields"].get("System.Reason")!r}, severity {bug["fields"].get("Microsoft.VSTS.Common.Severity")!r}', '']
else:
    out += ['```json', short(errors(bug), 600), '```', '']

out.append(dump_costs())
write_result('w16_create_with_dry_run.md', '\n'.join(out))
