"""s57 (read-only): the Dashboard REST API catalog, for the Home tab's
Dashboards segment (NEXT-STEPS item 24, research/19).

Questions:

  A  does `{project}/{team}/_apis/dashboard/dashboards` answer at
     api-version=7.1 (non-preview) and 7.1-preview.3, and what shape?
  B  what does the project-scope route `{project}/_apis/dashboard/dashboards`
     return vs the team-scope route (project dashboards vs team dashboards)?
  C  how many dashboards / widgets per project and team in puremedia, and
     which widget contributionIds are in use (counts only; client names are
     redacted in the result file except for the scratch project).
  D  the widget type catalog: `{project}/_apis/dashboard/widgettypes?$scope=…`
     at collection_User and project_Team.
  E  rate-limit costs.

GETs only; nothing is written anywhere.
"""
import json, os, re, sys, urllib.parse
from collections import Counter

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402

OUT = []
SCRATCH = 'DevOps Mobile App'


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def q(s):
    return urllib.parse.quote(str(s), safe='')


# Projects and teams the PAT can see.
st, _, body = get(f'{ORG_URL}/_apis/projects?api-version=7.1')
projects = [(pr['id'], pr['name']) for pr in body.get('value', [])] if st == 200 else []
p('projects:', st, len(projects))

teams_by_project = {}
for pid, pname in projects:
    st, _, body = get(f'{ORG_URL}/_apis/projects/{q(pname)}/teams?api-version=7.1')
    teams_by_project[pname] = [(t['id'], t['name']) for t in body.get('value', [])] if st == 200 else []

# A: api-version variants on the scratch project's team route.
p('\n=== A  api-version variants (scratch project, team scope) ===')
scratch_teams = teams_by_project.get(SCRATCH, [])
if scratch_teams:
    tid, tname = scratch_teams[0]
    for api in ('7.1', '7.1-preview.3', '7.1-preview.2', '7.2-preview.3'):
        url = f'{ORG_URL}/{q(SCRATCH)}/{q(tid)}/_apis/dashboard/dashboards?api-version={api}'
        st, hdrs, body = get(url)
        keys = sorted(body.keys()) if isinstance(body, dict) else type(body).__name__
        p(f'  api-version={api}: HTTP {st} keys={keys}')
        if st != 200:
            p('   ', short(body, 400))

# B/C: dashboards per project (project scope and team scope).
p('\n=== B/C  dashboards per project and per team ===')
contrib_counter = Counter()
all_dashboards = {}  # (project, scope, team) -> list of dashboards
for pid, pname in projects:
    is_scratch = pname == SCRATCH
    label = pname if is_scratch else f'<project {pid[:8]}>'
    url = f'{ORG_URL}/{q(pname)}/_apis/dashboard/dashboards?api-version=7.1-preview.3'
    st, _, body = get(url)
    dl = body.get('dashboardEntries') or body.get('value') or [] if isinstance(body, dict) else []
    p(f'\n{label} project-scope: HTTP {st} top-level keys={sorted(body.keys()) if isinstance(body, dict) else body}')
    all_dashboards[(pname, 'project', None)] = dl
    for d in dl:
        name = d.get('name') if is_scratch else '<name>'
        p(f'   id={d.get("id")} name={name} scope={d.get("dashboardScope")} widgets={len(d.get("widgets") or [])} refresh={d.get("refreshInterval")} pos={d.get("position")} groupId={d.get("groupId")} owner={d.get("ownerId")} keys={sorted(d.keys())}')
    for tid, tname in teams_by_project[pname]:
        url = f'{ORG_URL}/{q(pname)}/{q(tid)}/_apis/dashboard/dashboards?api-version=7.1-preview.3'
        st, _, body = get(url)
        dl = body.get('dashboardEntries') or body.get('value') or [] if isinstance(body, dict) else []
        p(f'  team {"<team>" if not is_scratch else tname} team-scope: HTTP {st} keys={sorted(body.keys()) if isinstance(body, dict) else body} dashboards={len(dl)}')
        all_dashboards[(pname, 'team', tid)] = dl
        for d in dl:
            name = d.get('name') if is_scratch else '<name>'
            p(f'   id={d.get("id")} name={name} scope={d.get("dashboardScope")} widgets={len(d.get("widgets") or [])} refresh={d.get("refreshInterval")} pos={d.get("position")} groupId={d.get("groupId")} owner={d.get("ownerId")}')
            # the list entry may or may not carry widgets; fetch the dashboard itself
            st2, _, full = get(f'{ORG_URL}/{q(pname)}/{q(tid)}/_apis/dashboard/dashboards/{d.get("id")}?api-version=7.1-preview.3')
            widgets = full.get('widgets') or [] if isinstance(full, dict) else []
            p(f'     GET by id: HTTP {st2} keys={sorted(full.keys()) if isinstance(full, dict) else full} widgets={len(widgets)}')
            c = Counter(w.get('contributionId') for w in widgets)
            contrib_counter.update(c)
            for cid, n in sorted(c.items()):
                p(f'       {n:2d} x {cid}')

p('\n=== C  contributionIds across the org (counts) ===')
for cid, n in contrib_counter.most_common():
    p(f'  {n:3d}  {cid}')

# B': project-scope route at preview.2 vs preview.3, scratch project
p('\n=== B\'  project-scope route, preview.2 vs preview.3 (scratch) ===')
for api in ('7.1-preview.2', '7.1-preview.3'):
    st, _, body = get(f'{ORG_URL}/{q(SCRATCH)}/_apis/dashboard/dashboards?api-version={api}')
    p(f'  {api}: HTTP {st}\n{short(body, 3000)}')
if scratch_teams:
    st, _, body = get(f'{ORG_URL}/{q(SCRATCH)}/{q(scratch_teams[0][0])}/_apis/dashboard/dashboards?api-version=7.1-preview.2')
    p(f'  team-scope preview.2: HTTP {st}\n{short(body, 3000)}')

# D: widget type catalog at both scopes.
p('\n=== D  widget type catalog ===')
catalog = {}
for scope in ('collection_User', 'project_Team'):
    url = f'{ORG_URL}/{q(SCRATCH)}/_apis/dashboard/widgettypes?$scope={scope}&api-version=7.1-preview.1'
    st, _, body = get(url)
    wt = body.get('widgetTypes') or body.get('value') or [] if isinstance(body, dict) else []
    p(f'\nscope={scope}: HTTP {st} keys={sorted(body.keys()) if isinstance(body, dict) else short(body, 300)} types={len(wt)}')
    catalog[scope] = wt
    for w in sorted(wt, key=lambda x: x.get('name') or ''):
        p(f'  {w.get("name")!r:40} contributionId={w.get("contributionId")} visible={w.get("isVisibleFromCatalog")} config={w.get("configurationContributionId")} sizes={[(s.get("rowSpan"), s.get("columnSpan")) for s in (w.get("allowedSizes") or [])]} keys={sorted(w.keys())}')
# non-preview vs preview for widget types
for api in ('7.1-preview.1', '7.1'):
    st, _, body = get(f'{ORG_URL}/{q(SCRATCH)}/_apis/dashboard/widgettypes?$scope=project_Team&api-version={api}')
    p(f'widgettypes api-version={api}: HTTP {st}')
# one widget type by contribution id
st, _, body = get(f'{ORG_URL}/{q(SCRATCH)}/_apis/dashboard/widgettypes/ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget?api-version=7.1-preview.1')
p(f'widgettypes/{{contributionId}}: HTTP {st}\n{short(body, 2500)}')

p('\n=== raw catalog (project_Team) ===')
p(json.dumps(catalog.get('project_Team'), indent=1))

write_result('s57_dashboards_catalog/s57_dashboards_catalog.md', '\n'.join(OUT) + dump_costs())
