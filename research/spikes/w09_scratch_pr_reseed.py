"""w09: seed a fresh scratch pull request after PR 8319 is completed, so the
app's PR tests keep a target: a branch off main with an edit to /src/app.ts,
a PR, one anchored line comment and one ```suggestion comment (same shape
as w03). Writes only in the scratch project. Idempotent per branch name."""
import os, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scratch import *  # noqa: E402,F403

BRANCH = os.environ.get('BRANCH', 'refs/heads/scratch/pr-tests')
ZERO = '0' * 40

s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if r['name'] == SCRATCH)
R = f'{ORG_URL}/{P}/_apis/git/repositories/{repo["id"]}'
s, h, refs = get(f'{R}/refs?api-version=7.1')
reflist = refs['value']
main_sha = next(r for r in reflist if r['name'] == 'refs/heads/main')['objectId']

s, h, text = get(f'{R}/items?path=/src/app.ts&api-version=7.1', headers={'Accept': 'text/plain'}, raw=True)
lines = text.rstrip('\n').split('\n')
# Change two lines in the middle and append two: same recipe as w03.
changed = [(f'{l} [PR change]' if i in (5, 6) else l) for i, l in enumerate(lines, 1)]
new_text = '\n'.join(changed) + '\nappended A\nappended B\n'

existing = next((r for r in reflist if r['name'] == BRANCH), None)
if existing is None:
    s, h, mk = post(f'{R}/refs?api-version=7.1', [{'name': BRANCH, 'oldObjectId': ZERO, 'newObjectId': main_sha}])
    print('create branch:', s, mk['value'][0].get('success') if s < 300 else str(mk)[:200])
    base = main_sha
else:
    base = existing['objectId']
    print('branch exists at', base[:8])
s, h, push = post(f'{R}/pushes?api-version=7.1', {
    'refUpdates': [{'name': BRANCH, 'oldObjectId': base}],
    'commits': [{'comment': 'Scratch PR: change lines 5-6, append two lines', 'changes': [
        {'changeType': 'edit', 'item': {'path': '/src/app.ts'}, 'newContent': {'content': new_text, 'contentType': 'rawtext'}}]}]})
print('push:', s, push['commits'][0]['commitId'][:8] if s < 300 else str(push)[:200])

s, h, prs = get(f'{R}/pullrequests?searchCriteria.sourceRefName={urllib.parse.quote(BRANCH)}&searchCriteria.status=active&api-version=7.1')
pr = prs['value'][0] if s < 300 and prs.get('value') else None
if pr is None:
    s, h, pr = post(f'{R}/pullrequests?api-version=7.1', {
        'sourceRefName': BRANCH, 'targetRefName': 'refs/heads/main',
        'title': 'Scratch PR for Boardhop tests', 'description': 'Seeded by w09. Safe to complete or abandon.'})
    print('create PR:', s, pr.get('pullRequestId') if s < 300 else str(pr)[:200])
pid = pr['pullRequestId']
PR = f'{R}/pullRequests/{pid}'
print('PR', pid)

s, h, th = get(f'{PR}/threads?api-version=7.1')
if s < 300 and not any(t.get('threadContext') for t in th.get('value', [])):
    s, h, ch = get(f'{PR}/iterations/1/changes?api-version=7.1')
    entry = next(c for c in ch['changeEntries'] if c['item']['path'] == '/src/app.ts')
    ctx = {'changeTrackingId': entry['changeTrackingId'], 'iterationContext': {'firstComparingIteration': 1, 'secondComparingIteration': 1}}
    for line, content in [(6, 'Seeded line comment on line 6.'), (5, 'Try this instead:\n```suggestion\nline 5: suggested by w09\n```')]:
        s, h, t = post(f'{PR}/threads?api-version=7.1', {
            'comments': [{'parentCommentId': 0, 'content': content, 'commentType': 1}], 'status': 1,
            'threadContext': {'filePath': '/src/app.ts', 'rightFileStart': {'line': line, 'offset': 1}, 'rightFileEnd': {'line': line, 'offset': 1}},
            'pullRequestThreadContext': ctx})
        print('thread on line', line, '->', s, t.get('id') if s < 300 else str(t)[:200])
else:
    print('threads already seeded')
