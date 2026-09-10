"""Spike 5b: which $expand value populates multilineFieldsFormat, and at which api-version?
Spike 5 showed the key exists at 7.1 but was only populated on a single GET with $expand=all."""
from lib import *
P = urllib.parse.quote(DEFAULT_PROJECT)
out = ['# Spike 5b — multilineFieldsFormat vs $expand and api-version', f'Org: {ORG_URL} · Project: {DEFAULT_PROJECT}', '']
s, h, q = post(f'{ORG_URL}/{P}/_apis/wit/wiql?$top=5&api-version=7.1', {'query': "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject]=@project AND [System.WorkItemType] IN ('User Story','Bug','Tech Task') ORDER BY [System.ChangedDate] DESC"})
ids = [w['id'] for w in q.get('workItems', [])]
wid = ids[0]
out += ['## Single GET', '| api-version | $expand | fields param | HTTP | multilineFieldsFormat |', '|---|---|---|---|---|']
for v in ['7.1', '7.2-preview.3']:
    for exp in [None, 'none', 'fields', 'relations', 'all']:
        for fp in [None, 'System.Id,System.Description']:
            qs = [f'api-version={v}'] + ([f'$expand={exp}'] if exp else []) + ([f'fields={fp}'] if fp else [])
            s, h, one = get(f'{ORG_URL}/_apis/wit/workitems/{wid}?' + '&'.join(qs))
            mf = one.get('multilineFieldsFormat') if isinstance(one, dict) else one
            out.append(f'| {v} | {exp} | {"yes" if fp else "no"} | {s} | `{json.dumps(mf) if not isinstance(mf, str) else mf[:80]}` |')
out += ['', '## List GET (ids=…) and workitemsbatch', '| call | api-version | $expand | HTTP | items with multilineFieldsFormat populated |', '|---|---|---|---|---|']
for v in ['7.1', '7.2-preview.3']:
    for exp in [None, 'all']:
        qs = [f'ids={",".join(map(str, ids))}', f'api-version={v}'] + ([f'$expand={exp}'] if exp else [])
        s, h, lst = get(f'{ORG_URL}/_apis/wit/workitems?' + '&'.join(qs))
        n = sum(1 for w in lst.get('value', []) if w.get('multilineFieldsFormat')) if isinstance(lst, dict) else lst
        out.append(f'| GET workitems?ids | {v} | {exp} | {s} | {n} of {len(ids)} |')
        body = {'ids': ids, 'errorPolicy': 'omit'} | ({'$expand': exp} if exp else {'fields': ['System.Id', 'System.Description']})
        s, h, lst = post(f'{ORG_URL}/_apis/wit/workitemsbatch?api-version={v}', body)
        n = sum(1 for w in lst.get('value', []) if w.get('multilineFieldsFormat')) if isinstance(lst, dict) else str(lst)[:80]
        out.append(f'| POST workitemsbatch | {v} | {exp or "(fields list)"} | {s} | {n} of {len(ids)} |')
out.append(dump_costs())
write_result('s05b_multiline_expand.md', '\n'.join(out))
