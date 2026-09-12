"""s35 (read-only): read back what the phase 5 walkthrough did in the scratch
project — the relations of the items the Links and Attachments pages touched
(#15540, #15546, #15547, #15550) and anything titled `[phase5]`, with each
relation's rel, target or file name, `attributes.resourceSize` and the item's
`System.AttachedFileCount`.

Takes ids from the command line, or uses the walkthrough's own set.
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, dump_costs, write_result  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)

fixed = [int(a) for a in sys.argv[1:] if a.isdigit()] or [15540, 15546, 15547, 15550]

wiql = ("SELECT [System.Id] FROM WorkItems "
        "WHERE [System.TeamProject] = @project "
        "AND [System.Title] CONTAINS '[phase5]' "
        "ORDER BY [System.Id] ASC")
s, h, res = post(f'{ORG_URL}/{P}/_apis/wit/wiql?api-version=7.1', {'query': wiql})
found = [w['id'] for w in (res.get('workItems') or [])] if isinstance(res, dict) else []
print('WIQL', s, found)

ids = fixed + [i for i in found if i not in fixed]
out = ['# Spike s35 - relations after the phase 5 walkthrough', '',
       f'WIQL `[phase5]` HTTP {s}: {found}', f'ids read: {ids}', '']

s, h, items = get(f'{ORG_URL}/{P}/_apis/wit/workitems'
                  f'?ids={",".join(str(i) for i in ids)}&$expand=all&api-version=7.1')
out.append(f'batch HTTP {s}')
for it in (items.get('value') or []) if isinstance(items, dict) else []:
    f = it.get('fields') or {}
    out += [
        '',
        f"#{it['id']} rev {it['rev']} {f.get('System.WorkItemType')} - {f.get('System.Title')!r}",
        f"  state: {f.get('System.State')} | AttachedFileCount:"
        f" {f.get('System.AttachedFileCount')} | RelatedLinkCount: {f.get('System.RelatedLinkCount')}",
    ]
    for i, r in enumerate(it.get('relations') or []):
        rel = r.get('rel')
        url = r.get('url') or ''
        attrs = r.get('attributes') or {}
        target = url.rsplit('/', 1)[-1]
        shown = {k: attrs[k] for k in ('name', 'resourceSize', 'comment') if k in attrs}
        out.append(f'  [{i}] {rel} -> {target} {shown if shown else ""}')
    desc = (f.get('System.Description') or '')
    if '_apis/wit/attachments' in desc:
        out.append('  description embeds an attachment image')
    print(out[-3] if len(out) > 3 else '')

body = '\n'.join(out)
print(body)
write_result('s35-phase5-links-attachments.md', body)
dump_costs()
