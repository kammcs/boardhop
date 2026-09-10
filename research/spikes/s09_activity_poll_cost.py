"""Spike 9: TSTU cost of one planned foreground Activity poll cycle, read from X-RateLimit-Cost.

Budget target from 05 §3.4: ≤ ~20 TSTU per 5-minute window in steady state (the limit is 200).
"""
from lib import *

P = urllib.parse.quote(DEFAULT_PROJECT)
out = ['# Spike 9 — TSTU cost of one Activity poll cycle', f'Org: {ORG_URL} · Project: {DEFAULT_PROJECT}', '',
       'Budget target: ≤ ~20 TSTU per 5-minute window in steady state (limit 200).', '']

s, h, cd = get(f'{ORG_URL}/_apis/connectionData')
me = cd['authenticatedUser']['id']
s, h, projects = get(f'{ORG_URL}/_apis/projects?api-version=7.1')
names = [p['name'] for p in projects.get('value', [])]
out.append(f'projects in org: {len(names)} (fan-out capped at 10 for this measurement)')

# 1. PRs where I am a reviewer, per project (fan-out)
for n in names[:10]:
    get(f'{ORG_URL}/{urllib.parse.quote(n)}/_apis/git/pullrequests?searchCriteria.reviewerId={me}&searchCriteria.status=active&$top=50&api-version=7.1')

# 2. work items assigned to me changed in the last 14 days: one org-wide WIQL, then one batch
s, h, q = post(f'{ORG_URL}/_apis/wit/wiql?$top=100&api-version=7.1',
               {'query': 'SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo]=@Me AND [System.ChangedDate] >= @Today-14 ORDER BY [System.ChangedDate] DESC'})
ids = [w['id'] for w in q.get('workItems', [])] if isinstance(q, dict) else []
if ids:
    post(f'{ORG_URL}/_apis/wit/workitemsbatch?api-version=7.1',
         {'ids': ids[:200], 'fields': ['System.Id', 'System.Title', 'System.State', 'System.ChangedDate', 'System.WorkItemType'], 'errorPolicy': 'omit'})

# 3. builds in the default project in the last day
since = time.strftime('%Y-%m-%dT00:00:00Z', time.gmtime(time.time() - 86400))
get(f'{ORG_URL}/{P}/_apis/build/builds?minTime={since}&$top=25&api-version=7.1')

# 4. work item revisions reporting feed (the only watermark feed), first page
get(f'{ORG_URL}/{P}/_apis/wit/reporting/workitemrevisions?$maxPageSize=200&includeLatestOnly=true&startDateTime={since}&api-version=7.1')

out += [f'work items assigned to me changed in 14 days: {len(ids)}', dump_costs('Per-call cost of one poll cycle')]
write_result('s09_activity_poll_cost.md', '\n'.join(out))
