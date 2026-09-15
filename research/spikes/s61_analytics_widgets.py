"""s61 (read-only, OData GETs only): the Analytics data behind the dashboard
widgets that Boardhop cannot compute from REST (research/dash r2).

  0  team / board / iteration lookups (Teams, BoardLocations, Iterations)
  1  CFD: WorkItemBoardSnapshot grouped by DateValue + ColumnName, 30 days
  2  velocity: last 6 dated iterations; completed vs planned, count + points
  3  cycle / lead time: WorkItems completed in the last 60 days
  4  work by state / type: WorkItems grouped by WorkItemType, State
  5  team burndown (widget-style, team + type + date range)
  6  pipelines: PipelineRuns aggregate + last 20 runs; TestRuns/TestResultsDaily
  7  header check: does Analytics ever send X-RateLimit-*?

Same URL form as AnalyticsRepository.odataUri (analytics.dev.azure.com,
_odata/v4.0-preview). Scratch project first; CloudCover 2.0 only for numbers,
field names and timings (no client text is echoed).
"""
import os, re, sys, time, urllib.parse
from datetime import datetime, timedelta, timezone

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG, get, dump_costs, write_result, COST_LOG  # noqa: E402

OUT = []
SCRATCH = 'DevOps Mobile App'
CLIENT = 'CloudCover 2.0'
TODAY = datetime.now(timezone.utc).date()


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def blk(t):
    p(f'\n=== {t} ===')


def q(s):
    return urllib.parse.quote(str(s), safe='')


def day(d):
    return d.strftime('%Y-%m-%d') + 'Z'


def od(project, entity, query):
    """GET one OData query; returns (status, rows, error message, seconds, headers)."""
    url = (f'https://analytics.dev.azure.com/{ORG}/{q(project)}/_odata/v4.0-preview/{entity}?'
           + urllib.parse.quote(query, safe="=&$(),/:'"))
    t0 = time.time()
    s, h, body = get(url)
    dt = round(time.time() - t0, 2)
    rows = body.get('value') if isinstance(body, dict) else None
    err = None
    if s != 200:
        err = (body.get('error') or {}).get('message') if isinstance(body, dict) else str(body)[:200]
    warn = body.get('@vsts.warnings') if isinstance(body, dict) else None
    return s, rows or [], err, dt, h, warn


def show(label, res, sample=True, client=False):
    s, rows, err, dt, h, warn = res
    cost = COST_LOG[-1][3]
    p(f'  {label}: HTTP {s} {dt}s rows={len(rows)} cost_hdr={cost}' + (f' warn={warn}' if warn else ''))
    if err:
        p(f'    error: {str(err)[:300]}')
    elif rows and sample:
        p(f'    keys={sorted(rows[0].keys())}')
        if not client:
            for r in rows[:6]:
                p(f'    {r}')
    return rows


for project in (SCRATCH, CLIENT):
    client = project == CLIENT
    tag = 'client' if client else 'scratch'
    blk(f'0  {tag}: lookups')
    teams = show('Teams', od(project, 'Teams', '$select=TeamSK,TeamName'), client=client)
    if not teams:
        continue
    sk = teams[0]['TeamSK']
    p(f'  using TeamSK={sk}' + ('' if client else f' ({teams[0]["TeamName"]})'))
    boards = show('BoardLocations current, by board',
                  od(project, 'BoardLocations',
                     f"$apply=filter(Team/TeamSK eq {sk} and IsCurrent eq true)"
                     "/groupby((BoardName,BoardLevel,BacklogType,BoardCategoryReferenceName))"),
                  client=client)
    if not boards:
        boards = show('BoardLocations by Team/TeamName fallback',
                      od(project, 'BoardLocations',
                         f"$apply=filter(Team/TeamName eq '{teams[0]['TeamName']}' and IsCurrent eq true)"
                         "/groupby((BoardName,BoardLevel,BacklogType))"), client=client)
    req = next((b for b in boards if b.get('BacklogType') == 'RequirementBacklog'), boards[0] if boards else None)
    board = req['BoardName'] if req else 'Stories'
    p(f'  requirement board = {board!r} (name only, from BoardName)')
    cols = show('BoardLocations columns of that board',
                od(project, 'BoardLocations',
                   f"$apply=filter(Team/TeamSK eq {sk} and BoardName eq '{board}' and IsCurrent eq true)"
                   "/groupby((ColumnName,ColumnOrder,IsColumnSplit))&$orderby=ColumnOrder"), client=client)
    p(f'  column names in order: {[c["ColumnName"] for c in sorted(cols, key=lambda c: c.get("ColumnOrder") or 0)]}')
    iters = show('Iterations of the team, dated, latest 8',
                 od(project, 'Iterations',
                    f"$filter=Teams/any(t:t/TeamSK eq {sk}) and StartDate ne null and StartDate le {day(TODAY)}"
                    "&$orderby=StartDate desc&$top=8&$select=IterationSK,IterationName,StartDate,EndDate,IsEnded"),
                 client=client)
    if not iters:
        iters = show('Iterations (no team filter)',
                     od(project, 'Iterations',
                        f"$filter=StartDate ne null and StartDate le {day(TODAY)}"
                        "&$orderby=StartDate desc&$top=8&$select=IterationSK,IterationName,StartDate,EndDate,IsEnded"),
                     client=client)
    types = show('Processes: requirement-backlog types',
                 od(project, 'Processes',
                    f"$filter=TeamSK eq {sk} and BacklogType eq 'RequirementBacklog'"
                    "&$select=WorkItemType,BacklogName,BacklogType,IsBugType,IsHiddenType"), client=client)
    if not types:
        types = show('Processes without TeamSK', od(project, 'Processes',
                     "$filter=BacklogType eq 'RequirementBacklog'&$select=WorkItemType,BacklogName,BacklogType,IsBugType,IsHiddenType,TeamSK"), client=client)
    req_types = sorted({t['WorkItemType'] for t in types if not t.get('IsHiddenType')}) or ['User Story']
    p(f'  requirement types: {req_types}')
    type_filter = '(' + ' or '.join(f"WorkItemType eq '{t}'" for t in req_types) + ')'

    blk(f'1  {tag}: CFD (WorkItemBoardSnapshot, 30 days)')
    start = TODAY - timedelta(days=30)
    cfd = show('groupby DateValue,ColumnName,ColumnOrder',
               od(project, 'WorkItemBoardSnapshot',
                  f"$apply=filter(Team/TeamSK eq {sk} and BoardName eq '{board}' and DateValue ge {day(start)})"
                  "/groupby((DateValue,ColumnName,ColumnOrder),aggregate($count as Count))&$orderby=DateValue asc"),
               sample=True, client=client)
    if not cfd:
        cfd = show('groupby without ColumnOrder',
                   od(project, 'WorkItemBoardSnapshot',
                      f"$apply=filter(Team/TeamSK eq {sk} and BoardName eq '{board}' and DateValue ge {day(start)})"
                      "/groupby((DateValue,ColumnName),aggregate($count as Count))&$orderby=DateValue asc"),
                   client=client)
    if cfd:
        days = {r['DateValue'][:10] for r in cfd}
        p(f'  distinct days={len(days)} distinct columns={sorted({r["ColumnName"] for r in cfd})} '
          f'bytes~{len(str(cfd))}')
        last = max(days)
        p(f'  last day {last}: {[(r["ColumnName"], r["Count"]) for r in cfd if r["DateValue"].startswith(last)]}')
    show('same via DateSK + IsLastDayOfPeriod probe (weekly)',
         od(project, 'WorkItemBoardSnapshot',
            f"$apply=filter(Team/TeamSK eq {sk} and BoardName eq '{board}' and DateSK ge {start.strftime('%Y%m%d')} "
            "and Date/DayOfWeek eq 1)/groupby((DateValue,ColumnName),aggregate($count as Count))"),
         sample=False, client=client)
    show('lane split (LaneName) 30 days', od(project, 'WorkItemBoardSnapshot',
         f"$apply=filter(Team/TeamSK eq {sk} and BoardName eq '{board}' and DateValue ge {day(start)})"
         "/groupby((LaneName),aggregate($count as Count))"), client=client)

    blk(f'2  {tag}: velocity (last 6 dated iterations)')
    six = iters[:6]
    if six:
        sks = ','.join(i['IterationSK'] for i in six)
        # 2a completed per iteration, by StateCategory, with the completion date compared
        #    to the iteration end (property-to-property compare: does the service allow it?)
        show('completed on time (CompletedDate le Iteration/EndDate)',
             od(project, 'WorkItems',
                f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and {type_filter} and IterationSK in ({sks}) "
                "and StateCategory eq 'Completed' and CompletedDate le Iteration/EndDate)"
                "/groupby((IterationSK),aggregate($count as Count,StoryPoints with sum as SP))"), client=client)
        show('completed late (CompletedDate gt Iteration/EndDate)',
             od(project, 'WorkItems',
                f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and {type_filter} and IterationSK in ({sks}) "
                "and StateCategory eq 'Completed' and CompletedDate gt Iteration/EndDate)"
                "/groupby((IterationSK),aggregate($count as Count,StoryPoints with sum as SP))"), client=client)
        show('by IterationSK + StateCategory (in operator)',
             od(project, 'WorkItems',
                f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and {type_filter} and IterationSK in ({sks}))"
                "/groupby((IterationSK,Iteration/IterationName,Iteration/EndDate,StateCategory),"
                "aggregate($count as Count,StoryPoints with sum as SP))"), client=client)
        rows = show('per-item fallback: id, category, SP, CompletedDate, IterationSK',
                    od(project, 'WorkItems',
                       f"$filter=Teams/any(t:t/TeamSK eq {sk}) and {type_filter} and IterationSK in ({sks})"
                       "&$select=WorkItemId,StateCategory,StoryPoints,CompletedDate,IterationSK"),
                    sample=False, client=client)
        if rows:
            p(f'  per-item rows={len(rows)} bytes~{len(str(rows))} (client can compute late/incomplete)')
        # 2b planned: snapshot on each iteration's start date
        pairs = ' or '.join(f"(IterationSK eq {i['IterationSK']} and DateSK eq {i['StartDate'][:10].replace('-', '')})" for i in six)
        show('planned: WorkItemSnapshot on each start date (or-chain of IterationSK+DateSK pairs)',
             od(project, 'WorkItemSnapshot',
                f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and {type_filter} and ({pairs}))"
                "/groupby((IterationSK,DateSK),aggregate($count as Planned,StoryPoints with sum as SP))"),
             client=client)
        if not client:
            pass
        # 2c one-iteration variant, the way the burndown already does it
        i0 = six[0]
        d0 = i0['StartDate'][:10].replace('-', '')
        show('planned for one iteration (IterationSK eq, DateValue eq)',
             od(project, 'WorkItemSnapshot',
                f"$apply=filter(IterationSK eq {i0['IterationSK']} and DateSK eq {d0} and {type_filter})"
                "/aggregate($count as Planned,StoryPoints with sum as SP)"), client=client)
    else:
        p('  no dated iterations: velocity impossible here')

    blk(f'3  {tag}: cycle / lead time (60 days)')
    start60 = TODAY - timedelta(days=60)
    ct = show('WorkItems completed, CycleTimeDays/LeadTimeDays',
              od(project, 'WorkItems',
                 f"$filter=Teams/any(t:t/TeamSK eq {sk}) and {type_filter} and StateCategory eq 'Completed' "
                 f"and CompletedDate ge {day(start60)}"
                 "&$select=WorkItemId,WorkItemType,State,CycleTimeDays,LeadTimeDays,CompletedDateSK,CompletedDate"
                 "&$orderby=CompletedDate asc"), sample=False, client=client)
    if ct:
        p(f'  keys={sorted(ct[0].keys())} bytes~{len(str(ct))} '
          f'null cycle={sum(1 for r in ct if r.get("CycleTimeDays") is None)} '
          f'null lead={sum(1 for r in ct if r.get("LeadTimeDays") is None)}')
        cyc = [r['CycleTimeDays'] for r in ct if r.get('CycleTimeDays') is not None]
        lead = [r['LeadTimeDays'] for r in ct if r.get('LeadTimeDays') is not None]
        if cyc:
            p(f'  avg cycle={sum(cyc) / len(cyc):.1f}d avg lead={sum(lead) / len(lead):.1f}d n={len(cyc)}')
    show('by backlog level via Processes/any (Requirement)',
         od(project, 'WorkItems',
            f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and Processes/any(p:p/BacklogType eq 'RequirementBacklog') "
            f"and StateCategory eq 'Completed' and CompletedDate ge {day(start60)})"
            "/aggregate($count as Count,CycleTimeDays with average as AvgCycle,LeadTimeDays with average as AvgLead)"),
         client=client)
    show('aggregate only (average + count, 60 days)',
         od(project, 'WorkItems',
            f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and {type_filter} and StateCategory eq 'Completed' "
            f"and CompletedDate ge {day(start60)})"
            "/groupby((CompletedDateSK),aggregate($count as Count,CycleTimeDays with average as AvgCycle,LeadTimeDays with average as AvgLead))"),
         sample=False, client=client)

    blk(f'4  {tag}: work by state / type')
    show('WorkItems groupby WorkItemType,State,StateCategory',
         od(project, 'WorkItems',
            f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and StateCategory ne 'Removed')"
            "/groupby((WorkItemType,State,StateCategory),aggregate($count as Count))"), client=client)
    show('WorkItems groupby AssignedTo/UserName (open only)',
         od(project, 'WorkItems',
            f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and StateCategory in ('Proposed','InProgress','Resolved'))"
            "/groupby((AssignedTo/UserName),aggregate($count as Count))"), sample=False, client=client)
    show('project-wide (no team filter) groupby type', od(project, 'WorkItems',
         "$apply=groupby((WorkItemType,StateCategory),aggregate($count as Count))"), sample=not client, client=client)

    blk(f'5  {tag}: team burndown, widget style (30 days, requirement types)')
    show('WorkItemSnapshot groupby DateValue,StateCategory',
         od(project, 'WorkItemSnapshot',
            f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and {type_filter} and DateValue ge {day(start)} and DateValue le {day(TODAY)})"
            "/groupby((DateValue,StateCategory),aggregate($count as Count,StoryPoints with sum as SP))&$orderby=DateValue asc"),
         sample=False, client=client)
    show('same with RevisedDateSK hint (guidelines)',
         od(project, 'WorkItemSnapshot',
            f"$apply=filter(Teams/any(t:t/TeamSK eq {sk}) and {type_filter} and DateValue ge {day(start)} and DateValue le {day(TODAY)} "
            f"and (RevisedDateSK eq null or RevisedDateSK gt {start.strftime('%Y%m%d')}))"
            "/groupby((DateValue,StateCategory),aggregate($count as Count,StoryPoints with sum as SP))"),
         sample=False, client=client)

    blk(f'6  {tag}: pipelines and tests')
    pipes = show('Pipelines', od(project, 'Pipelines', '$select=PipelineId,PipelineName,PipelineProcessType'),
                 sample=False, client=client)
    if pipes:
        p(f'  pipelines={len(pipes)} keys={sorted(pipes[0].keys())}')
        pid = 139 if not client else pipes[0]['PipelineId']
        start90 = TODAY - timedelta(days=90)
        show('PipelineRuns aggregate 90d',
             od(project, 'PipelineRuns',
                f"$apply=filter(PipelineId eq {pid} and CompletedDate ge {day(start90)})"
                "/aggregate($count as TotalCount,SucceededCount with sum as Succeeded,FailedCount with sum as Failed,"
                "PartiallySucceededCount with sum as Partial,CanceledCount with sum as Canceled)"), client=client)
        runs = show('PipelineRuns last 20',
                    od(project, 'PipelineRuns',
                       f"$filter=PipelineId eq {pid}&$orderby=CompletedDate desc&$top=20"
                       "&$select=PipelineRunId,RunNumber,RunOutcome,RunReason,QueuedDate,StartedDate,CompletedDate,RunDurationSeconds"),
                    sample=False, client=client)
        if runs:
            p(f'  keys={sorted(runs[0].keys())} outcomes={sorted({r.get("RunOutcome") for r in runs})} '
              f'newest completed={str(runs[0].get("CompletedDate"))[:10]}')
        show('PipelineRuns by day (build-history histogram source)',
             od(project, 'PipelineRuns',
                f"$apply=filter(PipelineId eq {pid} and CompletedDate ge {day(start90)})"
                "/groupby((CompletedDateSK,RunOutcome),aggregate($count as Count,RunDurationSeconds with average as AvgSeconds))"),
             sample=False, client=client)
    show('TestRuns $top=1', od(project, 'TestRuns', '$top=1&$select=TestRunId,Workflow,ResultCount,ResultPassCount'), client=client)
    show('TestResultsDaily $top=1', od(project, 'TestResultsDaily', '$top=1'), sample=False, client=client)
    show('TestResultsDaily aggregate 30d',
         od(project, 'TestResultsDaily', f"$apply=filter(DateSK ge {start.strftime('%Y%m%d')})"
            "/groupby((DateSK),aggregate(ResultCount with sum as Total,ResultPassCount with sum as Passed,ResultFailCount with sum as Failed))"),
         sample=False, client=client)

    blk(f'7  {tag}: headers')
    s, h, body = get(f'https://analytics.dev.azure.com/{ORG}/{q(project)}/_odata/v4.0-preview/Teams?$top=1')
    p(f'  header names: {sorted(k.lower() for k in h)}')
    p(f'  ratelimit-ish: { {k: v for k, v in h.items() if "rate" in k.lower() or "retry" in k.lower()} }')

# PipelineRun property names from metadata (names only)
blk('metadata: PipelineRun / TestResultsDaily / WorkItemBoardSnapshot property names')
s, h, meta = get(f'https://analytics.dev.azure.com/{ORG}/{q(SCRATCH)}/_odata/v4.0-preview/$metadata', raw=True)
p(f'  $metadata HTTP {s} bytes={len(meta) if isinstance(meta, str) else 0}')
if s == 200:
    for ent in ('PipelineRun', 'TestResultsDaily', 'TestResultDaily', 'WorkItemBoardSnapshot', 'BoardLocation'):
        m = re.search(rf'<EntityType Name="{ent}".*?</EntityType>', meta, re.S)
        if m:
            props = re.findall(r'<Property Name="([^"]+)"', m.group(0))
            navs = re.findall(r'<NavigationProperty Name="([^"]+)"', m.group(0))
            p(f'  {ent}: {len(props)} props: {props}')
            p(f'    nav: {navs}')
        else:
            p(f'  {ent}: not declared')

dump_costs()
write_result('s61_analytics_widgets/s61_analytics_widgets.md', '\n'.join(OUT) + dump_costs())
