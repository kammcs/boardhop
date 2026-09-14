"""s52 (read-only): read back what T-B's two writes actually stored — the newest comment on
#15545 and the newest thread comment on PR 8334 — to confirm the trailing block (T8), the
absolute URLs, that `renderedText` carries an <img>, that no AttachedFile relation was added
(T4), and what the pull request attachment store holds."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402

# The raw output stays local (results/ is gitignored): it carries real URLs.
_out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results',
                    's52_comment_readback')
sys.stdout = open(_out, 'w', encoding='utf-8')

PROJECT = 'DevOps%20Mobile%20App'

st, _, comments = get(
    f'{ORG_URL}/{PROJECT}/_apis/wit/workItems/15545/comments'
    '?$top=3&order=desc&$expand=renderedText&api-version=7.1-preview.4'
)
print('comments', st)
for c in comments.get('comments', [])[:1]:
    print('id      ', c['id'], 'format', c.get('format'))
    print('text    ', repr(c['text']))
    print('rendered', repr(c.get('renderedText'))[:400])

st, _, item = get(f'{ORG_URL}/_apis/wit/workItems/15545?$expand=relations&api-version=7.1')
rels = [r['rel'] for r in item.get('relations', [])]
print('relations', st, rels)

st, _, pr = get(f'{ORG_URL}/_apis/git/pullrequests/8334?api-version=7.1')
proj, repo = pr['repository']['project']['id'], pr['repository']['id']
st, _, threads = get(
    f'{ORG_URL}/{proj}/_apis/git/repositories/{repo}/pullRequests/8334/threads?api-version=7.1'
)
newest = None
for t in threads.get('value', []):
    for c in t.get('comments', []):
        if newest is None or c['publishedDate'] > newest[1]['publishedDate']:
            newest = (t, c)
if newest:
    t, c = newest
    print('pr thread', t['id'], 'comment', c['id'], c['publishedDate'])
    print('content  ', repr(c['content']))

st, _, lst = get(
    f'{ORG_URL}/{proj}/_apis/git/repositories/{repo}/pullRequests/8334/attachments?api-version=7.1'
)
print('pr attachments', st)
for r in lst.get('value', []):
    print('  ', r['id'], r['displayName'], r['url'])
