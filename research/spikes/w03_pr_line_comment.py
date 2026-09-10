"""w03: build a repo history and a PR entirely through REST, post an anchored line comment with
changeTrackingId, push a second iteration that shifts line numbers, and read the thread back.
Also posts a ```suggestion-fenced comment for visual inspection in the web UI.
"""
from scratch import *

out = ['# w03 — PR line comment anchoring (scratch project)', f'Project: {SCRATCH}', '']

s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if r['name'] == SCRATCH)
R = f'{ORG_URL}/{P}/_apis/git/repositories/{repo["id"]}'
WEB = f'{ORG_URL}/{P}/_git/{urllib.parse.quote(repo["name"])}'
s, h, refs = get(f'{R}/refs?api-version=7.1')
reflist = refs.get('value', []) if isinstance(refs, dict) else []
out.append(f'repo {repo["name"]} id {repo["id"]}; existing refs: {[r["name"] for r in reflist]}')

ZERO = '0' * 40
APP_V1 = '\n'.join(f'line {i}: original' for i in range(1, 21)) + '\n'
APP_V2 = '\n'.join((f'line {i}: CHANGED in PR' if i in (5, 6) else f'line {i}: original') for i in range(1, 21)) + '\nline 21: added in PR\nline 22: added in PR\n'


def bail():
    write_result('w03_pr_line_comment.md', '\n'.join(out + [dump_costs()]))
    sys.exit()


main = next((r for r in reflist if r['name'] == 'refs/heads/main'), None)
if not main:
    s, h, push = post(f'{R}/pushes?api-version=7.1', {
        'refUpdates': [{'name': 'refs/heads/main', 'oldObjectId': ZERO}],
        'commits': [{'comment': '[spike] initial commit', 'changes': [
            {'changeType': 'add', 'item': {'path': '/README.md'}, 'newContent': {'content': '# Boardhop spike repo\n', 'contentType': 'rawtext'}},
            {'changeType': 'add', 'item': {'path': '/src/app.ts'}, 'newContent': {'content': APP_V1, 'contentType': 'rawtext'}}]}]})
    out += [f'## initial push to main — HTTP {s}', '```json', short(push if s >= 300 else {'commit': push['commits'][0]['commitId']}, 500), '```']
    if s >= 300:
        bail()
    main_sha = push['commits'][0]['commitId']
else:
    main_sha = main['objectId']

branch = 'refs/heads/spike/line-comments'
existing = next((r for r in reflist if r['name'] == branch), None)
if not existing:
    # A new branch must be created as a ref pointing at an existing commit first; a push with the
    # zero oldObjectId has no base tree, so an "edit" change fails with "path does not exist".
    s, h, mk = post(f'{R}/refs?api-version=7.1', [{'name': branch, 'oldObjectId': ZERO, 'newObjectId': main_sha}])
    out += [f'## create branch ref from main — HTTP {s}: `{short(mk, 300) if s >= 300 else mk["value"][0].get("success")}`']
    if s >= 300:
        bail()
    existing = {'objectId': main_sha}
s, h, push2 = post(f'{R}/pushes?api-version=7.1', {
    'refUpdates': [{'name': branch, 'oldObjectId': existing['objectId']}],
    'commits': [{'comment': '[spike] change lines 5-6, add 21-22', 'changes': [
        {'changeType': 'edit', 'item': {'path': '/src/app.ts'}, 'newContent': {'content': APP_V2, 'contentType': 'rawtext'}}]}]})
out += [f'## push branch spike/line-comments — HTTP {s}', '```json', short(push2 if s >= 300 else {'commit': push2['commits'][0]['commitId']}, 500), '```']
if s >= 300:
    bail()
branch_sha = push2['commits'][0]['commitId']

s, h, pr = post(f'{R}/pullrequests?api-version=7.1', {
    'sourceRefName': branch, 'targetRefName': 'refs/heads/main',
    'title': '[spike] w03 line comment anchoring', 'description': 'Created by the Boardhop w03 spike. Safe to abandon.'})
out += [f'## create PR — HTTP {s}', '```json', short(pr if s >= 300 else {'pullRequestId': pr['pullRequestId'], 'url': f'{WEB}/pullrequest/{pr["pullRequestId"]}'}, 500), '```']
if s >= 300:
    bail()
pid = pr['pullRequestId']
PR = f'{R}/pullRequests/{pid}'

s, h, ch = get(f'{PR}/iterations/1/changes?api-version=7.1')
entry = next(c for c in ch['changeEntries'] if c['item']['path'] == '/src/app.ts')
out += [f'## iteration 1 changes — HTTP {s}', f'`{json.dumps({k: entry.get(k) for k in ["changeTrackingId", "changeId", "changeType"]})}` item: `{json.dumps(entry["item"])}`']

thread_body = {
    'comments': [{'parentCommentId': 0, 'content': 'Spike comment anchored to line 6 (right side) of iteration 1.', 'commentType': 1}],
    'status': 1,
    'threadContext': {'filePath': '/src/app.ts', 'rightFileStart': {'line': 6, 'offset': 1}, 'rightFileEnd': {'line': 6, 'offset': 20}},
    'pullRequestThreadContext': {'changeTrackingId': entry['changeTrackingId'], 'iterationContext': {'firstComparingIteration': 1, 'secondComparingIteration': 1}}}
s, h, th = post(f'{PR}/threads?api-version=7.1', thread_body)
out += [f'## post anchored thread — HTTP {s}', '```json', short({k: th.get(k) for k in ['id', 'status', 'threadContext', 'pullRequestThreadContext']} if isinstance(th, dict) else th, 900), '```']

sugg = {
    'comments': [{'parentCommentId': 0, 'content': 'Try this instead:\n```suggestion\nline 5: SUGGESTED replacement\n```', 'commentType': 1}],
    'status': 1,
    'threadContext': {'filePath': '/src/app.ts', 'rightFileStart': {'line': 5, 'offset': 1}, 'rightFileEnd': {'line': 5, 'offset': 20}},
    'pullRequestThreadContext': {'changeTrackingId': entry['changeTrackingId'], 'iterationContext': {'firstComparingIteration': 1, 'secondComparingIteration': 1}}}
s, h, th2 = post(f'{PR}/threads?api-version=7.1', sugg)
out += [f'## post suggestion-fenced comment on line 5 (for visual check) — HTTP {s}', f'thread id: {th2.get("id") if isinstance(th2, dict) else th2}']

APP_V3 = 'inserted A\ninserted B\ninserted C\n' + APP_V2
s, h, push3 = post(f'{R}/pushes?api-version=7.1', {
    'refUpdates': [{'name': branch, 'oldObjectId': branch_sha}],
    'commits': [{'comment': '[spike] insert 3 lines at top', 'changes': [
        {'changeType': 'edit', 'item': {'path': '/src/app.ts'}, 'newContent': {'content': APP_V3, 'contentType': 'rawtext'}}]}]})
out += [f'## push iteration 2 (3 lines inserted at top) — HTTP {s}']
time.sleep(5)

s, h, its = get(f'{PR}/iterations?api-version=7.1')
out.append(f'iterations now: {[i["id"] for i in its.get("value", [])] if isinstance(its, dict) else its}')
s, h, ch2 = get(f'{PR}/iterations/2/changes?$compareTo=1&api-version=7.1')
out += [f'## iteration 2 changes compared to 1 — HTTP {s}', '```json', short(ch2, 500), '```']

s, h, ths = get(f'{PR}/threads?api-version=7.1')
for t in ths.get('value', []) if isinstance(ths, dict) else []:
    if t.get('threadContext'):
        out += [f'## thread {t["id"]} after iteration 2 (default read)', '```json', short({k: t.get(k) for k in ['threadContext', 'pullRequestThreadContext']}, 900), '```']
s, h, ths_i2 = get(f'{PR}/threads?$iteration=2&$baseIteration=0&api-version=7.1')
for t in ths_i2.get('value', []) if isinstance(ths_i2, dict) else []:
    if t.get('threadContext'):
        out += [f'## thread {t["id"]} read with $iteration=2&$baseIteration=0', '```json', short({k: t.get(k) for k in ['threadContext', 'pullRequestThreadContext']}, 900), '```']

s, h, cd = get(f'{ORG_URL}/_apis/connectionData')
me = cd['authenticatedUser']['id']
s, h, v = call('PUT', f'{PR}/reviewers/{me}?api-version=7.1', {'vote': 5})
out += [f'## vote 5 (approve with suggestions) as creator — HTTP {s}: `{ {k: v.get(k) for k in ["vote", "displayName", "isRequired"]} if isinstance(v, dict) else short(v, 300)}`']
s, h, lab = post(f'{PR}/labels?api-version=7.1', {'name': 'spike'})
out += [f'## add label — HTTP {s}: `{lab.get("name") if isinstance(lab, dict) else short(lab, 200)}`']

out += ['', f'PR left ACTIVE for visual inspection: {WEB}/pullrequest/{pid}',
        'Check in the web UI: (1) does the first thread sit on the "line 6: CHANGED in PR" line in the latest iteration? (2) does the suggestion comment render with an Apply button?']
out.append(dump_costs())
write_result('w03_pr_line_comment.md', '\n'.join(out))
