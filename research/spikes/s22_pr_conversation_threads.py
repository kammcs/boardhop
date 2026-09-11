"""s22: why is the app's Conversation tab empty on a busy review? Read-only
against CloudCover 2.0 / ServiceDelivery: finds the SHAI AI triage pull
request and counts its threads by shape (file-anchored vs not, status,
system-only) so the tab's filter can be fixed and given status filters."""
import os, sys, urllib.parse
from collections import Counter

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402

PROJECT = 'CloudCover 2.0'
REPO = 'ServiceDelivery'
P = urllib.parse.quote(PROJECT)

s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if r['name'] == REPO)
print('repo', repo['name'], repo['id'])

found = None
for status in ('all',):
    s, h, prs = get(f'{ORG_URL}/{P}/_apis/git/repositories/{repo["id"]}/pullrequests'
                    f'?searchCriteria.status={status}&$top=200&api-version=7.1')
    for pr in prs.get('value', []):
        title = pr.get('title') or ''
        if 'shai' in title.lower() or 'triage' in title.lower():
            print(f"  candidate !{pr['pullRequestId']} [{pr.get('status')}] {title}")
            if found is None:
                found = pr
if not found:
    print('no SHAI/triage PR found'); sys.exit(0)

PRID = found['pullRequestId']
print('\nusing !%d %s (%s)' % (PRID, found['title'], found['status']))
base = f'{ORG_URL}/{P}/_apis/git/repositories/{repo["id"]}/pullRequests/{PRID}'
s, h, threads = get(f'{base}/threads?api-version=7.1')
value = threads.get('value', [])
print('threads:', s, len(value))

shapes = Counter()
statuses = Counter()
props = Counter()
for t in value:
    ctx = t.get('threadContext')
    comments = [c for c in (t.get('comments') or [])
                if not c.get('isDeleted') and c.get('commentType') != 'system']
    kind = ('deleted' if t.get('isDeleted') else
            'system-only' if not comments else
            'file' if ctx and ctx.get('filePath') else
            'context-no-path' if ctx else 'overview')
    shapes[kind] += 1
    if comments:
        statuses[(kind, t.get('status'))] += 1
    for k in (t.get('properties') or {}):
        props[k] += 1

print('\nby shape:', dict(shapes))
print('by (shape, status):')
for k, v in sorted(statuses.items()):
    print('   ', k, v)
print('\nthread property keys seen:', dict(props))

print('\nfirst three non-system threads:')
shown = 0
for t in value:
    comments = [c for c in (t.get('comments') or [])
                if not c.get('isDeleted') and c.get('commentType') != 'system']
    if not comments or shown >= 3:
        continue
    shown += 1
    ctx = t.get('threadContext') or {}
    print(f"  id={t['id']} status={t.get('status')} file={ctx.get('filePath')} "
          f"right={(ctx.get('rightFileStart') or {}).get('line')} comments={len(comments)}")
    print('    keys:', sorted(t.keys()))
    print('    first comment:', (comments[0].get('content') or '')[:120].replace('\n', ' '))
