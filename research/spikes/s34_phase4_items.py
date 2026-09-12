"""s34 (read-only): read back everything the phase 4 walkthrough created in
the scratch project — the item from the board column's `+` (state, lane and
board column after the follow-up patch), the child of #15546 (its parent
relation), the item from the team template (tags and priority) and the one
created from a resumed draft. Found by the `[phase4]` title prefix.
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, dump_costs, write_result  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)

wiql = ("SELECT [System.Id] FROM WorkItems "
        "WHERE [System.TeamProject] = @project "
        "AND ([System.Title] CONTAINS '[phase4]' OR [System.Title] CONTAINS '[template]') "
        "ORDER BY [System.Id] ASC")
s, h, res = post(f'{ORG_URL}/{P}/_apis/wit/wiql?api-version=7.1', {'query': wiql})
ids = [w['id'] for w in (res.get('workItems') or [])] if isinstance(res, dict) else []
print('WIQL', s, ids)

out = [f'# Spike s34 — the items the phase 4 walkthrough created', '', f'WIQL HTTP {s}: {ids}', '']
if ids:
    s, h, items = get(f'{ORG_URL}/{P}/_apis/wit/workitems'
                      f'?ids={",".join(str(i) for i in ids)}&$expand=all&api-version=7.1')
    out.append(f'batch HTTP {s}')
    for it in (items.get('value') or []):
        f = it.get('fields') or {}
        lane = {k: v for k, v in f.items() if k.startswith('WEF_')}
        rels = [(r.get('rel'), (r.get('url') or '').rsplit('/', 1)[-1]) for r in (it.get('relations') or [])]
        lines = [
            '',
            f"#{it['id']} rev {it['rev']} {f.get('System.WorkItemType')} — {f.get('System.Title')!r}",
            f"  state: {f.get('System.State')} | reason: {f.get('System.Reason')}"
            f" | priority: {f.get('Microsoft.VSTS.Common.Priority')} | tags: {f.get('System.Tags')!r}",
            f"  area: {f.get('System.AreaPath')} | iteration: {f.get('System.IterationPath')}"
            f" | assigned: {(f.get('System.AssignedTo') or {}).get('displayName')}",
            f"  board fields: {lane}",
            f"  relations: {rels}",
        ]
        print('\n'.join(lines))
        out += lines

# the parent's own view of the child link
s, h, parent = get(f'{ORG_URL}/{P}/_apis/wit/workitems/15546?$expand=relations&api-version=7.1')
kids = [(r.get('rel'), (r.get('url') or '').rsplit('/', 1)[-1]) for r in (parent.get('relations') or [])]
print('15546 relations:', s, kids)
out += ['', f'## #15546 relations — HTTP {s}: {kids}', '']

out.append(dump_costs())
write_result('s34_phase4_items.md', '\n'.join(out))
