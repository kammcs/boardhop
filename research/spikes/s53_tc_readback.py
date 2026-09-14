"""s53 (read-only): the T-C acceptance readback.

Lists the pull request 8334 attachment store and the newest comments on #15545 and on
PR 8334's threads, so the walkthrough can prove (a) that a cancelled composer uploaded
nothing, (b) the T8 trailing block of each write, and (c) that a fresh pull request
attachment is fetchable where the dead spike blob is not (s51).

Run it once before the writes and once after; `TC_PASS` in the environment keeps both
outputs apart:
    TC_PASS=before python3 research/spikes/_run_with_mcp_creds.py s53_tc_readback.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402

suffix = os.environ.get('TC_PASS', 'now')
_out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results',
                    f's53_tc_readback_{suffix}')
sys.stdout = open(_out, 'w', encoding='utf-8')

st, _, pr = get(f'{ORG_URL}/_apis/git/pullrequests/8334?api-version=7.1')
proj, repo = pr['repository']['project']['id'], pr['repository']['id']

st, _, lst = get(
    f'{ORG_URL}/{proj}/_apis/git/repositories/{repo}/pullRequests/8334'
    f'/attachments?api-version=7.1'
)
print('pr attachments', st, lst.get('count'))
for r in lst.get('value', []):
    print('  ', r['id'], r['displayName'], r['url'])
    # Does the byte fetch work? s51's 500 is the open question.
    bst, hdrs, _ = get(r['url'], raw=True)
    ctype = next((v for k, v in hdrs.items() if k.lower() == 'content-type'), None)
    # With the spike PAT, not the app's Entra token: s51 saw 200 here for the same
    # blob the app could not fetch, so this only says the endpoint itself answers.
    print('      GET bytes ->', bst, ctype)

st, _, threads = get(
    f'{ORG_URL}/{proj}/_apis/git/repositories/{repo}/pullRequests/8334'
    f'/threads?api-version=7.1'
)
rows = []
for t in threads.get('value', []):
    for c in t.get('comments', []):
        rows.append((c['publishedDate'], t['id'], c['id'], t.get('threadContext'),
                     c.get('content')))
rows.sort(reverse=True)
print('newest pr comments')
for published, tid, cid, ctx, content in rows[:4]:
    path = (ctx or {}).get('filePath')
    print('  thread', tid, 'comment', cid, published, 'file', path)
    print('    ', repr(content))

st, _, comments = get(
    f'{ORG_URL}/DevOps%20Mobile%20App/_apis/wit/workItems/15545/comments'
    '?$top=2&order=desc&$expand=renderedText&api-version=7.1-preview.4'
)
print('work item comments', st)
for c in comments.get('comments', []):
    print('  id', c['id'], 'format', c.get('format'))
    print('    text    ', repr(c['text']))
    print('    rendered', repr(c.get('renderedText'))[:600])

st, _, item = get(f'{ORG_URL}/_apis/wit/workItems/15545?$expand=relations&api-version=7.1')
print('relations', st, [r['rel'] for r in item.get('relations', [])])
