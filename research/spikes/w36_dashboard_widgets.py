"""w36 (SCRATCH PROJECT WRITES ONLY): pin the dashboard widget settings shapes
that were never seen live (decision D11, research/19 §5).

Everything here targets "DevOps Mobile App" and its default team's empty
"Overview" dashboard. Nothing touches a client project.

  0  look up the scratch ids (project, team, repo, iteration, board level)
  1  create one shared query (the scratch project has none, spike s60), so the
     Query Tile / Query Results / Chart for Work Items widgets have an artifact
  2  POST one widget of every kind whose settings shape research/19 §1 could
     not quote from a live dashboard, each with the best-guess settings from
     the CloneAzdoDashboard models and the docs' configure-* pages
  3  GET the dashboard back (7.1-preview.3) and dump every widget with its
     settings verbatim: the readback is the deliverable
  4  read `_links` on the dashboard to check the web deep-link form

The widgets stay in place: they are the acceptance data for phases D-B..D-D.
"""
import json, os, sys, urllib.parse, uuid
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402

PROJECT = 'DevOps Mobile App'
TEAM = '8c08e1e1-7afd-411e-b414-4f9e1d14d8d6'          # DevOps Mobile App Team
DASHBOARD = '985ff75c-bdf6-4b2d-a2b0-0ef63431e6ec'     # its empty "Overview"
ITERATION = 'aa9f2381-54e4-499a-8b8b-e3f981aac964'     # Iteration 1
PIPELINE = 139                                          # boardhop-scratch
BOARD = 'Stories'                                       # requirement board (s61)

DASH_API = 'api-version=7.1-preview.3'
WIDGET_API = 'api-version=7.1-preview.2'
WIT_API = 'api-version=7.1'

P = urllib.parse.quote(PROJECT, safe='')
DASH = f'{ORG_URL}/{P}/{TEAM}/_apis/dashboard/dashboards'
WIT = f'{ORG_URL}/{P}/_apis/wit'
OUT = []
D = 'ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.'
MYWORK = 'ms.vss-mywork-web.Microsoft.VisualStudioOnline.MyWork.'


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def blk(t):
    p('')
    p('=' * 78)
    p('===', t)
    p('=' * 78)


def delete(url):
    return call('DELETE', url)


# --------------------------------------------------------------- 0 lookups
blk('0  scratch ids')
st, _, body = get(f'{ORG_URL}/_apis/projects/{P}?{WIT_API}')
PROJECT_ID = body.get('id') if st == 200 else None
p(f'project: HTTP {st} id={PROJECT_ID}')

st, _, body = get(f'{ORG_URL}/{P}/_apis/git/repositories?{WIT_API}')
repos = body.get('value', []) if st == 200 else []
REPO = repos[0] if repos else {}
p(f'repositories: HTTP {st} n={len(repos)} '
  f'first={REPO.get("name")} id={REPO.get("id")} default={REPO.get("defaultBranch")}')

st, _, body = get(f'{ORG_URL}/{P}/{TEAM}/_apis/work/teamsettings/iterations/{ITERATION}?{WIT_API}')
ITER_PATH = body.get('path') if st == 200 else f'{PROJECT}\\Iteration 1'
p(f'iteration: HTTP {st} path={ITER_PATH!r} attrs={body.get("attributes") if st == 200 else None}')

# ------------------------------------------------------- 1 the shared query
blk('1  a shared query for the query-backed widgets')
QUERY_NAME = 'Boardhop dashboard spike'
QUERY_ID = None
st, _, body = get(f'{WIT}/queries/Shared%20Queries?$depth=2&$expand=wiql&{WIT_API}')
existing = [c for c in (body.get('children') or []) if c.get('name') == QUERY_NAME] if st == 200 else []
if existing:
    QUERY_ID = existing[0]['id']
    p(f'query already exists: id={QUERY_ID} type={existing[0].get("queryType")}')
else:
    wiql = (
        "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], "
        "[System.AssignedTo] FROM WorkItems "
        f"WHERE [System.TeamProject] = '{PROJECT}' "
        "AND [System.WorkItemType] IN ('User Story', 'Bug') "
        "AND [System.State] <> 'Removed' ORDER BY [System.ChangedDate] DESC"
    )
    st, _, body = post(
        f'{WIT}/queries/Shared%20Queries?{WIT_API}',
        {'name': QUERY_NAME, 'wiql': wiql, 'isFolder': False},
    )
    p(f'POST query: HTTP {st}')
    if st in (200, 201):
        QUERY_ID = body.get('id')
        p(f'  id={QUERY_ID} queryType={body.get("queryType")} path={body.get("path")!r}')
    else:
        p('  ' + short(body, 600))

if QUERY_ID:
    st, _, body = get(f'{WIT}/queries/{QUERY_ID}?$expand=wiql&{WIT_API}')
    p(f'query readback: HTTP {st} keys={sorted(body.keys()) if isinstance(body, dict) else body}')
    if st == 200:
        p(f'  queryType={body.get("queryType")} columns='
          f'{[c.get("referenceName") for c in (body.get("columns") or [])]}')
    st, _, body = get(f'{WIT}/wiql/{QUERY_ID}?{WIT_API}')
    n = len(body.get('workItems') or []) if isinstance(body, dict) else 0
    p(f'wiql/{{id}}: HTTP {st} ids={n}')
    st, hdrs, _ = call('HEAD', f'{WIT}/wiql/{QUERY_ID}?{WIT_API}', raw=True)
    p(f'HEAD wiql/{{id}}: HTTP {st} X-Total-Count={hdrs.get("X-Total-Count")}')

# ------------------------------------------------------------- 2 the posts
blk('2  POST one widget of every unseen kind')

CHART_ID = str(uuid.uuid4())  # Chart for Work Items: the web stores only this


def widget(name, contribution, row, column, row_span, column_span, settings):
    """settings: a dict (JSON-encoded), a string (sent raw) or None."""
    body = {
        'name': name,
        'contributionId': contribution,
        'position': {'row': row, 'column': column},
        'size': {'rowSpan': row_span, 'columnSpan': column_span},
        'settingsVersion': {'major': 1, 'minor': 0, 'patch': 0},
    }
    if settings is not None:
        body['settings'] = settings if isinstance(settings, str) else json.dumps(settings)
    return body


team_ref = {'projectId': PROJECT_ID, 'teamId': TEAM}
req_filter = {'identifier': 'BacklogCategory', 'settings': 'Microsoft.RequirementCategory'}
points = {'identifier': 1, 'settings': 'Microsoft.VSTS.Scheduling.StoryPoints'}

WIDGETS = [
    # --- row 1: the 1x1 and 1x2 tiles
    widget('Query Tile', D + 'QueryScalarWidget', 1, 1, 1, 1, {
        'queryId': QUERY_ID,
        'queryName': QUERY_NAME,
        'lastArtifactName': QUERY_NAME,
        'defaultBackgroundColor': '#007acc',
        'colorRules': [],
    }),
    widget('Code Tile', D + 'CodeScalarWidget', 1, 2, 1, 1, {
        'projectId': PROJECT_ID,
        'repositoryId': REPO.get('id'),
        'repositoryName': REPO.get('name'),
        'branchName': (REPO.get('defaultBranch') or 'refs/heads/main').split('/')[-1],
        'path': '/',
    }),
    widget('Build History', D + 'BuildHistogramWidget', 1, 3, 1, 2, {
        'buildDefinition': str(PIPELINE),
        'uri': f'vstfs:///Build/Definition/{PIPELINE}',
        'defaultBranch': REPO.get('defaultBranch') or 'refs/heads/main',
    }),
    widget('Sprint Overview', D + 'SprintOverviewWidget', 1, 5, 1, 2, {
        'showWorkItems': True,
    }),
    # Markdown: research/19 §1 says the settings string is the markdown itself;
    # send plain text and see what comes back.
    widget('Markdown', D + 'MarkdownWidget', 1, 7, 2, 2,
           '## Boardhop scratch\n\nPlain-text markdown settings, written by spike w36.\n'
           '\n- a bullet\n- [a link](https://dev.azure.com/)\n'),
    # --- rows 2-3: the query-backed widgets
    widget('Query Results', MYWORK + 'WitViewWidget', 2, 1, 2, 3, {
        'queryId': QUERY_ID,
        'queryName': QUERY_NAME,
        'lastArtifactName': QUERY_NAME,
    }),
    widget('Chart for Work Items', D + 'WitChartWidget', 2, 4, 2, 2, {
        'chartId': CHART_ID,
    }),
    # --- rows 4-5: the Analytics charts
    widget('Cumulative Flow Diagram', D + 'CumulativeFlowDiagramWidget', 4, 1, 2, 3, {
        'projectId': PROJECT_ID,
        'teamId': TEAM,
        'boardName': BOARD,
        'swimlane': 'All',
        'numberOfDays': 30,
        'hideIncoming': False,
        'hideOutgoing': False,
        'backlogLevelName': BOARD,
    }),
    widget('Cycle Time', D + 'CycleTimeWidget', 4, 4, 2, 3, {
        'projectId': PROJECT_ID,
        'teamId': TEAM,
        'workItemTypeFilter': req_filter,
        'fieldFilters': [],
        'timePeriodInDays': 30,
    }),
    widget('Lead Time', D + 'LeadTimeWidget', 4, 7, 2, 3, {
        'projectId': PROJECT_ID,
        'teamId': TEAM,
        'workItemTypeFilter': req_filter,
        'fieldFilters': [],
        'timePeriodInDays': 30,
    }),
    # --- rows 6-7: velocity and the two list widgets
    widget('Velocity', D + 'VelocityWidget', 6, 1, 2, 3, {
        'teams': [team_ref],
        'teamId': TEAM,
        'projectId': PROJECT_ID,
        'numberOfIterations': 6,
        'aggregation': points,
        'workItemTypeFilter': req_filter,
        'fieldFilters': [],
    }),
    widget('Pull Requests', D + 'PullrequestsWidget', 6, 4, 2, 3, None),
    widget('Assigned to Me', D + 'AssignedToMeWidget', 6, 7, 2, 3, None),
]

posted = []
for w in WIDGETS:
    st, _, body = post(f'{DASH}/{DASHBOARD}/widgets?{WIDGET_API}', w)
    kind = w['contributionId'].rsplit('.', 1)[-1]
    p(f'\nPOST {kind} ({w["size"]["rowSpan"]}x{w["size"]["columnSpan"]} '
      f'@ r{w["position"]["row"]}c{w["position"]["column"]}): HTTP {st}')
    if st in (200, 201):
        posted.append(body.get('id'))
        p(f'  id={body.get("id")} eTag={body.get("eTag")} '
          f'position={body.get("position")} size={body.get("size")}')
    else:
        msg = body.get('message') if isinstance(body, dict) else str(body)[:300]
        p(f'  REFUSED: {msg}')
        # Smallest valid body the error suggests: no settings at all.
        retry = {k: v for k, v in w.items() if k != 'settings'}
        st2, _, body2 = post(f'{DASH}/{DASHBOARD}/widgets?{WIDGET_API}', retry)
        p(f'  retry without settings: HTTP {st2}')
        if st2 in (200, 201):
            posted.append(body2.get('id'))
        else:
            m2 = body2.get('message') if isinstance(body2, dict) else str(body2)[:300]
            p(f'    REFUSED: {m2}')

p(f'\nposted {len(posted)} widget(s)')

# ------------------------------------------------------------ 3 the readback
blk('3  readback: GET the dashboard by id (7.1-preview.3)')
st, hdrs, dash = get(f'{DASH}/{DASHBOARD}?{DASH_API}')
p(f'HTTP {st} keys={sorted(dash.keys()) if isinstance(dash, dict) else dash}')
widgets = (dash.get('widgets') or []) if isinstance(dash, dict) else []
p(f'eTag={dash.get("eTag")} refreshInterval={dash.get("refreshInterval")} widgets={len(widgets)}')
for w in sorted(widgets, key=lambda x: (x['position']['row'], x['position']['column'])):
    p('')
    p(f'  {w.get("name")!r}  {w.get("contributionId")}')
    p(f'    id={w.get("id")} typeId={w.get("typeId")} '
      f'pos={w.get("position")} size={w.get("size")} '
      f'settingsVersion={w.get("settingsVersion")} isEnabled={w.get("isEnabled")} '
      f'eTag={w.get("eTag")} artifactId={w.get("artifactId")!r} '
      f'configId={w.get("configurationContributionId")} '
      f'lightbox={w.get("lightboxOptions")}')
    p(f'    keys={sorted(w.keys())}')
    s = w.get('settings')
    if s is None:
        p('    settings: null')
    else:
        try:
            p('    settings(json): ' + json.dumps(json.loads(s), sort_keys=True))
        except (ValueError, TypeError):
            p(f'    settings(raw, not JSON): {s!r}')

blk('3b  the widgets sub-resource (7.1-preview.2) for the same dashboard')
st, hdrs, body = get(f'{DASH}/{DASHBOARD}/widgets?{WIDGET_API}')
n = body.get('count') if isinstance(body, dict) else None
p(f'HTTP {st} count={n} ETag-header={hdrs.get("ETag")}')

# --------------------------------------------------------------- 4 the links
blk('4  _links / deep link form')
p(json.dumps(dash.get('_links') if isinstance(dash, dict) else None, indent=1))
p(f'url: {dash.get("url") if isinstance(dash, dict) else None}')
p(f'web deep link (unverified form): {ORG_URL}/{P}/_dashboards/dashboard/{DASHBOARD}')
st, _, _body = get(f'{ORG_URL}/{P}/_apis/dashboard/dashboards?{DASH_API}')
lst = _body.get('value', []) if st == 200 else []
p(f'project-route list: HTTP {st} n={len(lst)} '
  f'entry keys={sorted(lst[0].keys()) if lst else None} '
  f'widgets in list entry={len((lst[0].get("widgets") or [])) if lst else None}')

p('')
p(f'run at {datetime.now(timezone.utc).isoformat()}')
write_result('w36_dashboard_widgets/w36_dashboard_widgets.md',
             '\n'.join(OUT) + '\n' + dump_costs('w36 rate-limit cost log'))
