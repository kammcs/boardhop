"""Dynamic-forms spike: work item types, states, and per-field rules with $expand=All
(allowedValues, alwaysRequired, dependentFields), plus two validateOnly dry runs that save nothing.
"""
from lib import *

P = urllib.parse.quote(DEFAULT_PROJECT)
out = ['# Spike — Work item type and field metadata for dynamic forms', f'Org: {ORG_URL} · Project: {DEFAULT_PROJECT}', '']

s, h, types = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes?api-version=7.1')
tlist = types.get('value', []) if isinstance(types, dict) else []
out += [f'## workitemtypes — HTTP {s}, {len(tlist)} types', '| type | states | fields | icon | color |', '|---|---|---|---|---|']
for t in tlist:
    out.append(f'| {t["name"]} | {[x["name"] for x in t.get("states", [])]} | {len(t.get("fields", []))} | {(t.get("icon") or {}).get("id")} | {t.get("color")} |')

pick = next((t['name'] for t in tlist if t['name'] in ('User Story', 'Product Backlog Item', 'Issue', 'Bug')), tlist[0]['name'] if tlist else None)
if pick:
    s, h, tf = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/{urllib.parse.quote(pick)}/fields?$expand=All&api-version=7.1')
    flist = tf.get('value', []) if isinstance(tf, dict) else []
    out += ['', f'## workitemtypes/{pick}/fields?$expand=All — HTTP {s}, {len(flist)} fields',
            '| referenceName | alwaysRequired | allowedValues | dependentFields | defaultValue |', '|---|---|---|---|---|']
    for f in flist:
        av = f.get('allowedValues') or []
        sample = ' e.g. ' + json.dumps(av[:3])[:80] if av else ''
        out.append(f'| {f["referenceName"]} | {f.get("alwaysRequired")} | {len(av)}{sample} | {[d.get("referenceName") for d in f.get("dependentFields", [])]} | {str(f.get("defaultValue"))[:30]} |')

    s, h, st = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/{urllib.parse.quote(pick)}/states?api-version=7.1')
    out += ['', f'## states for {pick} — HTTP {s}', '```json', short(st, 800), '```']

    wiql = {'query': f"SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject]=@project AND [System.WorkItemType]='{pick}' ORDER BY [System.ChangedDate] DESC"}
    s, h, q = post(f'{ORG_URL}/{P}/_apis/wit/wiql?$top=1&api-version=7.1', wiql)
    ids = [w['id'] for w in q.get('workItems', [])] if isinstance(q, dict) else []
    if ids:
        wid = ids[0]
        s, h, wi = get(f'{ORG_URL}/_apis/wit/workitems/{wid}?fields=System.Rev,System.State,System.Title&api-version=7.1')
        rev = wi.get('rev')
        # dry run 1: invalid state → expect a rules-engine error, nothing saved
        s, h, r = patch(f'{ORG_URL}/_apis/wit/workitems/{wid}?validateOnly=true&api-version=7.1',
                        [{'op': 'test', 'path': '/rev', 'value': rev}, {'op': 'add', 'path': '/fields/System.State', 'value': 'ThisStateDoesNotExist'}])
        out += ['', f'## validateOnly=true dry run on #{wid} (rev {rev}) with an invalid state — HTTP {s} (nothing saved)', '```json', short(r, 700), '```']
        # dry run 2: stale rev → expect the concurrency failure shape
        s, h, r = patch(f'{ORG_URL}/_apis/wit/workitems/{wid}?validateOnly=true&api-version=7.1',
                        [{'op': 'test', 'path': '/rev', 'value': (rev or 0) + 999}, {'op': 'add', 'path': '/fields/System.Title', 'value': wi['fields']['System.Title']}])
        out += ['', f'## validateOnly=true with a stale rev (concurrency check) — HTTP {s}', '```json', short(r, 500), '```']
out.append(dump_costs())
write_result('s11_workitem_type_fields.md', '\n'.join(out))
