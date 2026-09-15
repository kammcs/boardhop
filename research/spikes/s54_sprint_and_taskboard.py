"""s54 (read-only): everything the Sprint / taskboard view needs from Azure DevOps.

Covers research brief R1 questions 1-8 and 10:
  1  team iterations + teamsettings, team resolution when a project has several
  2  sprint work items: iterations/{id}/workitems vs WIQL @CurrentIteration
  3  taskboardcolumns + taskboardworkitems, backlogconfiguration, type categories
  4  ordering (StackRank / BacklogPriority, workitemsorder)
  5  capacities, teamdaysoff, working days, Remaining Work presence
  6  Analytics OData WorkItemSnapshot for a burndown
  7  sprint goal: is there any API for it
  8  backlog levels (work/backlogs, backlogs/{id}/workItems)
 10  rate cost + latency of one realistic taskboard load

Read-only: only GET and the two POSTs that are queries (WIQL, OData is GET).
Nothing is written anywhere. Raw output lands in results/s54_sprint_and_taskboard
which is gitignored.
"""
import os, sys, json, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, post, dump_costs, write_result, short, COST_LOG  # noqa: E402

API = 'api-version=7.1'
OUT = []


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def blk(title):
    p('')
    p('=' * 78)
    p('===', title)
    p('=' * 78)


def q(s):
    return urllib.parse.quote(str(s), safe='')


def keys(obj, n=40):
    return sorted(obj.keys())[:n] if isinstance(obj, dict) else type(obj).__name__


PROJECTS = ['DevOps Mobile App', 'CloudCover 2.0', 'Product', 'Special Projects and AI']
SCRATCH = 'DevOps Mobile App'

# ---------------------------------------------------------------- Q1 teams
blk('Q1a  projects, default team, team list')
project_info = {}
for name in PROJECTS:
    s, h, proj = get(f'{ORG_URL}/_apis/projects/{q(name)}?{API}')
    if s != 200:
        p(f'  {name}: HTTP {s} (skipped)')
        continue
    pid = proj.get('id')
    dt = (proj.get('defaultTeam') or {})
    s2, h2, teams = get(f'{ORG_URL}/_apis/projects/{q(pid)}/teams?{API}')
    rows = teams.get('value') or [] if isinstance(teams, dict) else []
    project_info[name] = {'id': pid, 'defaultTeam': dt.get('id'),
                          'defaultTeamName': dt.get('name'),
                          'teams': [(t.get('id'), t.get('name')) for t in rows]}
    p(f'  {name}: id={pid} defaultTeam={dt.get("name")!r} ({dt.get("id")}) '
      f'teams={len(rows)} process-ish={proj.get("description") is not None}')
    for t in rows[:12]:
        p(f'      team {t.get("name")!r} {t.get("id")}')
    # which process template?
    s3, h3, props = get(f'{ORG_URL}/_apis/projects/{q(pid)}/properties?api-version=7.1-preview.1')
    if s3 == 200:
        pr = {r.get('name'): r.get('value') for r in (props.get('value') or [])}
        p(f'      properties: templateName={pr.get("System.ProcessTemplateType")} '
          f'{ {k: v for k, v in pr.items() if "rocess" in k or "emplate" in k} }')

blk('Q1b  teamsettings + iterations per project default team')
iteration_pick = {}
for name, info in project_info.items():
    team = info['defaultTeam']
    base = f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work'
    s, h, ts = get(f'{base}/teamsettings?{API}')
    p(f'\n  --- {name} / default team ---')
    p(f'  teamsettings HTTP {s} keys={keys(ts)}')
    if s == 200:
        p('  ' + short({k: ts.get(k) for k in
                        ('bugsBehavior', 'workingDays', 'defaultIterationMacro')}, 400))
        for k in ('backlogIteration', 'defaultIteration'):
            v = ts.get(k)
            if isinstance(v, dict):
                p(f'  {k}: ' + short({kk: v.get(kk) for kk in
                                      ('id', 'name', 'path', 'attributes')}, 400))
        p(f'  backlogVisibilities: {ts.get("backlogVisibilities")}')
    for tf in (None, 'current', 'past', 'future'):
        url = f'{base}/teamsettings/iterations?{API}' + (f'&$timeframe={tf}' if tf else '')
        s, h, it = get(url)
        rows = it.get('value') or [] if isinstance(it, dict) else []
        p(f'  iterations $timeframe={tf}: HTTP {s} count={len(rows)}')
        if tf is None and rows:
            p(f'    row keys: {keys(rows[0])}  attributes keys: {keys(rows[0].get("attributes") or {})}')
            for r in rows[:6]:
                a = r.get('attributes') or {}
                p(f'    {r.get("name")!r} path={r.get("path")!r} id={r.get("id")} '
                  f'start={a.get("startDate")} finish={a.get("finishDate")} tf={a.get("timeFrame")}')
            nodated = [r for r in rows if not (r.get('attributes') or {}).get('startDate')]
            p(f'    iterations with NO dates: {len(nodated)} / {len(rows)}'
              + (f' e.g. {nodated[0].get("name")!r} tf={(nodated[0].get("attributes") or {}).get("timeFrame")}'
                 if nodated else ''))
        if tf == 'current' and rows:
            iteration_pick[name] = rows[0]
            p(f'    CURRENT -> {rows[0].get("name")!r} id={rows[0].get("id")}')
    if name not in iteration_pick:
        # fall back to the latest past iteration with dates
        s, h, it = get(f'{base}/teamsettings/iterations?{API}')
        rows = [r for r in (it.get('value') or []) if (r.get('attributes') or {}).get('startDate')]
        if rows:
            iteration_pick[name] = rows[-1]
            p(f'    no current; falling back to {rows[-1].get("name")!r}')

blk('Q1c  do non-default teams see different iterations? (largest project)')
big = max(project_info.items(), key=lambda kv: len(kv[1]['teams']), default=(None, None))
if big[0] and len(big[1]['teams']) > 1:
    name = big[0]
    for tid, tname in big[1]['teams'][:4]:
        s, h, it = get(f'{ORG_URL}/{q(name)}/{q(tid)}/_apis/work/teamsettings/iterations?{API}&$timeframe=current')
        rows = it.get('value') or [] if isinstance(it, dict) else []
        s2, h2, tfv = get(f'{ORG_URL}/{q(name)}/{q(tid)}/_apis/work/teamsettings/teamfieldvalues?{API}')
        p(f'  team {tname!r}: current={[r.get("name") for r in rows]} '
          f'areas={[v.get("value") for v in (tfv.get("values") or [])] if isinstance(tfv, dict) else tfv}')
else:
    p('  every project has a single team; nothing to compare')

# -------------------------------------------------- Q2 sprint work items
blk('Q2  iterations/{id}/workitems vs WIQL')
for name, it in iteration_pick.items():
    info = project_info[name]
    team, iid = info['defaultTeam'], it.get('id')
    p(f'\n  --- {name} / {it.get("name")!r} ({iid}) ---')
    s, h, wi = get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/teamsettings/iterations/{iid}/workitems?{API}')
    p(f'  iterations/{{id}}/workitems HTTP {s} keys={keys(wi)}')
    rels = wi.get('workItemRelations') or [] if isinstance(wi, dict) else []
    p(f'  workItemRelations: {len(rels)}')
    if rels:
        p('  first three rows verbatim:')
        p('  ' + short(rels[:3], 900))
        roots = [r for r in rels if r.get('source') is None]
        kids = [r for r in rels if r.get('source') is not None]
        p(f'  roots (source null) = {len(roots)}; child rows = {len(kids)}; '
          f'rel types = {sorted({str(r.get("rel")) for r in rels})}')
        ids = {r['target']['id'] for r in rels if r.get('target')}
        p(f'  distinct work item ids in the sprint: {len(ids)}')
        it['_ids'] = sorted(ids)
        it['_rels'] = rels
    # WIQL equivalents
    path = it.get('path')
    wiqls = {
        'UNDER @CurrentIteration': "SELECT [System.Id] FROM WorkItems WHERE "
            "[System.TeamProject] = @project AND [System.IterationPath] UNDER @CurrentIteration",
        '= @CurrentIteration(team)': "SELECT [System.Id] FROM WorkItems WHERE "
            "[System.TeamProject] = @project AND [System.IterationPath] = "
            f"@CurrentIteration('{name} \\\\ {project_info[name]['defaultTeamName']}')",
        'UNDER path': "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project "
            f"AND [System.IterationPath] UNDER '{path}'",
        '= path': "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project "
            f"AND [System.IterationPath] = '{path}'",
        'tree query': None,
    }
    for label, text in wiqls.items():
        if text is None:
            continue
        s, h, r = post(f'{ORG_URL}/{q(name)}/_apis/wit/wiql?{API}&$top=500', {'query': text})
        n = len(r.get('workItems') or []) if isinstance(r, dict) else None
        p(f'  WIQL {label:28s} HTTP {s} ids={n}'
          + ('' if s == 200 else ' ' + short(r, 200)))
        if s == 200 and label == 'UNDER path':
            it['_wiql_ids'] = sorted(w['id'] for w in r['workItems'])
    # one-pass tree WIQL (parents + children in one answer)
    tree = ("SELECT [System.Id] FROM WorkItemLinks WHERE "
            f"([Source].[System.IterationPath] UNDER '{path}') AND "
            "([System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward') "
            "MODE (Recursive)")
    s, h, r = post(f'{ORG_URL}/{q(name)}/_apis/wit/wiql?{API}', {'query': tree})
    p(f'  WIQL {"tree (WorkItemLinks)":28s} HTTP {s} '
      f'rel rows={len(r.get("workItemRelations") or []) if isinstance(r, dict) else short(r,160)} '
      f'queryResultType={r.get("queryResultType") if isinstance(r, dict) else ""}')
    # compare the two id sets
    a, b = set(it.get('_ids') or []), set(it.get('_wiql_ids') or [])
    if a or b:
        p(f'  SET COMPARE: iteration/workitems={len(a)} wiql-UNDER-path={len(b)} '
          f'only-in-iteration={len(a - b)} only-in-wiql={len(b - a)}')

# --------------------------------------- Q3 taskboard columns and states
blk('Q3  taskboardcolumns + taskboardworkitems')
for name, it in iteration_pick.items():
    info = project_info[name]
    team, iid = info['defaultTeam'], it.get('id')
    p(f'\n  --- {name} ---')
    for ver in ('7.1-preview.1', '7.1'):
        s, h, tc = get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/taskboardcolumns?api-version={ver}')
        p(f'  taskboardcolumns api-version={ver}: HTTP {s} keys={keys(tc)}')
        if s == 200:
            p(f'  isCustomized={tc.get("isCustomized")} columns={len(tc.get("columns") or [])}')
            p('  ' + short(tc.get('columns'), 1600))
            break
    s, h, tw = get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/taskboardworkitems/{iid}?api-version=7.1-preview.1')
    rows = tw.get('value') or [] if isinstance(tw, dict) else []
    p(f'  taskboardworkitems/{{iterationId}}: HTTP {s} count={len(rows)} keys={keys(tw)}')
    if rows:
        p('  first three rows verbatim:')
        p('  ' + short(rows[:3], 700))
        p(f'  distinct columns in use: {sorted({str(r.get("column")) for r in rows})}')
        p(f'  distinct states in use : {sorted({str(r.get("state")) for r in rows})}')
    it['_taskboard_rows'] = rows

blk('Q3b  backlogconfiguration + workitemtypecategories (task vs requirement)')
for name, info in project_info.items():
    team = info['defaultTeam']
    s, h, bc = get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/backlogconfiguration?{API}')
    p(f'\n  --- {name} --- backlogconfiguration HTTP {s} keys={keys(bc)}')
    if s != 200:
        continue
    for key in ('taskBacklog', 'requirementBacklog'):
        lvl = bc.get(key) or {}
        p(f'  {key}: id={lvl.get("id")} name={lvl.get("name")!r} rank={lvl.get("rank")} '
          f'types={[t.get("name") for t in (lvl.get("workItemTypes") or [])]}')
        p(f'    defaultWorkItemType={(lvl.get("defaultWorkItemType") or {}).get("name")!r} '
          f'color={lvl.get("color")} addPanelFields={[f.get("referenceName") for f in (lvl.get("addPanelFields") or [])]}')
        p(f'    workItemTypeMappedStates: ' + short(lvl.get('workItemTypeMappedStates'), 700))
        p(f'    columnFields: ' + short([c.get('columnFieldReference', {}).get('referenceName')
                                         for c in (lvl.get('columnFields') or [])], 400))
    p(f'  backlogFields.typeFields: ' + short((bc.get('backlogFields') or {}).get('typeFields'), 600))
    p(f'  bugsBehavior={bc.get("bugsBehavior")} hiddenBacklogs={bc.get("hiddenBacklogs")}')
    s, h, cats = get(f'{ORG_URL}/{q(name)}/_apis/wit/workitemtypecategories?{API}')
    if s == 200:
        for c in cats.get('value') or []:
            if c.get('referenceName') in ('Microsoft.TaskCategory', 'Microsoft.RequirementCategory',
                                          'Microsoft.BugCategory'):
                p(f'  category {c.get("referenceName")}: '
                  f'types={[t.get("name") for t in (c.get("workItemTypes") or [])]} '
                  f'default={(c.get("defaultWorkItemType") or {}).get("name")!r}')

# ------------------------------------------------------------ Q4 ordering
blk('Q4  ordering fields on the taskboard')
for name, it in iteration_pick.items():
    ids = (it.get('_ids') or [])[:200]
    if not ids:
        continue
    fields = ['System.Id', 'System.WorkItemType', 'System.State', 'System.Title',
              'System.Parent', 'System.AssignedTo', 'System.IterationPath', 'System.AreaPath',
              'Microsoft.VSTS.Scheduling.RemainingWork', 'Microsoft.VSTS.Scheduling.OriginalEstimate',
              'Microsoft.VSTS.Scheduling.CompletedWork', 'Microsoft.VSTS.Scheduling.StoryPoints',
              'Microsoft.VSTS.Scheduling.Effort', 'Microsoft.VSTS.Common.StackRank',
              'Microsoft.VSTS.Common.BacklogPriority', 'Microsoft.VSTS.Common.Priority']
    s, h, batch = post(f'{ORG_URL}/{q(name)}/_apis/wit/workitemsbatch?{API}',
                       {'ids': ids, 'fields': fields})
    rows = batch.get('value') or [] if isinstance(batch, dict) else []
    p(f'\n  --- {name} --- workitemsbatch({len(ids)}) HTTP {s} rows={len(rows)}')
    if not rows:
        p('  ' + short(batch, 300))
        continue
    present = {}
    for r in rows:
        for k, v in (r.get('fields') or {}).items():
            if v is not None:
                present[k] = present.get(k, 0) + 1
    for f in fields:
        p(f'    {f:52s} set on {present.get(f, 0):4d} / {len(rows)}')
    types = {}
    for r in rows:
        t = (r.get('fields') or {}).get('System.WorkItemType')
        types[str(t)] = types.get(str(t), 0) + 1
    p(f'  types in the sprint: {types}')
    it['_batch'] = rows

blk('Q4b  does the taskboard row/cell order follow StackRank or BacklogPriority?')
for name, it in iteration_pick.items():
    rows = it.get('_taskboard_rows') or []
    rels = it.get('_rels') or []
    batch = {r['id']: (r.get('fields') or {}) for r in (it.get('_batch') or [])}
    if not rels or not batch:
        continue
    order = [r['target']['id'] for r in rels if r.get('source') is None]
    rank = [(i, batch.get(i, {}).get('Microsoft.VSTS.Common.StackRank'),
             batch.get(i, {}).get('Microsoft.VSTS.Common.BacklogPriority')) for i in order[:15]]
    p(f'\n  --- {name} --- roots in the order iterations/workitems returned them, with ranks:')
    for i, sr, bp in rank:
        p(f'    {i}  StackRank={sr}  BacklogPriority={bp}')
    vals = [sr for _, sr, _ in rank if sr is not None]
    p(f'  roots monotonically increasing by StackRank? '
      f'{vals == sorted(vals) if vals else "n/a"} ({len(vals)} ranked of {len(rank)})')
    child_order = [(r['source']['id'], r['target']['id']) for r in rels if r.get('source')]
    p(f'  child rows come grouped under their parent in wire order? '
      f'{[pid for pid, _ in child_order[:12]]}')

# ------------------------------------------------------- Q5 capacity, days off
blk('Q5  capacities, team days off, working days')
for name, it in iteration_pick.items():
    info = project_info[name]
    team, iid = info['defaultTeam'], it.get('id')
    base = f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/teamsettings/iterations/{iid}'
    p(f'\n  --- {name} / {it.get("name")!r} ---')
    s, h, cap = get(f'{base}/capacities?{API}')
    rows = cap.get('value') or [] if isinstance(cap, dict) else (cap if isinstance(cap, list) else [])
    p(f'  capacities HTTP {s} keys={keys(cap)} members={len(rows)}')
    if rows:
        p('  one member verbatim: ' + short(rows[0], 700))
        filled = [r for r in rows if any((a.get('capacityPerDay') or 0) for a in (r.get('activities') or []))]
        p(f'  members with non-zero capacityPerDay: {len(filled)} / {len(rows)}')
        p(f'  activities seen: {sorted({str(a.get("name")) for r in rows for a in (r.get("activities") or [])})}')
        p(f'  members with daysOff: {sum(1 for r in rows if r.get("daysOff"))}')
    s, h, off = get(f'{base}/teamdaysoff?{API}')
    p(f'  teamdaysoff HTTP {s} -> ' + short(off, 400))
    s, h, ts = get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/teamsettings?{API}')
    p(f'  workingDays: {ts.get("workingDays") if isinstance(ts, dict) else ts}')
    # working-day count for the sprint
    a = it.get('attributes') or {}
    p(f'  sprint window: {a.get("startDate")} -> {a.get("finishDate")}')

blk('Q5b  is Remaining Work even on the Task type in each project?')
for name, info in project_info.items():
    for t in ('Task', 'Bug'):
        s, h, f = get(f'{ORG_URL}/{q(name)}/_apis/wit/workitemtypes/{t}/fields/'
                      f'Microsoft.VSTS.Scheduling.RemainingWork?{API}')
        p(f'  {name:26s} {t:5s} RemainingWork: HTTP {s} '
          f'{f.get("name") if isinstance(f, dict) and s == 200 else short(f, 120)}')

# ------------------------------------------------------------ Q6 Analytics
blk('Q6  Analytics OData (burndown)')
_an_order = sorted(iteration_pick.items(),
                   key=lambda kv: (kv[0] == SCRATCH,
                                   not (kv[1].get('attributes') or {}).get('startDate')))
for name, it in _an_order:
    pid = project_info[name]['id']
    an = f'https://analytics.dev.azure.com/{ORG}/{q(name)}/_odata/v4.0-preview'
    s, h, meta = get(f'{an}/$metadata', raw=True)
    p(f'\n  --- {name} --- $metadata HTTP {s} bytes={len(meta) if isinstance(meta, str) else 0}')
    if s != 200:
        p('  ' + short(meta, 400))
        continue
    for ent in ('WorkItemSnapshot', 'WorkItems', 'Iterations', 'BurndownSnapshot'):
        p(f'    entity {ent} declared in metadata: {("EntityType Name=\"" + ent + "\"") in meta or ("EntitySet Name=\"" + ent + "\"") in meta}')
    # Iterations: find the IterationSK for the current sprint
    s, h, iters = get(f'{an}/Iterations?$filter=IterationId%20eq%20{it.get("id")}'
                      '&$select=IterationSK,IterationId,IterationName,IterationPath,StartDate,EndDate')
    p(f'  Iterations by IterationId: HTTP {s} -> ' + short(iters, 500))
    sk = None
    if s == 200 and (iters.get('value') or []):
        sk = iters['value'][0].get('IterationSK')
    if sk:
        _a = it.get('attributes') or {}
        start = (_a.get('startDate') or '2026-01-01T00:00:00Z')[:10]
        end = (_a.get('finishDate') or '2026-12-31T00:00:00Z')[:10]
        url = (f'{an}/WorkItemSnapshot?'
               f'$apply=filter(IterationSK%20eq%20{sk}%20and%20DateValue%20ge%20{start}Z'
               f'%20and%20DateValue%20le%20{end}Z%20and%20WorkItemType%20eq%20%27Task%27)'
               f'/groupby((DateValue),aggregate(StoryPoints%20with%20sum%20as%20SP,'
               f'%24count%20as%20Count,RemainingWork%20with%20sum%20as%20Remaining))')
        t0 = time.time()
        s, h, snap = get(url)
        p(f'  WorkItemSnapshot groupby day: HTTP {s} {round(time.time()-t0,2)}s '
          f'rows={len(snap.get("value") or []) if isinstance(snap, dict) else 0}')
        p('  ' + short(snap, 900))
        # plain shape of one snapshot row
        s2, h2, one = get(f'{an}/WorkItemSnapshot?$filter=IterationSK%20eq%20{sk}&$top=1')
        p(f'  one raw WorkItemSnapshot row: HTTP {s2}')
        if s2 == 200 and (one.get('value') or []):
            p(f'  row fields ({len(one["value"][0])}): {sorted(one["value"][0].keys())}')
    break  # one project is enough to settle the scope question

p('\n  Analytics on the scratch project too (does a tiny project have it?):')
an = f'https://analytics.dev.azure.com/{ORG}/{q(SCRATCH)}/_odata/v4.0-preview'
s, h, r = get(f'{an}/WorkItems?$top=1&$select=WorkItemId,Title,IterationSK')
p(f'  scratch WorkItems: HTTP {s} ' + short(r, 300))

# ----------------------------------------------------------- Q7 sprint goal
blk('Q7  sprint goal: does any API carry one?')
for name, it in list(iteration_pick.items())[:2]:
    info = project_info[name]
    team, iid = info['defaultTeam'], it.get('id')
    s, h, one = get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/teamsettings/iterations/{iid}?{API}')
    p(f'  {name}: teamsettings/iterations/{{id}} HTTP {s} -> ' + short(one, 600))
    # the classification node behind it
    s, h, node = get(f'{ORG_URL}/{q(name)}/_apis/wit/classificationnodes/Iterations'
                     f'?$depth=2&{API}')
    if s == 200:
        def firstnode(n):
            yield n
            for c in n.get('children') or []:
                yield from firstnode(c)
        sample = [n for n in firstnode(node) if n.get('attributes')]
        p(f'    classification node attributes keys seen: '
          f'{sorted({k for n in sample for k in (n.get("attributes") or {})})}')
        p(f'    node keys: {keys(node)}')
    # process-level: is there a "sprint goal" type or field anywhere?
    s, h, fields = get(f'{ORG_URL}/{q(name)}/_apis/wit/fields?{API}')
    if s == 200:
        hits = [f.get('referenceName') for f in (fields.get('value') or [])
                if 'goal' in (f.get('name') or '').lower() or 'goal' in (f.get('referenceName') or '').lower()]
        p(f'    fields whose name contains "goal": {hits}')
    s, h, types = get(f'{ORG_URL}/{q(name)}/_apis/wit/workitemtypes?{API}')
    if s == 200:
        p(f'    work item types: {[t.get("name") for t in (types.get("value") or [])]}')

# --------------------------------------------------------- Q8 backlog levels
blk('Q8  work/backlogs and backlogs/{id}/workItems')
for name, info in list(project_info.items()):
    team = info['defaultTeam']
    base = f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work'
    s, h, bl = get(f'{base}/backlogs?{API}')
    rows = bl.get('value') or [] if isinstance(bl, dict) else []
    p(f'\n  --- {name} --- work/backlogs HTTP {s} count={len(rows)}')
    if rows:
        p(f'  row keys: {keys(rows[0])}')
        for r in rows:
            p(f'    {r.get("id")} {r.get("name")!r} rank={r.get("rank")} '
              f'types={[t.get("name") for t in (r.get("workItemTypes") or [])]} '
              f'isHidden={r.get("isHidden")}')
        req = next((r for r in rows if 'Requirement' in (r.get('id') or '') or
                    (r.get('rank') == 1)), rows[0])
        s, h, items = get(f'{base}/backlogs/{q(req.get("id"))}/workItems?{API}')
        wi = items.get('workItems') or [] if isinstance(items, dict) else []
        p(f'  backlogs/{req.get("id")}/workItems HTTP {s} count={len(wi)} keys={keys(items)}')
        p('  ' + short(wi[:3], 400))
        break

# ------------------------------------------------ Q10 realistic taskboard load
blk('Q10  cost + latency of one taskboard load (client sprint, read-only)')
target = None
for name, it in iteration_pick.items():
    if name != SCRATCH and (it.get('_ids')):
        target = (name, it)
        break
if target:
    name, it = target
    info = project_info[name]
    team, iid = info['defaultTeam'], it.get('id')
    mark = len(COST_LOG)
    t0 = time.time()
    base = f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work'
    get(f'{base}/teamsettings/iterations?{API}&$timeframe=current')
    s, h, wi = get(f'{base}/teamsettings/iterations/{iid}/workitems?{API}')
    ids = sorted({r['target']['id'] for r in (wi.get('workItemRelations') or []) if r.get('target')})
    get(f'{base}/taskboardcolumns?api-version=7.1-preview.1')
    get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/taskboardworkitems/{iid}?api-version=7.1-preview.1')
    get(f'{base}/teamsettings/iterations/{iid}/capacities?{API}')
    for chunk in [ids[i:i + 200] for i in range(0, len(ids), 200)]:
        post(f'{ORG_URL}/{q(name)}/_apis/wit/workitemsbatch?{API}',
             {'ids': chunk, 'fields': ['System.Id', 'System.Title', 'System.WorkItemType',
                                       'System.State', 'System.AssignedTo', 'System.Parent',
                                       'Microsoft.VSTS.Scheduling.RemainingWork',
                                       'Microsoft.VSTS.Common.StackRank']})
    dt = time.time() - t0
    seq = COST_LOG[mark:]
    total = sum(float(c) for *_, c, _, _ in [(m, u, s2, c, d, t) for m, u, s2, c, d, t in seq] if c)
    p(f'  project {name!r}, sprint {it.get("name")!r}, {len(ids)} work items')
    p(f'  {len(seq)} calls, wall clock {round(dt, 2)}s, total X-RateLimit-Cost {round(total, 4)} TSTU')
    for m, u, s2, c, d, t in seq:
        p(f'    {m:5s} {s2} cost={c} {t}s  {u.replace(ORG_URL, "{org}")[:120]}')
else:
    p('  no client sprint with work items found')

blk('Q10b  how much sprint activity do the client projects actually have?')
for name, info in project_info.items():
    team = info['defaultTeam']
    s, h, it = get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/teamsettings/iterations?{API}')
    rows = it.get('value') or [] if isinstance(it, dict) else []
    dated = [r for r in rows if (r.get('attributes') or {}).get('startDate')]
    p(f'\n  {name}: {len(rows)} team iterations, {len(dated)} with dates')
    for r in dated[-4:]:
        iid = r.get('id')
        s2, h2, wi = get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/teamsettings/'
                         f'iterations/{iid}/workitems?{API}')
        n = len({x['target']['id'] for x in (wi.get('workItemRelations') or []) if x.get('target')}) \
            if isinstance(wi, dict) else 0
        s3, h3, cap = get(f'{ORG_URL}/{q(name)}/{q(team)}/_apis/work/teamsettings/'
                          f'iterations/{iid}/capacities?{API}')
        cr = cap.get('value') or [] if isinstance(cap, dict) else []
        filled = sum(1 for c in cr if any((a.get('capacityPerDay') or 0) for a in (c.get('activities') or [])))
        a = r.get('attributes') or {}
        p(f'    {r.get("name")!r:28s} {str(a.get("startDate"))[:10]}..{str(a.get("finishDate"))[:10]} '
          f'tf={str(a.get("timeFrame")):8s} items={n:4d} capacity rows={len(cr)} filled={filled}')

OUT.append(dump_costs('s54 rate-limit cost log'))
write_result('s54_sprint_and_taskboard/raw.md', '\n'.join(OUT))
print(dump_costs('s54 rate-limit cost log'))
