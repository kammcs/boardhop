"""w15: prepare scratch PR 8334 for the reply/resolve walkthrough and
report the state. Scratch project only. Without arguments it only prints
the threads; with `seed` it makes sure there are four active threads to
exercise the four button paths."""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call  # noqa: E402
from scratch import SCRATCH as PROJECT  # noqa: E402

P = urllib.parse.quote(PROJECT)
PRID = 8334
SEED = 'seed' in sys.argv

s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == PROJECT, proj
s, h, pr = get(f'{ORG_URL}/{P}/_apis/git/pullrequests/{PRID}?api-version=7.1')
assert pr['repository']['project']['id'] == proj['id'], 'PR is not in the scratch project'
RID = pr['repository']['id']
print(f"PR !{PRID} {pr['title']} [{pr['status']}] in {pr['repository']['name']}")
base = f'{ORG_URL}/{P}/_apis/git/repositories/{RID}/pullRequests/{PRID}'


def show():
    s, h, t = get(f'{base}/threads?api-version=7.1')
    rows = []
    for th in t.get('value', []):
        comments = [c for c in (th.get('comments') or [])
                    if not c.get('isDeleted') and c.get('commentType') != 'system']
        if not comments or th.get('isDeleted'):
            continue
        ctx = th.get('threadContext') or {}
        rows.append((th['id'], th.get('status'), ctx.get('filePath'), len(comments),
                     (comments[-1].get('content') or '')[:60].replace('\n', ' ')))
    for r in rows:
        print(f"  thread {r[0]} status={r[1]:8} file={r[2]} comments={r[3]} last={r[4]!r}")
    return rows


rows = show()
if not SEED:
    sys.exit(0)

active = [r for r in rows if r[1] == 'active']
need = 4 - len(active)
for i in range(max(0, need)):
    s, h, created = post(f'{base}/threads?api-version=7.1', {
        'comments': [{
            'parentCommentId': 0,
            'content': f'w15 walkthrough thread {i + 1}: a point to answer from the phone.',
            'commentType': 1,
        }],
        'status': 'active',
    })
    print('  created thread', created.get('id') if isinstance(created, dict) else str(created)[:200])
print('\nafter seeding:')
show()
