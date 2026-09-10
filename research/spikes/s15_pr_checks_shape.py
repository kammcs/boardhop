"""s15: read-only look at the payload shapes the PR detail page needs for its
second pass: policy evaluations, PR statuses, thread comment ids/dates and
iteration metadata. Prints keys and a few values only; nothing is written."""
import json, os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402

PR = int(os.environ.get('PR_ID', '8319'))
s, h, pr = get(f'{ORG_URL}/_apis/git/pullrequests/{PR}?api-version=7.1')
project = pr['repository']['project']['id']
repo = pr['repository']['id']
P = urllib.parse.quote(project)
base = f'{ORG_URL}/{P}/_apis/git/repositories/{repo}/pullRequests/{PR}'
print('pr keys:', sorted(pr.keys()))
print('mergeStatus:', pr.get('mergeStatus'), 'completionOptions:', pr.get('completionOptions'),
      'autoCompleteSetBy:', bool(pr.get('autoCompleteSetBy')))

art = urllib.parse.quote(f'vstfs:///CodeReview/CodeReviewId/{project}/{PR}', safe='')
s, h, ev = get(f'{ORG_URL}/{P}/_apis/policy/evaluations?artifactId={art}&api-version=7.1-preview.1')
print('evaluations:', s, ev.get('count'))
for e in ev.get('value', [])[:8]:
    c = e.get('configuration', {})
    print('  ', e.get('status'), '|', c.get('type', {}).get('displayName'), '| blocking=', c.get('isBlocking'),
          '| settings keys=', sorted(c.get('settings', {}).keys()), '| context keys=', sorted((e.get('context') or {}).keys()))

s, h, st = get(f'{base}/statuses?api-version=7.1')
print('statuses:', s, st.get('count') if isinstance(st, dict) else str(st)[:200])
for x in (st.get('value', []) if isinstance(st, dict) else [])[:8]:
    print('  ', x.get('state'), '|', x.get('context'), '|', x.get('description'), '| iter', x.get('iterationId'))

s, h, th = get(f'{base}/threads?api-version=7.1')
print('threads:', s, th.get('count'))
for t in th.get('value', [])[:6]:
    cs = t.get('comments', [])
    print('  thread', t['id'], t.get('status'), 'ctx=', bool(t.get('threadContext')), 'props=', sorted((t.get('properties') or {}).keys())[:6])
    for c in cs[:4]:
        print('     comment', c.get('id'), 'parent=', c.get('parentCommentId'), 'type=', c.get('commentType'),
              'pub=', c.get('publishedDate'), 'author keys=', sorted((c.get('author') or {}).keys()),
              'content=', (c.get('content') or '')[:40].replace('\n', ' '))

s, h, its = get(f'{base}/iterations?api-version=7.1')
print('iterations:', s, its.get('count'))
for it in its.get('value', []):
    print('  ', it['id'], it.get('createdDate'), it.get('author', {}).get('displayName'), '|', it.get('description'),
          '| reason=', it.get('reason'), '| keys=', sorted(it.keys()))
