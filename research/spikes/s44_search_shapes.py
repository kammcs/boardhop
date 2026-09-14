"""s44: read-only. The Azure DevOps Search API shapes the search feature
(research/15) builds on: work item search project-scoped and org-wide with
facets, the highlight payload, $top/$skip/$orderBy, the empty answer, and
code search org-wide (the app only ever called it per project). Reads only;
the scratch project supplies the project-scoped calls, the org-wide ones are
listing hits across client projects and are recorded by count and field
names only — no titles or snippets reach the result file."""
import json, os, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, post, dump_costs, write_result, short  # noqa: E402

SEARCH = f'https://almsearch.dev.azure.com/{ORG}'
P = 'DevOps%20Mobile%20App'
PNAME = 'DevOps Mobile App'
out = ['# Spike s44 — Search API shapes (read-only)', '']


def keys(d, depth=0):
    if not isinstance(d, dict):
        return type(d).__name__
    return {k: (keys(v, depth + 1) if depth < 2 else type(v).__name__) for k, v in d.items()}


def wi(title, url, body):
    s, h, r = post(url, body)
    out.append(f'## {title} — HTTP {s}')
    out.append('')
    if not isinstance(r, dict):
        out.append(short(r, 600)); out.append(''); return r
    out.append(f'- count: {r.get("count")}  results: {len(r.get("results", []))}  infoCode: {r.get("infoCode")}')
    out.append(f'- top-level keys: {sorted(r.keys())}')
    facets = r.get('facets') or {}
    out.append(f'- facets: {{ {", ".join(f"{k}: {len(v)}" for k, v in facets.items())} }}')
    for k, v in facets.items():
        out.append(f'  - {k}: {[ (f.get("name"), f.get("resultCount")) for f in v[:8] ]}')
    if r.get('results'):
        first = r['results'][0]
        out.append(f'- result keys: {sorted(first.keys())}')
        out.append(f'- result.fields keys: {sorted((first.get("fields") or {}).keys())}')
        hits = first.get('hits') or []
        out.append(f'- hits: {len(hits)} entries; fieldReferenceNames: {sorted({h.get("fieldReferenceName") for h in hits})}')
        if hits:
            out.append(f'- hit keys: {sorted(hits[0].keys())}; highlight count: {len(hits[0].get("highlights") or [])}')
        out.append(f'- project keys: {sorted((first.get("project") or {}).keys())}')
    out.append('')
    return r


base = {'searchText': 'boardhop', '$skip': 0, '$top': 25, 'includeFacets': True}
wi('work items, project-scoped (scratch)', f'{SEARCH}/{P}/_apis/search/workitemsearchresults?api-version=7.1',
   dict(base, filters={'System.TeamProject': [PNAME]}))
wi('work items, org-wide, facets on', f'{SEARCH}/_apis/search/workitemsearchresults?api-version=7.1',
   dict(base, searchText='test'))
wi('work items, org-wide, filtered to a type + state', f'{SEARCH}/_apis/search/workitemsearchresults?api-version=7.1',
   dict(base, searchText='test', filters={'System.WorkItemType': ['Task'], 'System.State': ['Active']}))
wi('work items, $orderBy changed date desc', f'{SEARCH}/{P}/_apis/search/workitemsearchresults?api-version=7.1',
   dict(base, filters={'System.TeamProject': [PNAME]}, **{'$orderBy': [{'field': 'system.changeddate', 'sortOrder': 'DESC'}]}))
wi('work items, $top 200 (cap?)', f'{SEARCH}/_apis/search/workitemsearchresults?api-version=7.1',
   dict(base, searchText='a', **{'$top': 200}))
wi('work items, $top 201 (over the cap?)', f'{SEARCH}/_apis/search/workitemsearchresults?api-version=7.1',
   dict(base, searchText='a', **{'$top': 201}))
wi('work items, no hits', f'{SEARCH}/{P}/_apis/search/workitemsearchresults?api-version=7.1',
   dict(base, searchText='zzqxv_nothing_here', filters={'System.TeamProject': [PNAME]}))
wi('work items, 2-character term', f'{SEARCH}/{P}/_apis/search/workitemsearchresults?api-version=7.1',
   dict(base, searchText='bo', filters={'System.TeamProject': [PNAME]}))

# Code search org-wide (the app only calls it per project today).
s, h, r = post(f'{SEARCH}/_apis/search/codesearchresults?api-version=7.1',
               {'searchText': 'TODO', '$skip': 0, '$top': 10, 'includeFacets': True})
out.append(f'## code, org-wide, facets on — HTTP {s}'); out.append('')
if isinstance(r, dict):
    out.append(f'- count: {r.get("count")}  results: {len(r.get("results", []))}  infoCode: {r.get("infoCode")}')
    out.append(f'- facets: {{ {", ".join(f"{k}: {len(v)}" for k, v in (r.get("facets") or {}).items())} }}')
    if r.get('results'):
        out.append(f'- result keys: {sorted(r["results"][0].keys())}')
        out.append(f'- project keys: {sorted((r["results"][0].get("project") or {}).keys())}')
else:
    out.append(short(r, 400))
out.append('')

# Wiki, shape only, for the record (out of v1).
s, h, r = post(f'{SEARCH}/{P}/_apis/search/wikisearchresults?api-version=7.1',
               {'searchText': 'boardhop', '$skip': 0, '$top': 5, 'filters': {'Project': [PNAME]}})
out.append(f'## wiki, project-scoped — HTTP {s}'); out.append('')
out.append(f'- count: {r.get("count") if isinstance(r, dict) else short(r, 300)}')
if isinstance(r, dict) and r.get('results'):
    out.append(f'- result keys: {sorted(r["results"][0].keys())}')
out.append('')

out.append(dump_costs())
write_result('s44_search_shapes', '\n'.join(out))
print('\n'.join(l for l in out if l.startswith('## ') or l.startswith('- count') or l.startswith('- facets') or 'keys' in l or 'hits' in l or 'HTTP' in l))
