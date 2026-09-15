"""s55 (read-only): the questions s54 left open for the Sprint / taskboard view.

  A  the exact 400 bodies: $timeframe=past|future, taskboardworkitems on a
     project whose taskboard was never customized
  B  where the DEFAULT taskboard columns come from when isCustomized=false
     (wit/workitemtypes/{type}/states + state categories)
  C  what taskboardworkitems actually returns (only task-category types?)
  D  the 149-vs-158 delta between iterations/{id}/workitems and WIQL UNDER path
  E  capacities read properly (teamMembers, not value); any sprint with capacity
  F  the 100-iteration list: a cap, or the team's subscription?
  G  @CurrentIteration('[project]\\team') with a single backslash
  H  Analytics: a burndown query that actually returns rows, and its cost
  I  task order inside a parent: StackRank on tasks, workitemsorder parentId
"""
import os, sys, json, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, post, dump_costs, write_result, short  # noqa: E402

API = 'api-version=7.1'
OUT = []


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def blk(t):
    p('')
    p('=' * 78)
    p('===', t)
    p('=' * 78)


def q(s):
    return urllib.parse.quote(str(s), safe='')


CC = 'CloudCover 2.0'
CC_TEAM = 'e2d48804-cec3-492f-9ec7-2a011909dadd'
CC_ITER = '7ec22116-7f07-4635-8970-f75df1023af0'
CC_PATH = 'CloudCover 2.0\\Iteration 106'
SC = 'DevOps Mobile App'
SC_TEAM = '8c08e1e1-7afd-411e-b414-4f9e1d14d8d6'
SC_ITER = 'aa9f2381-54e4-499a-8b8b-e3f981aac964'

# --------------------------------------------------------------- A error bodies
blk('A  the exact 400 bodies')
for tf in ('past', 'future', 'Past', 'completed'):
    s, h, r = get(f'{ORG_URL}/{q(SC)}/{q(SC_TEAM)}/_apis/work/teamsettings/iterations?{API}&$timeframe={tf}')
    p(f'  $timeframe={tf}: HTTP {s} -> {r.get("message") if isinstance(r, dict) else short(r, 200)}')
s, h, r = get(f'{ORG_URL}/{q(SC)}/{q(SC_TEAM)}/_apis/work/taskboardworkitems/{SC_ITER}?api-version=7.1-preview.1')
p(f'\n  taskboardworkitems on a never-customized taskboard: HTTP {s}')
p('  ' + short(r, 700))
s, h, r = get(f'{ORG_URL}/{q(SC)}/{q(SC_TEAM)}/_apis/work/taskboardcolumns?api-version=7.1-preview.1')
p(f'  taskboardcolumns same project: HTTP {s} -> ' + short(r, 300))

# --------------------------------------- B default columns from state categories
blk('B  default taskboard columns when isCustomized=false')
for proj, team in ((SC, SC_TEAM), (CC, CC_TEAM)):
    p(f'\n  --- {proj} ---')
    s, h, bc = get(f'{ORG_URL}/{q(proj)}/{q(team)}/_apis/work/backlogconfiguration?{API}')
    p(f'  backlogconfiguration.workItemTypeMappedStates = '
      + short(bc.get('workItemTypeMappedStates') if isinstance(bc, dict) else bc, 900))
    tb = (bc.get('taskBacklog') or {}) if isinstance(bc, dict) else {}
    for t in [x.get('name') for x in (tb.get('workItemTypes') or [])]:
        s, h, st = get(f'{ORG_URL}/{q(proj)}/_apis/wit/workitemtypes/{q(t)}/states?{API}')
        rows = st.get('value') or [] if isinstance(st, dict) else []
        p(f'  {t!r} states HTTP {s}: ' +
          ', '.join(f'{r.get("name")}[{r.get("category")}]' for r in rows))
    # and for the requirement types (the taskboard rows)
    rb = (bc.get('requirementBacklog') or {}) if isinstance(bc, dict) else {}
    for t in [x.get('name') for x in (rb.get('workItemTypes') or [])]:
        s, h, st = get(f'{ORG_URL}/{q(proj)}/_apis/wit/workitemtypes/{q(t)}/states?{API}')
        rows = st.get('value') or [] if isinstance(st, dict) else []
        p(f'  (row type) {t!r} states: ' +
          ', '.join(f'{r.get("name")}[{r.get("category")}]' for r in rows))

# ------------------------------------------- C what taskboardworkitems contains
blk('C  taskboardworkitems: which items does it return?')
s, h, tw = get(f'{ORG_URL}/{q(CC)}/{q(CC_TEAM)}/_apis/work/taskboardworkitems/{CC_ITER}?api-version=7.1-preview.1')
rows = tw.get('value') or [] if isinstance(tw, dict) else []
tb_ids = [r['workItemId'] for r in rows]
p(f'  rows: {len(rows)} ids={tb_ids}')
s, h, wi = get(f'{ORG_URL}/{q(CC)}/{q(CC_TEAM)}/_apis/work/teamsettings/iterations/{CC_ITER}/workitems?{API}')
rels = wi.get('workItemRelations') or []
all_ids = sorted({r['target']['id'] for r in rels if r.get('target')})
s, h, batch = post(f'{ORG_URL}/{q(CC)}/_apis/wit/workitemsbatch?{API}',
                   {'ids': all_ids, 'fields': ['System.Id', 'System.WorkItemType', 'System.State',
                                               'System.AreaPath', 'System.IterationPath',
                                               'System.Parent']})
by_id = {r['id']: (r.get('fields') or {}) for r in (batch.get('value') or [])}
task_types = {'Task', 'Bug Task', 'QA Task'}
task_ids = sorted(i for i in all_ids if by_id.get(i, {}).get('System.WorkItemType') in task_types)
p(f'  task-category items in the sprint: {len(task_ids)} {task_ids}')
p(f'  taskboardworkitems ids == task-category ids? {sorted(tb_ids) == task_ids}')
p(f'  their types: { {i: by_id[i]["System.WorkItemType"] for i in task_ids} }')
p(f'  orphan tasks (task type, no System.Parent): '
  f'{[i for i in task_ids if not by_id.get(i, {}).get("System.Parent")]}')
p(f'  tasks whose parent is NOT in the sprint: '
  f'{[i for i in task_ids if by_id.get(i, {}).get("System.Parent") and by_id[i]["System.Parent"] not in all_ids]}')

# ------------------------------------------------------ D the 149 / 158 delta
blk('D  iterations/{id}/workitems vs WIQL UNDER path: what is the difference?')
wiql = ("SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project "
        f"AND [System.IterationPath] UNDER '{CC_PATH}'")
s, h, r = post(f'{ORG_URL}/{q(CC)}/_apis/wit/wiql?{API}&$top=500', {'query': wiql})
wiql_ids = sorted(w['id'] for w in (r.get('workItems') or []))
a, b = set(all_ids), set(wiql_ids)
s, h, tfv = get(f'{ORG_URL}/{q(CC)}/{q(CC_TEAM)}/_apis/work/teamsettings/teamfieldvalues?{API}')
p(f'  team areas: field={tfv.get("field", {}).get("referenceName") if isinstance(tfv, dict) else "?"} '
  f'default={tfv.get("defaultValue") if isinstance(tfv, dict) else "?"} '
  f'values={[(v.get("value"), v.get("includeChildren")) for v in (tfv.get("values") or [])] if isinstance(tfv, dict) else "?"}')
only_wiql = sorted(b - a)
only_iter = sorted(a - b)
p(f'  only in WIQL ({len(only_wiql)}): {only_wiql}')
if only_wiql:
    s, h, bb = post(f'{ORG_URL}/{q(CC)}/_apis/wit/workitemsbatch?{API}',
                    {'ids': only_wiql, 'fields': ['System.Id', 'System.WorkItemType', 'System.State',
                                                  'System.AreaPath', 'System.IterationPath']})
    for row in (bb.get('value') or []):
        f = row.get('fields') or {}
        p(f'    {row["id"]:>6} {f.get("System.WorkItemType"):12s} {f.get("System.State"):14s} '
          f'area={f.get("System.AreaPath")!r} iter={f.get("System.IterationPath")!r}')
p(f'  only in iterations/workitems ({len(only_iter)}): {only_iter}')
if only_iter:
    for i in only_iter:
        f = by_id.get(i, {})
        p(f'    {i:>6} {f.get("System.WorkItemType")} {f.get("System.State")} '
          f'area={f.get("System.AreaPath")!r} iter={f.get("System.IterationPath")!r} '
          f'parent={f.get("System.Parent")}')

# ---------------------------------------------------------------- E capacities
blk('E  capacities read properly')
for proj, team, iid, label in ((CC, CC_TEAM, CC_ITER, 'Iteration 106'),
                               (SC, SC_TEAM, SC_ITER, 'scratch Iteration 1')):
    s, h, cap = get(f'{ORG_URL}/{q(proj)}/{q(team)}/_apis/work/teamsettings/iterations/{iid}/capacities?{API}')
    tm = cap.get('teamMembers') or [] if isinstance(cap, dict) else []
    p(f'\n  {proj} / {label}: HTTP {s} teamMembers={len(tm)} '
      f'totalCapacityPerDay={cap.get("totalCapacityPerDay")} totalDaysOff={cap.get("totalDaysOff")}')
    if tm:
        p('  one member verbatim: ' + short(tm[0], 800))
    else:
        p('  full body: ' + short(cap, 500))
# any CloudCover sprint with capacity at all?
p('\n  scanning the last 8 CloudCover sprints for any capacity row:')
s, h, it = get(f'{ORG_URL}/{q(CC)}/{q(CC_TEAM)}/_apis/work/teamsettings/iterations?{API}')
iters = it.get('value') or []
for r in iters[-8:]:
    s, h, cap = get(f'{ORG_URL}/{q(CC)}/{q(CC_TEAM)}/_apis/work/teamsettings/iterations/{r["id"]}/capacities?{API}')
    tm = cap.get('teamMembers') or [] if isinstance(cap, dict) else []
    p(f'    {r.get("name")!r:18s} teamMembers={len(tm)} totalCapacityPerDay={cap.get("totalCapacityPerDay")}')

# ------------------------------------------------------ F the 100-iteration cap
blk('F  is the 100-row iteration list a cap or the team subscription?')
p(f'  teamsettings/iterations returned {len(iters)} rows; '
  f'first={iters[0].get("name")!r} last={iters[-1].get("name")!r}')
s, h, nodes = get(f'{ORG_URL}/{q(CC)}/_apis/wit/classificationnodes/Iterations?$depth=3&{API}')


def flat(n, out):
    out.append(n)
    for c in n.get('children') or []:
        flat(c, out)


tree = []
if s == 200:
    flat(nodes, tree)
p(f'  classification tree iterations (depth 3): {len(tree)} nodes')
tree_names = {n.get('name') for n in tree}
team_names = {r.get('name') for r in iters}
p(f'  in the tree but NOT in the team list: {sorted(tree_names - team_names - {"Iteration"})}')
p(f'  in the team list but not the tree: {sorted(team_names - tree_names)}')
for extra in ('$top=200', '$top=500'):
    s, h, it2 = get(f'{ORG_URL}/{q(CC)}/{q(CC_TEAM)}/_apis/work/teamsettings/iterations?{API}&{extra}')
    p(f'  with {extra}: HTTP {s} count={len(it2.get("value") or []) if isinstance(it2, dict) else 0}')

# ------------------------------------------------------- G @CurrentIteration
blk("G  @CurrentIteration('[project]\\team') syntax")
for team_name in ('CloudCover 2.0 Team',):
    for form in (f"[{CC}]\\\\{team_name}", f"[{CC}]\\{team_name}", f"{CC}\\{team_name}"):
        text = ("SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project "
                f"AND [System.IterationPath] = @CurrentIteration('{form}')")
        s, h, r = post(f'{ORG_URL}/{q(CC)}/_apis/wit/wiql?{API}&$top=500', {'query': text})
        n = len(r.get('workItems') or []) if isinstance(r, dict) and s == 200 else None
        p(f'  form {form!r}: HTTP {s} ids={n} '
          + ('' if s == 200 else (r.get('message', '')[:140] if isinstance(r, dict) else '')))
# offsets
for off in ('@CurrentIteration - 1', '@CurrentIteration + 1'):
    text = ("SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project "
            f"AND [System.IterationPath] = {off}")
    s, h, r = post(f'{ORG_URL}/{q(CC)}/_apis/wit/wiql?{API}&$top=500', {'query': text})
    p(f'  {off}: HTTP {s} ids={len(r.get("workItems") or []) if s == 200 else (r.get("message","")[:120] if isinstance(r, dict) else "")}')

# ----------------------------------------------------------------- H Analytics
blk('H  Analytics: a burndown that actually returns rows')
an = f'https://analytics.dev.azure.com/{ORG}/{q(CC)}/_odata/v4.0-preview'
sk = CC_ITER
start, end = '2026-08-25', '2026-09-08'
queries = {
    'count by day, all types':
        f'{an}/WorkItemSnapshot?$apply=filter(IterationSK eq {sk} and DateValue ge {start}Z and '
        f'DateValue le {end}Z)/groupby((DateValue),aggregate($count as Count))&$orderby=DateValue asc',
    'count by day and StateCategory':
        f'{an}/WorkItemSnapshot?$apply=filter(IterationSK eq {sk} and DateValue ge {start}Z and '
        f'DateValue le {end}Z)/groupby((DateValue,StateCategory),aggregate($count as Count,'
        f'StoryPoints with sum as SP,RemainingWork with sum as Remaining))&$orderby=DateValue asc',
    'requirement types only':
        f'{an}/WorkItemSnapshot?$apply=filter(IterationSK eq {sk} and DateValue ge {start}Z and '
        f"DateValue le {end}Z and (WorkItemType eq 'User Story' or WorkItemType eq 'Bug'))"
        f'/groupby((DateValue,StateCategory),aggregate($count as Count,StoryPoints with sum as SP))'
        f'&$orderby=DateValue asc',
}
for label, url in queries.items():
    t0 = time.time()
    s, h, r = get(url.replace(' ', '%20'))
    rows = r.get('value') or [] if isinstance(r, dict) else []
    p(f'\n  {label}: HTTP {s} {round(time.time()-t0, 2)}s rows={len(rows)} '
      f'cost={h.get("X-RateLimit-Cost")}')
    if s != 200:
        p('  ' + short(r, 400))
    else:
        p('  ' + short(rows[:8], 900))
# scratch project has no dates at all: what does Analytics do?
p('\n  Does Analytics answer with an OData version other than v4.0-preview?')
for v in ('v3.0-preview', 'v4.0-preview', 'v1.0'):
    s, h, r = get(f'https://analytics.dev.azure.com/{ORG}/{q(CC)}/_odata/{v}/WorkItems?$top=1&$select=WorkItemId')
    p(f'    {v}: HTTP {s}')
# the org-level (cross project) route
s, h, r = get(f'https://analytics.dev.azure.com/{ORG}/_odata/v4.0-preview/WorkItems?$top=1&$select=WorkItemId')
p(f'  org-level (no project segment): HTTP {s}')

# ----------------------------------------------------- I task order in a cell
blk('I  order of tasks inside one parent')
s, h, bb = post(f'{ORG_URL}/{q(CC)}/_apis/wit/workitemsbatch?{API}',
                {'ids': task_ids, 'fields': ['System.Id', 'System.Parent', 'System.WorkItemType',
                                             'System.State',
                                             'Microsoft.VSTS.Common.StackRank',
                                             'Microsoft.VSTS.Common.BacklogPriority',
                                             'Microsoft.VSTS.Scheduling.RemainingWork',
                                             'Microsoft.VSTS.Common.Activity']})
for row in (bb.get('value') or []):
    f = row.get('fields') or {}
    p(f'  {row["id"]:>6} parent={f.get("System.Parent")} '
      f'StackRank={f.get("Microsoft.VSTS.Common.StackRank")} '
      f'BacklogPriority={f.get("Microsoft.VSTS.Common.BacklogPriority")} '
      f'Remaining={f.get("Microsoft.VSTS.Scheduling.RemainingWork")} '
      f'Activity={f.get("Microsoft.VSTS.Common.Activity")}')
p('  order the iteration/workitems child rows arrived in, per parent:')
kids = {}
for r in rels:
    if r.get('source'):
        kids.setdefault(r['source']['id'], []).append(r['target']['id'])
for pid, ks in list(kids.items())[:8]:
    p(f'    parent {pid}: {ks}')

OUT.append(dump_costs('s55 rate-limit cost log'))
write_result('s55_sprint_followups/raw.md', '\n'.join(OUT))
print(dump_costs('s55 rate-limit cost log'))
