"""s60 (read-only): the REST data behind the query-based and pipeline dashboard
widgets (research/dash r2).

  A  saved query tree: `wit/queries?$depth=2&$expand=none` (shape, count, cost)
  B  one shared query: `wit/queries/{id}?$expand=wiql|minimal|all` (keys, queryType)
  C  `wiql/{id}` (ids, cost), `wiql/{id}?$top=1` (does a count survive?), HEAD
  D  `workitemsbatch` for the ids vs `workitems?ids=` (cost, time)
  E  does any charts endpoint exist for a saved query? (status codes only)
  F  build history: `build/builds?definitions=&$top=20&queryOrder=finishTimeDescending`
     plus `maxBuildsPerDefinition=1` for a "latest run per pipeline" tile
  G  release host (vsrm) definitions/releases, test runs: exist? cost?

GETs and the two query POSTs only (wiql, workitemsbatch); nothing is written.
Scratch project first, then one client project for counts and timings only
(no client text is echoed: only numbers, keys and field names).
"""
import os, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, call, dump_costs, write_result, COST_LOG  # noqa: E402

API = 'api-version=7.1'
OUT = []
SCRATCH = 'DevOps Mobile App'
CLIENT = 'CloudCover 2.0'
LIST_FIELDS = ['System.Id', 'System.Title', 'System.WorkItemType', 'System.State',
               'System.AssignedTo', 'System.ChangedDate', 'System.Tags',
               'Microsoft.VSTS.Common.Priority', 'System.IterationPath']


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def blk(t):
    p(f'\n=== {t} ===')


def q(s):
    return urllib.parse.quote(str(s), safe='')


def last_cost():
    m, u, s, c, d, t = COST_LOG[-1]
    return f'HTTP {s} cost={c} {t}s'


def keys(o):
    return sorted(o.keys()) if isinstance(o, dict) else type(o).__name__


def walk(items, depth=0):
    for it in items or []:
        yield depth, it
        yield from walk(it.get('children'), depth + 1)


for project in (SCRATCH, CLIENT):
    client = project == CLIENT
    tag = 'scratch' if not client else 'client'
    base = f'{ORG_URL}/{q(project)}/_apis'
    blk(f'A  {tag}: wit/queries?$depth=2&$expand=none')
    s, h, tree = get(f'{base}/wit/queries?$depth=2&$expand=none&{API}')
    p(f'  {last_cost()} bytes~{len(str(tree))}')
    if s != 200:
        p('  ', str(tree)[:300]); continue
    roots = tree.get('value') or []
    p(f'  roots={len(roots)} root keys={keys(roots[0]) if roots else None}')
    folders = queries = 0
    shared_flat = shared_tree = None
    for depth, it in walk(roots):
        if it.get('isFolder'):
            folders += 1
        else:
            queries += 1
            if it.get('isPublic') and it.get('queryType') == 'flat' and shared_flat is None:
                shared_flat = it
            if it.get('isPublic') and it.get('queryType') in ('tree', 'oneHop') and shared_tree is None:
                shared_tree = it
    p(f'  folders={folders} queries={queries} (depth 2 only)')
    if queries:
        sample = next(it for _, it in walk(roots) if not it.get('isFolder'))
        p(f'  query item keys={keys(sample)}')
        # does $expand=none carry queryType / columns already?
        p(f'  has queryType={"queryType" in sample} has columns={"columns" in sample} has wiql={"wiql" in sample}')
    if not client:
        for depth, it in walk(roots):
            p(f'  {"  " * depth}{"[F] " if it.get("isFolder") else ""}{it.get("name")} '
              f'{"" if it.get("isFolder") else "type=" + str(it.get("queryType"))} public={it.get("isPublic")}')
    qy = shared_flat or (next((it for _, it in walk(roots) if not it.get('isFolder')), None))
    if qy is None:
        p('  no query found; skipping B-E'); continue
    qid = qy['id']

    blk(f'B  {tag}: wit/queries/{{id}} expands')
    for ex in ('none', 'minimal', 'wiql', 'all'):
        s, h, one = get(f'{base}/wit/queries/{qid}?$expand={ex}&{API}')
        p(f'  $expand={ex}: {last_cost()} keys={keys(one)}')
        if ex == 'wiql' and s == 200:
            p(f'    queryType={one.get("queryType")} columns={len(one.get("columns") or [])} '
              f'sortColumns={len(one.get("sortColumns") or [])} wiql_len={len(one.get("wiql") or "")}')
            if not client:
                p(f'    wiql: {one.get("wiql")}')
            p(f'    columns: {[c.get("referenceName") for c in one.get("columns") or []]}')
    if shared_tree:
        s, h, one = get(f'{base}/wit/queries/{shared_tree["id"]}?$expand=wiql&{API}')
        p(f'  tree/oneHop query: {last_cost()} queryType={one.get("queryType")} '
          f'queryRecursionOption={one.get("queryRecursionOption")} filterOptions={one.get("filterOptions")}')

    blk(f'C  {tag}: wiql/{{id}}')
    s, h, res = get(f'{base}/wit/wiql/{qid}?{API}')
    ids = [w['id'] for w in (res.get('workItems') or [])] if s == 200 else []
    p(f'  full: {last_cost()} keys={keys(res)} queryType={res.get("queryType")} '
      f'resultType={res.get("queryResultType")} workItems={len(ids)} '
      f'relations={len(res.get("workItemRelations") or [])} bytes~{len(str(res))}')
    s, h, res1 = get(f'{base}/wit/wiql/{qid}?$top=1&{API}')
    p(f'  $top=1: {last_cost()} workItems={len(res1.get("workItems") or [])} '
      f'keys={keys(res1)} (any count key? {[k for k in res1 if "count" in k.lower()]}) '
      f'X-Total-Count={h.get("X-Total-Count")}')
    s, h, txt = call('HEAD', f'{base}/wit/wiql/{qid}?{API}', raw=True)
    p(f'  HEAD: HTTP {s} headers with count/total: '
      f'{ {k: v for k, v in h.items() if "count" in k.lower() or "total" in k.lower()} } body_len={len(txt)}')
    s, h, res0 = get(f'{base}/wit/wiql/{qid}?$top=0&{API}')
    p(f'  $top=0: {last_cost()} workItems={len(res0.get("workItems") or []) if isinstance(res0, dict) else res0}')
    if shared_tree:
        s, h, rt = get(f'{base}/wit/wiql/{shared_tree["id"]}?$top=50&{API}')
        p(f'  tree query $top=50: {last_cost()} relations={len(rt.get("workItemRelations") or [])} '
          f'roots={sum(1 for r in rt.get("workItemRelations") or [] if not r.get("source"))}')

    blk(f'D  {tag}: fields for {len(ids)} ids')
    chunk = ids[:200]
    if chunk:
        s, h, b = call('POST', f'{base}/wit/workitemsbatch?{API}',
                       {'ids': chunk, 'fields': LIST_FIELDS, 'errorPolicy': 'omit'})
        p(f'  workitemsbatch({len(chunk)}): {last_cost()} rows={len(b.get("value") or [])} bytes~{len(str(b))}')
        n = min(len(chunk), 50)
        s, h, g = get(f'{base}/wit/workitems?ids={",".join(map(str, chunk[:n]))}'
                      f'&fields={",".join(LIST_FIELDS)}&{API}')
        p(f'  workitems?ids= ({n}): {last_cost()} rows={len(g.get("value") or []) if isinstance(g, dict) else g}')
        # the Query Tile only needs a number: cheapest count?
        s, h, c = call('POST', f'{base}/wit/wiql?$top=1&{API}',
                       {'query': 'SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project'})
        p(f'  POST wiql $top=1 (project-wide): {last_cost()} workItems={len(c.get("workItems") or [])}')

    blk(f'E  {tag}: charts endpoints for a saved query (status codes only)')
    probes = [
        f'{base}/wit/queries/{qid}/charts?{API}',
        f'{base}/wit/queries/{qid}/charts?api-version=7.1-preview.1',
        f'{base}/Charting/charts?scope=WorkItemTracking.Queries&scopeIdentifier={qid}&{API}',
        f'{base}/Charting/charts?scope=WorkItemTracking.Queries&scopeIdentifier={qid}&api-version=7.1-preview.1',
        f'{base}/Charting/charts?scope=WorkItemTracking.Queries&scopeIdentifier={qid}&api-version=1.0-preview.1',
        f'{base}/Charting/charts/WorkItemTracking.Queries/{qid}?api-version=7.1-preview.1',
        f'{base}/Charting/charts/WorkItemTracking.Queries/{qid}?api-version=1.0-preview.1',
        f'{ORG_URL}/_apis/Charting/charts?scope=WorkItemTracking.Queries&scopeIdentifier={qid}&api-version=7.1-preview.1',
        f'{base}/work/charts?{API}',
    ]
    for url in probes:
        s, h, body = get(url, raw=True)
        short_u = url.replace(ORG_URL, '{org}').replace(q(project), '{project}').replace(qid, '{qid}')
        msg = ''
        if s in (400, 404, 405) and isinstance(body, str):
            i = body.find('"message"')
            msg = body[i:i + 160].replace('\n', ' ') if i >= 0 else body[:120].replace('\n', ' ')
        elif s == 200:
            msg = f'200! keys/body: {body[:400]}'
        p(f'  {s} {short_u} {msg}')
    if not client:
        # Charts on the query in the *web* UI are stored as chart settings; probe the
        # per-query settings resource too
        s, h, body = get(f'{base}/Charting/charts?scope=WorkItemTracking.Queries&scopeIdentifier={qid}&api-version=7.1-preview.1', raw=True)
        p(f'  response headers of the Charting probe: {sorted(k for k in h)}')

    blk(f'F  {tag}: build history')
    s, h, defs = get(f'{base}/build/definitions?{API}')
    dlist = defs.get('value') or [] if isinstance(defs, dict) else []
    p(f'  definitions: {last_cost()} count={len(dlist)} keys={keys(dlist[0]) if dlist else None}')
    if dlist:
        did = 139 if not client else dlist[0]['id']
        s, h, builds = get(f'{base}/build/builds?definitions={did}&$top=20&queryOrder=finishTimeDescending&{API}')
        rows = builds.get('value') or []
        p(f'  builds top20 finishTimeDescending: {last_cost()} rows={len(rows)} bytes~{len(str(builds))} '
          f'continuation={h.get("x-ms-continuationtoken")}')
        if rows:
            b0 = rows[0]
            p(f'    build keys={keys(b0)}')
            p(f'    {[(r.get("id"), r.get("status"), r.get("result"), r.get("reason"), (r.get("finishTime") or "")[:10]) for r in rows[:5]]}')
            p(f'    per-build bytes~{len(str(builds)) // len(rows)}; definition keys={keys(b0.get("definition"))}')
        s, h, b2 = get(f'{base}/build/builds?definitions={did}&$top=20&queryOrder=finishTimeDescending'
                       f'&statusFilter=completed&properties=none&{API}')
        p(f'  same with statusFilter=completed: {last_cost()} rows={len(b2.get("value") or [])} bytes~{len(str(b2))}')
        s, h, latest = get(f'{base}/build/builds?maxBuildsPerDefinition=1&queryOrder=queueTimeDescending&$top=100&{API}')
        lr = latest.get('value') or []
        p(f'  latest per definition (maxBuildsPerDefinition=1): {last_cost()} rows={len(lr)} '
          f'distinct defs={len({r["definition"]["id"] for r in lr})}')
        s, h, b3 = get(f'{base}/build/builds?definitions={did}&$top=20&queryOrder=finishTimeDescending'
                       f'&minTime={(time.strftime("%Y-%m-%dT00:00:00Z", time.gmtime(time.time() - 30 * 86400)))}&{API}')
        p(f'  minTime=30d: {last_cost()} rows={len(b3.get("value") or [])}')

    blk(f'G  {tag}: release host and test runs')
    vsrm = f'https://vsrm.dev.azure.com/{ORG}/{q(project)}/_apis'
    s, h, rd = get(f'{vsrm}/release/definitions?{API}')
    p(f'  vsrm release/definitions: {last_cost()} count={rd.get("count") if isinstance(rd, dict) else rd}')
    s, h, rl = get(f'{vsrm}/release/releases?$top=5&{API}')
    p(f'  vsrm release/releases?$top=5: {last_cost()} count={rl.get("count") if isinstance(rl, dict) else rl} '
      f'keys={keys((rl.get("value") or [None])[0]) if isinstance(rl, dict) and rl.get("value") else None}')
    s, h, tr = get(f'{base}/test/runs?$top=5&{API}')
    p(f'  test/runs?$top=5: {last_cost()} count={tr.get("count") if isinstance(tr, dict) else str(tr)[:120]}')
    s, h, tp = get(f'{base}/testplan/plans?{API}')
    p(f'  testplan/plans: {last_cost()} count={tp.get("count") if isinstance(tp, dict) else str(tp)[:120]}')

dump_costs()
write_result('s60_widget_queries/s60_widget_queries.md', '\n'.join(OUT) + dump_costs())
