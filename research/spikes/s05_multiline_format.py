"""Spike 5: does multilineFieldsFormat appear on work item reads, and at which api-version?

Document 01 says the property exists only in the 7.2-preview schema; the anonymous probe
showed wit/workitems routes at 7.2-preview.2 and .3 but not .1.
Note: WIQL cannot filter on long-text fields with <>, so we take recent items and filter client-side.
"""
from lib import *

P = urllib.parse.quote(DEFAULT_PROJECT)
out = ['# Spike 5 — multilineFieldsFormat on read', f'Org: {ORG_URL} · Project: {DEFAULT_PROJECT}', '']

wiql = {'query': "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject]=@project AND [System.WorkItemType] IN ('User Story','Bug','Tech Task','Feature') ORDER BY [System.ChangedDate] DESC"}
s, h, b = post(f'{ORG_URL}/{P}/_apis/wit/wiql?$top=60&api-version=7.1', wiql)
ids = [w['id'] for w in b.get('workItems', [])] if isinstance(b, dict) else []
out.append(f'WIQL HTTP {s}, {len(ids)} recent work items')
if not ids:
    out += ['```', short(b, 400), '```']

for v in ['7.1', '7.2-preview.2', '7.2-preview.3', '7.2-preview.4']:
    if not ids:
        break
    s, h, b = get(f'{ORG_URL}/_apis/wit/workitems?ids={",".join(map(str, ids[:60]))}&fields=System.Id,System.Title,System.Description,Microsoft.VSTS.TCM.ReproSteps,Microsoft.VSTS.Common.AcceptanceCriteria&api-version={v}')
    out += [f'## api-version={v}', f'HTTP {s}']
    if isinstance(b, dict) and 'value' in b:
        keys = sorted({k for w in b['value'] for k in w.keys()})
        out.append(f'top-level keys on WorkItem: `{keys}`')
        fmts = {w['id']: w.get('multilineFieldsFormat') for w in b['value'] if w.get('multilineFieldsFormat')}
        out.append(f'items carrying multilineFieldsFormat: {len(fmts)} of {len(b["value"])}')
        for i, f in list(fmts.items())[:8]:
            out.append(f'- {i}: `{json.dumps(f)}`')
        withdesc = [w for w in b['value'] if (w['fields'].get('System.Description') or '').strip()]
        html = sum(1 for w in withdesc if '<' in w['fields']['System.Description'])
        out.append(f'items with a description: {len(withdesc)}; HTML-looking (contains "<"): {html}; other: {len(withdesc) - html}')
        for w in [w for w in withdesc if '<' not in w['fields']['System.Description']][:3]:
            out.append(f'- non-HTML description sample #{w["id"]}: `{w["fields"]["System.Description"][:120]!r}`')
    else:
        out += ['```', short(b, 400), '```']
    out.append('')

# single-item GET with $expand=all at 7.2-preview.3, to see whether the property appears only with expand
if ids:
    s, h, one = get(f'{ORG_URL}/_apis/wit/workitems/{ids[0]}?$expand=all&api-version=7.2-preview.3')
    out += [f'## single GET #{ids[0]} with $expand=all at 7.2-preview.3 — HTTP {s}',
            f'top-level keys: `{sorted(one.keys()) if isinstance(one, dict) else one}`',
            f'multilineFieldsFormat: `{one.get("multilineFieldsFormat") if isinstance(one, dict) else None}`', '']
out.append(dump_costs())
write_result('s05_multiline_format.md', '\n'.join(out))
