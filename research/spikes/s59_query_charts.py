"""s59 (read-only): what sits behind a Chart-for-Work-Items widget's
`settings.chartId` (s58), for research/19.

The WitChartWidget settings carry only `{"chartId": "<guid>"}`; the chart
definition (query, chart type, group-by, aggregation, colours) must come
from a charts resource. Probe the candidate routes with the one chartId the
org has (a client project's Overview dashboard; only shapes are recorded).

GETs only; nothing is written anywhere.
"""
import json, os, re, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402

OUT = []
GUID = re.compile(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def q(s):
    return urllib.parse.quote(str(s), safe='')


def shape(v):
    if isinstance(v, dict):
        return {k: shape(x) for k, x in v.items()}
    if isinstance(v, list):
        return [shape(x) for x in v[:4]] + (['…'] if len(v) > 4 else [])
    if isinstance(v, str):
        if GUID.fullmatch(v):
            return '<guid>'
        if re.fullmatch(r'[A-Za-z0-9_.:\-/#+]{0,40}', v):
            return v
        return f'<str:{len(v)}>'
    return v


# find the first WitChartWidget in the org
st, _, body = get(f'{ORG_URL}/_apis/projects?api-version=7.1')
target = None
for pr in body.get('value', []):
    st, _, dl = get(f'{ORG_URL}/{q(pr["name"])}/_apis/dashboard/dashboards?api-version=7.1-preview.3')
    for d in dl.get('value', []):
        if not d.get('groupId'):
            continue
        st, _, full = get(f'{ORG_URL}/{q(pr["name"])}/{d["groupId"]}/_apis/dashboard/dashboards/{d["id"]}?api-version=7.1-preview.3')
        for w in full.get('widgets') or []:
            if w.get('contributionId', '').endswith('.WitChartWidget') and w.get('settings'):
                target = (pr['name'], pr['id'], d['groupId'], json.loads(w['settings']).get('chartId'), w.get('id'))
                break
        if target:
            break
    if target:
        break

if not target:
    p('no WitChartWidget found')
else:
    pname, pid, team, chart_id, widget_id = target
    p(f'WitChartWidget found in <project {pid[:8]}>; chartId=<guid>')
    routes = [
        ('wit/charts/{id}',            f'{ORG_URL}/{q(pname)}/_apis/wit/charts/{chart_id}?api-version=7.1-preview.1'),
        ('wit/charts/{id} 7.1',        f'{ORG_URL}/{q(pname)}/_apis/wit/charts/{chart_id}?api-version=7.1'),
        ('chart/charts/{id}',          f'{ORG_URL}/{q(pname)}/_apis/chart/charts/{chart_id}?api-version=7.1-preview.1'),
        ('Chart/Charts?scope=WorkItemTracking.Queries',
                                       f'{ORG_URL}/{q(pname)}/_apis/Chart/Charts?scope=WorkItemTracking.Queries&api-version=7.1-preview.1'),
        ('Chart/Charts/{id}',          f'{ORG_URL}/{q(pname)}/_apis/Chart/Charts/{chart_id}?api-version=7.1-preview.1'),
        ('Charting/Charts/{id}',       f'{ORG_URL}/{q(pname)}/_apis/Charting/Charts/{chart_id}?api-version=7.1-preview.1'),
        ('work/charts/{id}',           f'{ORG_URL}/{q(pname)}/_apis/work/charts/{chart_id}?api-version=7.1-preview.1'),
        ('wit/queries?$expand=charts', f'{ORG_URL}/{q(pname)}/_apis/wit/queries?$depth=0&api-version=7.1'),
    ]
    for label, url in routes:
        st, hdrs, b = get(url)
        p(f'\n[{label}] HTTP {st}')
        if st == 200:
            p('  shape:', json.dumps(shape(b), indent=1)[:2500])
        else:
            p('  ', short(b, 300).replace('\n', ' '))

    # the chart may live under the query: find a shared query with charts
    # (WorkItemTracking.Queries scope) — `_apis/wit/queries/{queryId}/charts` probe
    # uses the QueryScalarWidget's queryId if one exists on the same dashboard.
    st, _, full = get(f'{ORG_URL}/{q(pname)}/{team}/_apis/dashboard/dashboards?api-version=7.1-preview.3')
    qid = None
    for d in full.get('value', []):
        st, _, fd = get(f'{ORG_URL}/{q(pname)}/{team}/_apis/dashboard/dashboards/{d["id"]}?api-version=7.1-preview.3')
        for w in fd.get('widgets') or []:
            if w.get('contributionId', '').endswith('.QueryScalarWidget') and w.get('settings'):
                qid = json.loads(w['settings']).get('queryId')
    if qid:
        for label, url in [
            ('wit/queries/{qid}/charts',           f'{ORG_URL}/{q(pname)}/_apis/wit/queries/{qid}/charts?api-version=7.1-preview.1'),
            ('Chart/Charts?scope=…&groupKey=qid',  f'{ORG_URL}/{q(pname)}/_apis/Chart/Charts?scope=WorkItemTracking.Queries&groupKey={qid}&api-version=7.1-preview.1'),
            ('wit/queries/{qid} (shape only)',     f'{ORG_URL}/{q(pname)}/_apis/wit/queries/{qid}?api-version=7.1'),
        ]:
            st, hdrs, b = get(url)
            p(f'\n[{label}] HTTP {st}')
            if st == 200:
                p('  shape:', json.dumps(shape(b), indent=1)[:2500])
            else:
                p('  ', short(b, 300).replace('\n', ' '))


# Route discovery: OPTIONS on candidate resource areas lists their route
# templates (read-only; no body, nothing written), plus the resource-area
# directory.
from lib import call  # noqa: E402
p('\n=== route discovery ===')
st, _, ra = get(f'{ORG_URL}/_apis/resourceareas?api-version=7.1-preview.1')
names = sorted((a.get('name') or '') for a in (ra.get('value') or [])) if isinstance(ra, dict) else ra
p(f'resourceareas: HTTP {st} names={names}')
for area in ('Chart', 'Charts', 'Charting', 'Dashboard', 'Favorite'):
    st, _, b = call('OPTIONS', f'{ORG_URL}/_apis/{area}')
    p(f'\nOPTIONS _apis/{area}: HTTP {st}')
    if st == 200 and isinstance(b, dict):
        for loc in b.get('value') or []:
            p(f"   {loc.get('area')}/{loc.get('resourceName')}: {loc.get('routeTemplate')} min={loc.get('minVersion')} max={loc.get('maxVersion')} released={loc.get('releasedVersion')} id={loc.get('id')}")
    else:
        p('  ', short(b, 200).replace('\n', ' '))
if target:
    pname, pid, team, chart_id, widget_id = target
    for label, url in [
        ('Charts/Charts/{id}',      f'{ORG_URL}/{q(pname)}/_apis/Charts/Charts/{chart_id}?api-version=7.1-preview.1'),
        ('Chart/Charts/scope/qid',  f'{ORG_URL}/{q(pname)}/_apis/Chart/Charts/WorkItemTracking.Queries/{qid}?api-version=7.1-preview.1'),
        ('Chart/Charts/scope/qid/id', f'{ORG_URL}/{q(pname)}/_apis/Chart/Charts/WorkItemTracking.Queries/{qid}/{chart_id}?api-version=7.1-preview.1'),
        ('chart/{scope}/{groupKey}', f'{ORG_URL}/{q(pname)}/_apis/chart/WorkItemTracking.Queries/{qid}?api-version=7.1-preview.1'),
    ]:
        st, hdrs, b = get(url)
        p(f'\n[{label}] HTTP {st}')
        if st == 200:
            p('  shape:', json.dumps(shape(b), indent=1)[:3000])
        else:
            p('  ', short(b, 200).replace('\n', ' '))


# Which artifact types can be favorited (verifies the dashboard artifactType string).
p('\n=== Favorite providers ===')
st, _, b = get(f'{ORG_URL}/_apis/Favorite/FavoriteProviders?api-version=7.1-preview.1')
p(f'GET _apis/Favorite/FavoriteProviders: HTTP {st}')
if st == 200 and isinstance(b, dict):
    for prov in b.get('value') or []:
        p('  ', json.dumps(shape(prov), sort_keys=True)[:400])
else:
    p('  ', short(b, 300).replace('\n', ' '))
# OPTIONS on the WIT area: is there a charts resource under wit?
for area in ('wit', 'work', 'Analytics'):
    st, _, b = call('OPTIONS', f'{ORG_URL}/_apis/{area}')
    locs = [l for l in (b.get('value') or []) if 'chart' in (l.get('resourceName') or '').lower() or 'chart' in (l.get('routeTemplate') or '').lower()] if isinstance(b, dict) else []
    p(f'OPTIONS _apis/{area}: HTTP {st} locations={len(b.get("value") or []) if isinstance(b, dict) else "-"} chart-like={[(l.get("resourceName"), l.get("routeTemplate"), l.get("maxVersion")) for l in locs]}')


# Service constants (not client data): the artifactType / artifactUri templates.
p('\n=== Favorite providers, artifactType and artifactUri verbatim ===')
st, _, b = get(f'{ORG_URL}/_apis/Favorite/FavoriteProviders?api-version=7.1-preview.1')
for prov in (b.get('value') or []) if isinstance(b, dict) else []:
    p(f"   {prov.get('artifactType')} | {prov.get('artifactUri')} | {prov.get('contributionId')} | {prov.get('pluralName')}")

# Chart images and board charts on the scratch project (GET only).
p('\n=== work chart routes, scratch project ===')
SCRATCH = 'DevOps Mobile App'
st, _, tb = get(f'{ORG_URL}/_apis/projects/{q(SCRATCH)}/teams?api-version=7.1')
team = tb['value'][0]['id']
st, _, its = get(f'{ORG_URL}/{q(SCRATCH)}/{team}/_apis/work/teamsettings/iterations?api-version=7.1')
iters = its.get('value') or []
p(f'iterations: {len(iters)}; current={[i["name"] for i in iters if i.get("attributes", {}).get("timeFrame") == "current"]}')
st, _, bds = get(f'{ORG_URL}/{q(SCRATCH)}/{team}/_apis/work/boards?api-version=7.1')
boards = bds.get('value') or []
p(f'boards: {[b_["name"] for b_ in boards]}')
if boards:
    bname = boards[0]['name']
    for label, url in [
        ('boards/{board}/charts',            f'{ORG_URL}/{q(SCRATCH)}/{team}/_apis/work/boards/{q(bname)}/charts?api-version=7.1'),
        ('boards/{board}/charts/cumulativeflow', f'{ORG_URL}/{q(SCRATCH)}/{team}/_apis/work/boards/{q(bname)}/charts/cumulativeflow?api-version=7.1'),
        ('boards/{board}/chartimages/cumulativeflow', f'{ORG_URL}/{q(SCRATCH)}/{team}/_apis/work/boards/{q(bname)}/chartimages/cumulativeflow?api-version=7.1-preview.1&width=600&height=400'),
        ('boards/{board}/chartimages/CumulativeFlow (7.1)', f'{ORG_URL}/{q(SCRATCH)}/{team}/_apis/work/boards/{q(bname)}/chartimages/CumulativeFlow?api-version=7.1&width=600&height=400'),
    ]:
        st, hdrs, body_ = get(url, raw=True)
        p(f'\n[{label}] HTTP {st} content-type={hdrs.get("Content-Type")} bytes={len(body_)}')
        if 'json' in (hdrs.get('Content-Type') or ''):
            try:
                p('  shape:', json.dumps(shape(json.loads(body_)), indent=1)[:1500])
            except Exception as e:
                p('  ', body_[:300])
        else:
            p('  ', body_[:200].replace('\n', ' ') if not body_.startswith('\x89PNG') else '  <PNG>')
if iters:
    it = next((i for i in iters if i.get('attributes', {}).get('timeFrame') == 'current'), iters[0])
    for label, url in [
        ('iterations/{id}/chartimages/burndown', f'{ORG_URL}/{q(SCRATCH)}/{team}/_apis/work/iterations/{it["id"]}/chartimages/burndown?api-version=7.1-preview.1&width=600&height=400'),
        ('iterations/{id}/chartimages/Burndown (7.1)', f'{ORG_URL}/{q(SCRATCH)}/{team}/_apis/work/iterations/{it["id"]}/chartimages/Burndown?api-version=7.1&width=600&height=400'),
        ('iterations/chartimages/burndown (no id)', f'{ORG_URL}/{q(SCRATCH)}/{team}/_apis/work/iterations/chartimages/burndown?api-version=7.1-preview.1&width=600&height=400'),
    ]:
        st, hdrs, body_ = get(url, raw=True)
        p(f'\n[{label}] HTTP {st} content-type={hdrs.get("Content-Type")} bytes={len(body_)}')
        if st != 200 or 'json' in (hdrs.get('Content-Type') or ''):
            p('  ', body_[:300].replace('\n', ' '))
        elif 'image' in (hdrs.get('Content-Type') or ''):
            import base64
            out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results', 's59_query_charts', label.split('/')[-1].split(' ')[0] + '.png')
            os.makedirs(os.path.dirname(out), exist_ok=True)
            # body_ came back decoded as text (utf-8, replace); refetch bytes
            import urllib.request
            p('  image; see result folder (bytes re-fetched separately)')


# Last try for the query-chart definition behind WitChartWidget.chartId: the
# legacy MVC `_api` routes the web client used before `_apis`.
p('\n=== legacy _api chart routes ===')
if target:
    pname, pid, team, chart_id, widget_id = target
    for label, url in [
        ('_api/_chart/GetCharts',   f'{ORG_URL}/{q(pname)}/_api/_chart/GetCharts?scope=WorkItemTracking.Queries&groupKey={qid}&__v=5'),
        ('_api/_chart/GetChart',    f'{ORG_URL}/{q(pname)}/_api/_chart/GetChart?chartId={chart_id}&__v=5'),
        ('_apis/Charting/Charts?scope&groupKey', f'{ORG_URL}/{q(pname)}/_apis/Charting/Charts?scope=WorkItemTracking.Queries&groupKey={qid}&api-version=7.1-preview.1'),
        ('_apis/wit/queries/{qid}?$expand=all', f'{ORG_URL}/{q(pname)}/_apis/wit/queries/{qid}?$expand=all&api-version=7.1'),
    ]:
        st, hdrs, b = get(url)
        p(f'\n[{label}] HTTP {st} content-type={hdrs.get("Content-Type")}')
        if st == 200 and isinstance(b, dict):
            p('  shape:', json.dumps(shape(b), indent=1)[:2000])
        else:
            p('  ', short(b, 200).replace('\n', ' '))

write_result('s59_query_charts/s59_query_charts.md', '\n'.join(OUT) + dump_costs())
