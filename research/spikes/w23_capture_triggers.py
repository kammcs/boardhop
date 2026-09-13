"""w23: fire events on the scratch project so the capture hooks (w22)
deliver real payloads to the relay. Scratch project only: patches a
scratch task's title, adds a comment, and adds a reply on scratch PR
8334. Pipelines are not queued here (hosted minutes)."""
import os, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, dump_costs, write_result  # noqa: E402
from scratch import SCRATCH, P, wi_get, wi_patch  # noqa: E402

out = ['# Spike w23 — capture triggers (scratch project)', '']
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == SCRATCH, proj
stamp = time.strftime('%H:%M:%S')

# 1. workitem.updated: rename #15545 (a phase-1 snackbar check task)
s, h, w = wi_get(15545)
base = w['fields']['System.Title'].split(' [w23')[0]
s, h, upd = wi_patch(15545, [
    {'op': 'test', 'path': '/rev', 'value': w['rev']},
    {'op': 'add', 'path': '/fields/System.Title', 'value': f'{base} [w23 {stamp}]'},
])
print('workitem.updated (title):', s)
out.append(f'- workitem.updated on #15545 — HTTP {s}')

# 2. workitem.commented
s, h, c = post(f'{ORG_URL}/{P}/_apis/wit/workItems/15545/comments?api-version=7.1-preview.4',
               {'text': f'w23 capture trigger {stamp}'})
print('workitem.commented:', s)
out.append(f'- workitem.commented on #15545 — HTTP {s}')

# 3. git PR comment event: reply in an existing thread on scratch PR 8334
s, h, pr = get(f'{ORG_URL}/{P}/_apis/git/pullrequests/8334?api-version=7.1')
assert pr['repository']['project']['id'] == proj['id']
rid = pr['repository']['id']
s, h, threads = get(f'{ORG_URL}/{P}/_apis/git/repositories/{rid}/pullRequests/8334/threads?api-version=7.1')
tid = next(t['id'] for t in threads['value'] if not t.get('isDeleted'))
s, h, cm = post(f'{ORG_URL}/{P}/_apis/git/repositories/{rid}/pullRequests/8334/threads/{tid}/comments?api-version=7.1',
                {'content': f'w23 capture trigger {stamp}', 'parentCommentId': 1, 'commentType': 1})
print('pullrequest comment:', s)
out.append(f'- PR 8334 thread {tid} comment — HTTP {s}')

out.append(dump_costs())
write_result('w23_capture_triggers.md', '\n'.join(out))
