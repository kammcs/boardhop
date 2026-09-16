"""w39: writes, scratch project "DevOps Mobile App" only.

Exercises every pull request write Boardhop does not make yet, on fresh scratch
pull requests, and reads each one back:

  1  branch `scratch/policy-target` (kept) with two branch policies scoped to
     it only: minimum reviewers (1, creator's vote does not count) and require a
     merge strategy (squash + no-fast-forward); so auto-complete can be set
     without the PR merging, and the merge-strategy read has something to show.
  2  PR A (`spike/w39-<ts>-a` → main, created as a draft with a reviewer and a
     work item ref, four files so iteration changes can be paged): publish /
     re-draft, title + description, retarget to the policy branch and back,
     set auto-complete (squash, delete source, transition work items), read it
     back, cancel it; policy evaluations on the policy branch.
  3  reviewers: me with isRequired, the project team (isContainer), flag and
     decline, remove.
  4  threads: file-level (no line), left side, multi-line; edit and delete a
     comment; like / list / unlike.
  5  labels, properties, work item link/unlink (#15545, from the work item
     side), share, statuses (vso.code_status), second push → iteration 2,
     changeTrackingId stability, $compareTo, mergeOptions PATCH.
  6  PR B: deliberate edit/edit conflict between two fresh branches, conflicts
     read, a resolution PATCH attempt, abandon, branches deleted.
  7  cherryPicks and reverts POST (async ref operations), generated branches
     deleted.

Left behind: PR A active (auto-complete cancelled, targeting
`scratch/policy-target`), its source branch, the policy branch and its two
policies. Everything else is abandoned or deleted. Marker "spike w39".

    python _run_with_mcp_creds.py w39_pr_writes.py
"""
import json, os, re, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from scratch import *  # noqa: E402,F403
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402

TS = time.strftime('%Y%m%d-%H%M%S')
WI = 15545
ZERO = '0' * 40
NULL_GUID = '00000000-0000-0000-0000-000000000000'
POLICY_BRANCH = 'refs/heads/scratch/policy-target'
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
OUT = [f'# Spike w39 — pull request writes (scratch, {TS})', '']
ME = {}
LEFT = {'branches': [], 'prs': [], 'policies': []}


def g(v):
    if not isinstance(v, str):
        v = json.dumps(v, indent=1, default=str)
    return re.sub(GUID, lambda m: '<me-guid>' if ME.get('id', '').lower() == m.group(0).lower() else m.group(0), v)


def p(*a):
    line = ' '.join(str(x) if isinstance(x, str) else g(x) for x in a)
    print(g(line))
    OUT.append(g(line))


def sec(t):
    OUT.extend(['', f'## {t}', ''])
    print(f'\n## {t}')


def jpatch(url, body):
    return call('PATCH', url, body, headers={'Content-Type': 'application/json-patch+json'})


def jsonpatch_pr(url, body):
    return call('PATCH', url, body)


def brief_pr(x):
    if not isinstance(x, dict):
        return short(x, 300)
    return short({k: x.get(k) for k in ('pullRequestId', 'status', 'isDraft', 'title', 'targetRefName', 'mergeStatus',
                                          'autoCompleteSetBy', 'completionOptions', 'mergeOptions', 'labels') if k in x}, 900)


def err(x):
    return short(x.get('message') if isinstance(x, dict) else x, 300)


# ------------------------------------------------------------------ 0. who / where
s, _, r = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
ME['id'] = (r.get('authenticatedUser') or {}).get('id', '')
s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if r['name'] == SCRATCH)
REPO = repo['id']
PROJECT_ID = repo['project']['id']
R = f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}'
s, h, refs = get(f'{R}/refs?filter=heads/&api-version=7.1')
reflist = {r['name']: r['objectId'] for r in refs['value']}
main_sha = reflist['refs/heads/main']
s, h, teams = get(f'{ORG_URL}/_apis/projects/{PROJECT_ID}/teams?api-version=7.1')
team = next(t for t in teams['value'] if t['name'] == TEAM)
p(f'repo {REPO}, main {main_sha[:8]}, team `{team["name"]}` {team["id"]}, {len(reflist)} branches')

s, h, text = get(f'{R}/items?path=/src/app.ts&api-version=7.1', headers={'Accept': 'text/plain'}, raw=True)
base_lines = text.rstrip('\n').split('\n')


def mk_branch(name, base_sha):
    s, h, mk = post(f'{R}/refs?api-version=7.1', [{'name': name, 'oldObjectId': ZERO, 'newObjectId': base_sha}])
    ok = s < 300 and mk['value'][0].get('success')
    p(f'- create branch `{name}` from {base_sha[:8]} → {s} success={ok}' + ('' if ok else f' `{short(mk, 300)}`'))
    if ok:
        LEFT['branches'].append(name)
    return ok


def del_branch(name):
    sha = get(f'{R}/refs?filter={urllib.parse.quote(name[len("refs/"):])}&api-version=7.1')[2]
    sha = next((r['objectId'] for r in sha.get('value', []) if r['name'] == name), None)
    if not sha:
        p(f'- delete branch `{name}`: not found')
        return
    s, h, mk = post(f'{R}/refs?api-version=7.1', [{'name': name, 'oldObjectId': sha, 'newObjectId': ZERO}])
    p(f'- delete branch `{name}` → {s} success={mk["value"][0].get("success") if s < 300 else short(mk, 200)}')
    if s < 300 and mk['value'][0].get('success') and name in LEFT['branches']:
        LEFT['branches'].remove(name)


def push(branch, base_sha, comment, changes):
    s, h, r = post(f'{R}/pushes?api-version=7.1', {
        'refUpdates': [{'name': branch, 'oldObjectId': base_sha}],
        'commits': [{'comment': comment, 'changes': changes}]})
    sha = r['commits'][0]['commitId'] if s < 300 else None
    p(f'- push to `{branch}` ({len(changes)} changes) → {s} {sha[:8] if sha else short(r, 300)}')
    return sha


def edit(path, content):
    return {'changeType': 'edit', 'item': {'path': path}, 'newContent': {'content': content, 'contentType': 'rawtext'}}


def add(path, content):
    return {'changeType': 'add', 'item': {'path': path}, 'newContent': {'content': content, 'contentType': 'rawtext'}}


def pr_get(pid):
    return get(f'{R}/pullRequests/{pid}?api-version=7.1')[2]


# ------------------------------------------------------------------ 1. policy branch and policies
sec('1. Policy target branch and its two branch policies')
if POLICY_BRANCH not in reflist:
    mk_branch(POLICY_BRANCH, main_sha)
else:
    p(f'- `{POLICY_BRANCH}` already exists at {reflist[POLICY_BRANCH][:8]}')
LEFT['branches'] = [b for b in LEFT['branches'] if b != POLICY_BRANCH]  # kept on purpose
s, h, pol = get(f'{ORG_URL}/{P}/_apis/git/policy/configurations?repositoryId={REPO}&refName={urllib.parse.quote(POLICY_BRANCH)}&api-version=7.1')
have = {v['type']['id']: v for v in pol.get('value', [])} if s == 200 else {}
p(f'- existing policies on the branch → {s}: {[(v["type"]["displayName"], v["id"]) for v in have.values()]}')
scope = [{'repositoryId': REPO, 'refName': POLICY_BRANCH, 'matchKind': 'Exact'}]
wanted = {
    'fa4e907d-c16b-4a4c-9dfa-4906e5d171dd': ('Minimum number of reviewers', {
        'minimumApproverCount': 1, 'creatorVoteCounts': False, 'allowDownvotes': False, 'resetOnSourcePush': False,
        'requireVoteOnLastIteration': False, 'resetRejectionsOnSourcePush': False, 'blockLastPusherVote': False, 'scope': scope}),
    'fa4e907d-c16b-4a4c-9dfa-4916e5d171ab': ('Require a merge strategy', {
        'allowSquash': True, 'allowNoFastForward': True, 'allowRebase': False, 'allowRebaseMerge': False, 'scope': scope}),
}
for tid, (name, settings) in wanted.items():
    if tid in have:
        p(f'- `{name}` already configured (id {have[tid]["id"]})')
        continue
    s, h, r = post(f'{ORG_URL}/{P}/_apis/policy/configurations?api-version=7.1',
                   {'isEnabled': True, 'isBlocking': True, 'type': {'id': tid}, 'settings': settings})
    p(f'- POST policy/configurations `{name}` → {s}: {("id " + str(r.get("id")) + ", revision " + str(r.get("revision"))) if s < 300 else err(r)}')
    if s < 300:
        LEFT['policies'].append((name, r['id']))
        have[tid] = r
s, h, pol = get(f'{ORG_URL}/{P}/_apis/git/policy/configurations?repositoryId={REPO}&refName={urllib.parse.quote(POLICY_BRANCH)}&api-version=7.1')
p(f'- read back git-scoped → {s}: {[(v["type"]["displayName"], v["isBlocking"], {k: v2 for k, v2 in v["settings"].items() if k != "scope"}) for v in pol.get("value", [])]}')
POLICIES_OK = len(pol.get('value', [])) >= 2 if s == 200 else False

# ------------------------------------------------------------------ 2. PR A
sec('2. PR A: create (draft, reviewer, work item ref), publish, edit, retarget, auto-complete')
BR_A = f'refs/heads/spike/w39-{TS}-a'
mk_branch(BR_A, main_sha)
a_lines = [(f'{l} [w39 A]' if i in (5, 6) else l) for i, l in enumerate(base_lines, 1)]
sha_a1 = push(BR_A, main_sha, 'spike w39: PR A, edit lines 5-6 and add three files', [
    edit('/src/app.ts', '\n'.join(a_lines) + '\n'),
    add('/spike/w39/one.txt', 'one\n'), add('/spike/w39/two.txt', 'two\n'), add('/spike/w39/three.txt', 'three\n')])
body = {'sourceRefName': BR_A, 'targetRefName': 'refs/heads/main',
        'title': f'spike w39 PR A ({TS})', 'description': 'Created by spike w39 as a draft. Safe to abandon.',
        'isDraft': True, 'reviewers': [{'id': ME['id']}], 'workItemRefs': [{'id': str(WI)}],
        'labels': [{'name': 'w39-on-create'}]}
s, h, pra = post(f'{R}/pullrequests?supportsIterations=true&api-version=7.1', body)
p(f'POST pullrequests (isDraft, reviewers[me], workItemRefs[#{WI}], labels) → {s}: {brief_pr(pra)}')
if s >= 300:
    write_result('w39_pr_writes/report.md', '\n'.join(OUT))
    sys.exit('PR A creation failed')
A = pra['pullRequestId']
LEFT['prs'].append(A)
PRA = f'{R}/pullRequests/{A}'
p(f'- reviewers on create: {[(r.get("vote"), r.get("isRequired"), r.get("isContainer")) for r in pra.get("reviewers", [])]}; labels: {pra.get("labels")}')
s, h, wis = get(f'{PRA}/workitems?api-version=7.1')
p(f'- GET workitems after create → {s}: {[w.get("id") for w in wis.get("value", [])]}')
s, h, lb = get(f'{PRA}/labels?api-version=7.1')
p(f'- GET labels after create → {s}: {[(l.get("id"), l.get("name"), l.get("active")) for l in lb.get("value", [])]}')

# draft toggle
s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'isDraft': False})
p(f'PATCH isDraft=false (publish) → {s}: isDraft={r.get("isDraft") if s < 300 else err(r)}')
s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'isDraft': True})
p(f'PATCH isDraft=true (mark as draft) → {s}: isDraft={r.get("isDraft") if s < 300 else err(r)}')
s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'isDraft': False})
p(f'PATCH isDraft=false again → {s}: isDraft={r.get("isDraft") if s < 300 else err(r)}')
# title, description
s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'title': f'spike w39 PR A ({TS}) retitled', 'description': 'Description edited by spike w39.\n\nSecond paragraph.'})
p(f'PATCH title+description → {s}: title ends with "retitled": {str(r.get("title", "")).endswith("retitled") if s < 300 else err(r)}, description len {len(r.get("description", "")) if s < 300 else "-"}')
# retarget
s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'targetRefName': POLICY_BRANCH})
p(f'PATCH targetRefName → policy branch → {s}: targetRefName={r.get("targetRefName") if s < 300 else err(r)}, mergeStatus={r.get("mergeStatus") if s < 300 else "-"}')
time.sleep(3)
s, h, its = get(f'{PRA}/iterations?api-version=7.1')
p(f'- iterations after retarget: {[(i["id"], i.get("reason"), i.get("oldTargetRefName"), i.get("newTargetRefName")) for i in its.get("value", [])]}')
s, h, ev = get(f'{ORG_URL}/{P}/_apis/policy/evaluations?artifactId={urllib.parse.quote("vstfs:///CodeReview/CodeReviewId/" + PROJECT_ID + "/" + str(A), safe="")}&api-version=7.1-preview.1')
p(f'- policy evaluations on the policy branch → {s}: {[(e["configuration"]["type"]["displayName"], e.get("status"), e["configuration"].get("isBlocking")) for e in ev.get("value", [])] if s == 200 else err(ev)}')
pra = pr_get(A)
p(f'- PR A now: {brief_pr(pra)}')

# auto-complete set
ac_body = {'autoCompleteSetBy': {'id': ME['id']},
           'completionOptions': {'mergeStrategy': 'squash', 'deleteSourceBranch': True, 'transitionWorkItems': True,
                                 'mergeCommitMessage': f'spike w39: squash merge message for PR {A}'}}
s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', ac_body)
p(f'PATCH set auto-complete (squash, deleteSource, transitionWorkItems) → {s}: {brief_pr(r) if s < 300 else err(r)}')
time.sleep(3)
pra = pr_get(A)
p(f'- read back: status={pra.get("status")}, autoCompleteSetBy={"set" if pra.get("autoCompleteSetBy") else None}, completionOptions={short(pra.get("completionOptions"), 400)}')
s, h, th = get(f'{PRA}/threads?api-version=7.1')
ac_threads = [t for t in th.get('value', []) if (t.get('properties') or {}).get('CodeReviewThreadType', {}).get('$value') == 'AutoCompleteUpdate']
p(f'- AutoCompleteUpdate system threads: {len(ac_threads)}; properties of the last: {short({k: v.get("$value") for k, v in (ac_threads[-1].get("properties") or {}).items() if "Identity" not in k} if ac_threads else None, 400)}; content `{short((ac_threads[-1].get("comments") or [{}])[0].get("content") if ac_threads else None, 200)}`')
if pra.get('status') == 'active':
    # a rebase strategy the policy does not allow, while auto-complete is set
    s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'completionOptions': {'mergeStrategy': 'rebase', 'deleteSourceBranch': True}})
    p(f'PATCH completionOptions.mergeStrategy=rebase (policy forbids) → {s}: {short(r.get("completionOptions") if s < 300 else err(r), 300)}')
    s, h, ev = get(f'{ORG_URL}/{P}/_apis/policy/evaluations?artifactId={urllib.parse.quote("vstfs:///CodeReview/CodeReviewId/" + PROJECT_ID + "/" + str(A), safe="")}&api-version=7.1-preview.1')
    p(f'- policy evaluations now: {[(e["configuration"]["type"]["displayName"], e.get("status")) for e in ev.get("value", [])] if s == 200 else err(ev)}')
    # cancel with the null guid
    s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'autoCompleteSetBy': {'id': NULL_GUID}})
    p(f'PATCH autoCompleteSetBy null guid (cancel) → {s}: {brief_pr(r) if s < 300 else err(r)}')
    pra = pr_get(A)
    p(f'- read back: autoCompleteSetBy present={bool(pra.get("autoCompleteSetBy"))}, completionOptions={short(pra.get("completionOptions"), 300)}')
    if pra.get('autoCompleteSetBy'):
        s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'autoCompleteSetBy': None})
        p(f'PATCH autoCompleteSetBy: null → {s}: {brief_pr(r) if s < 300 else err(r)}')
        pra = pr_get(A)
        p(f'- read back: autoCompleteSetBy present={bool(pra.get("autoCompleteSetBy"))}')
    s, h, th = get(f'{PRA}/threads?api-version=7.1')
    ac_threads = [t for t in th.get('value', []) if (t.get('properties') or {}).get('CodeReviewThreadType', {}).get('$value') == 'AutoCompleteUpdate']
    p(f'- AutoCompleteUpdate threads now {len(ac_threads)}; last properties: {short({k: v.get("$value") for k, v in (ac_threads[-1].get("properties") or {}).items() if "Identity" not in k} if ac_threads else None, 300)}')
    # completion options can be stored without auto-complete? (the web's Complete dialog remembers them)
    s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'completionOptions': {'mergeStrategy': 'noFastForward', 'deleteSourceBranch': False}})
    p(f'PATCH completionOptions alone (no auto-complete) → {s}: completionOptions={short(r.get("completionOptions") if s < 300 else err(r), 300)}, autoComplete={bool(r.get("autoCompleteSetBy")) if s < 300 else "-"}')
else:
    p('!! PR A is no longer active after auto-complete; the policy did not hold it. Skipping the cancel path.')

# retarget back to main and again to the policy branch (both directions)
s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'targetRefName': 'refs/heads/main'})
p(f'PATCH targetRefName → main → {s}: {r.get("targetRefName") if s < 300 else err(r)}')
s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'targetRefName': POLICY_BRANCH})
p(f'PATCH targetRefName → policy branch again → {s}: {r.get("targetRefName") if s < 300 else err(r)}')
# mergeOptions / restart merge
s, h, r = jsonpatch_pr(f'{PRA}?api-version=7.1', {'mergeOptions': {'detectRenameFalsePositives': False, 'disableRenames': False, 'conflictAuthorshipCommits': False}})
p(f'PATCH mergeOptions (restart merge?) → {s}: mergeStatus={r.get("mergeStatus") if s < 300 else err(r)}, mergeOptions={short(r.get("mergeOptions") if s < 300 else None, 200)}')
time.sleep(2)
pra = pr_get(A)
p(f'- PR A after mergeOptions: mergeStatus={pra.get("mergeStatus")}, lastMergeCommit={str((pra.get("lastMergeCommit") or {}).get("commitId"))[:8]}')
s, h, its = get(f'{PRA}/iterations?api-version=7.1')
p(f'- iterations: {[(i["id"], i.get("reason")) for i in its.get("value", [])]}')

# ------------------------------------------------------------------ 3. reviewers
sec('3. Reviewers')
s, h, r = call('PUT', f'{PRA}/reviewers/{ME["id"]}?api-version=7.1', {'id': ME['id'], 'vote': 0, 'isRequired': True})
p(f'PUT reviewers/me isRequired=true → {s}: isRequired={r.get("isRequired") if s < 300 else err(r)}, keys `{sorted(r.keys()) if s < 300 else "-"}`')
s, h, r = call('PUT', f'{PRA}/reviewers/{ME["id"]}?api-version=7.1', {'id': ME['id'], 'vote': 0, 'isRequired': False})
p(f'PUT reviewers/me isRequired=false → {s}: isRequired={r.get("isRequired") if s < 300 else err(r)}')
s, h, r = call('PUT', f'{PRA}/reviewers/{team["id"]}?api-version=7.1', {'id': team['id'], 'vote': 0})
p(f'PUT reviewers/{{team}} → {s}: isContainer={r.get("isContainer") if s < 300 else err(r)}, displayName set={bool(r.get("displayName")) if s < 300 else "-"}, votedFor={r.get("votedFor") if s < 300 else "-"}')
s, h, r = call('PUT', f'{PRA}/reviewers/{ME["id"]}?api-version=7.1', {'id': ME['id'], 'vote': 10})
p(f'PUT reviewers/me vote=10 (member of the team) → {s}: vote={r.get("vote") if s < 300 else err(r)}')
s, h, rv = get(f'{PRA}/reviewers?api-version=7.1')
p(f'- GET reviewers: {[(x.get("vote"), x.get("isRequired"), x.get("isContainer"), [v.get("vote") for v in (x.get("votedFor") or [])]) for x in rv.get("value", [])]}')
s, h, ev = get(f'{ORG_URL}/{P}/_apis/policy/evaluations?artifactId={urllib.parse.quote("vstfs:///CodeReview/CodeReviewId/" + PROJECT_ID + "/" + str(A), safe="")}&api-version=7.1-preview.1')
p(f'- policy evaluations with the creator approved (creatorVoteCounts=false): {[(e["configuration"]["type"]["displayName"], e.get("status")) for e in ev.get("value", [])] if s == 200 else err(ev)}')
s, h, r = call('PATCH', f'{PRA}/reviewers/{ME["id"]}?api-version=7.1', {'isFlagged': True})
p(f'PATCH reviewers/me isFlagged=true → {s}: isFlagged={r.get("isFlagged") if s < 300 else err(r)}')
s, h, r = call('PATCH', f'{PRA}/reviewers/{ME["id"]}?api-version=7.1', {'hasDeclined': True})
p(f'PATCH reviewers/me hasDeclined=true → {s}: hasDeclined={r.get("hasDeclined") if s < 300 else err(r)}, vote={r.get("vote") if s < 300 else "-"}')
s, h, r = call('PATCH', f'{PRA}/reviewers/{ME["id"]}?api-version=7.1', {'hasDeclined': False, 'isFlagged': False})
p(f'PATCH reviewers/me hasDeclined=false, isFlagged=false → {s}: {(r.get("hasDeclined"), r.get("isFlagged")) if s < 300 else err(r)}')
s, h, r = call('PATCH', f'{PRA}/reviewers?api-version=7.1', [{'id': ME['id'], 'vote': 0}])
p(f'PATCH reviewers (batch reset vote) → {s}: {short(r, 200) if s >= 300 else [(x.get("vote")) for x in (r.get("value") if isinstance(r, dict) else r or [])]}')
s, h, r = call('DELETE', f'{PRA}/reviewers/{team["id"]}?api-version=7.1')
p(f'DELETE reviewers/{{team}} → {s} body `{short(r, 100)}`')
s, h, r = call('POST', f'{PRA}/reviewers?api-version=7.1', [{'id': ME['id'], 'isRequired': True}])
p(f'POST reviewers (batch add, isRequired) → {s}: {[(x.get("isRequired"), x.get("vote")) for x in r.get("value", [])] if s < 300 else err(r)}')
s, h, r = call('DELETE', f'{PRA}/reviewers/{ME["id"]}?api-version=7.1')
p(f'DELETE reviewers/me → {s}')
s, h, rv = get(f'{PRA}/reviewers?api-version=7.1')
p(f'- GET reviewers after removals: {len(rv.get("value", []))}')
s, h, th = get(f'{PRA}/threads?api-version=7.1')
rvu = [t for t in th.get('value', []) if (t.get('properties') or {}).get('CodeReviewThreadType', {}).get('$value') == 'ReviewersUpdate']
p(f'- ReviewersUpdate system threads: {len(rvu)}; property keys of one: `{sorted((rvu[-1].get("properties") or {}).keys()) if rvu else []}`; contents: {[short((t.get("comments") or [{}])[0].get("content"), 80) for t in rvu]}')

# ------------------------------------------------------------------ 4. threads and comments
sec('4. Threads: file-level, left side, multi-line; edit, delete, like')
s, h, ch = get(f'{PRA}/iterations/1/changes?api-version=7.1')
entry = next(c for c in ch['changeEntries'] if c['item']['path'] == '/src/app.ts')
ctx = {'changeTrackingId': entry['changeTrackingId'], 'iterationContext': {'firstComparingIteration': 1, 'secondComparingIteration': 1}}


def thread(content, tc, prc=ctx, status=1):
    body = {'comments': [{'parentCommentId': 0, 'content': content, 'commentType': 1}], 'status': status,
            'threadContext': tc}
    if prc:
        body['pullRequestThreadContext'] = prc
    return post(f'{PRA}/threads?api-version=7.1', body)


s, h, t_file = thread('spike w39: file-level comment (no line).', {'filePath': '/src/app.ts'})
p(f'POST file-level thread (filePath only) → {s}: id {t_file.get("id") if s < 300 else err(t_file)}, threadContext back `{short(t_file.get("threadContext") if s < 300 else None, 200)}`')
s, h, t_left = thread('spike w39: left-side comment on original line 5.',
                      {'filePath': '/src/app.ts', 'leftFileStart': {'line': 5, 'offset': 1}, 'leftFileEnd': {'line': 5, 'offset': 1}})
p(f'POST left-side thread → {s}: id {t_left.get("id") if s < 300 else err(t_left)}, threadContext back `{short(t_left.get("threadContext") if s < 300 else None, 300)}`')
s, h, t_multi = thread('spike w39: multi-line right range 5-6.',
                       {'filePath': '/src/app.ts', 'rightFileStart': {'line': 5, 'offset': 1}, 'rightFileEnd': {'line': 6, 'offset': 10}})
p(f'POST multi-line right thread → {s}: id {t_multi.get("id") if s < 300 else err(t_multi)}')
s, h, t_pending = thread('spike w39: a pending-status thread.', {'filePath': '/src/app.ts', 'rightFileStart': {'line': 7, 'offset': 1}, 'rightFileEnd': {'line': 7, 'offset': 1}}, status='pending')
p(f'POST thread with status=pending → {s}: status back {t_pending.get("status") if s < 300 else err(t_pending)}')
s, h, t_new = thread('spike w39: thread on an added file.', {'filePath': '/spike/w39/one.txt', 'rightFileStart': {'line': 1, 'offset': 1}, 'rightFileEnd': {'line': 1, 'offset': 1}},
                     prc={'changeTrackingId': next(c['changeTrackingId'] for c in ch['changeEntries'] if c['item']['path'] == '/spike/w39/one.txt'), 'iterationContext': {'firstComparingIteration': 1, 'secondComparingIteration': 1}})
p(f'POST thread on an added file → {s}: id {t_new.get("id") if s < 300 else err(t_new)}')
tid = t_multi.get('id') if isinstance(t_multi, dict) else None
if tid:
    s, h, c2 = post(f'{PRA}/threads/{tid}/comments?api-version=7.1', {'parentCommentId': 1, 'content': 'spike w39: reply, to be edited then deleted.', 'commentType': 1})
    p(f'POST reply → {s}: comment id {c2.get("id") if s < 300 else err(c2)}')
    cid = c2.get('id')
    s, h, r = call('PATCH', f'{PRA}/threads/{tid}/comments/{cid}?api-version=7.1', {'content': 'spike w39: reply, **edited**.'})
    p(f'PATCH comment content (edit) → {s}: content back `{short(r.get("content") if s < 300 else err(r), 100)}`, lastContentUpdatedDate != publishedDate: {r.get("lastContentUpdatedDate") != r.get("publishedDate") if s < 300 else "-"}')
    s, h, r = post(f'{PRA}/threads/{tid}/comments/{cid}/likes?api-version=7.1', None)
    p(f'POST likes → {s} body `{short(r, 80)}`')
    s, h, lk = get(f'{PRA}/threads/{tid}/comments/{cid}/likes?api-version=7.1')
    p(f'GET likes → {s}: count {lk.get("count")}, entry keys `{sorted(lk["value"][0].keys()) if lk.get("value") else []}`')
    s, h, r = get(f'{PRA}/threads/{tid}?api-version=7.1')
    p(f'- usersLiked on the comment via GET thread: {[len(c.get("usersLiked") or []) for c in r.get("comments", [])]}')
    s, h, r = post(f'{PRA}/threads/{tid}/comments/{cid}/likes?api-version=7.1', None)
    p(f'POST likes again (idempotent?) → {s}')
    s, h, r = call('DELETE', f'{PRA}/threads/{tid}/comments/{cid}/likes?api-version=7.1')
    p(f'DELETE likes → {s}')
    s, h, lk = get(f'{PRA}/threads/{tid}/comments/{cid}/likes?api-version=7.1')
    p(f'GET likes after unlike → {s}: count {lk.get("count")}')
    s, h, r = call('DELETE', f'{PRA}/threads/{tid}/comments/{cid}?api-version=7.1')
    p(f'DELETE comment → {s} body `{short(r, 80)}`')
    s, h, r = get(f'{PRA}/threads/{tid}?api-version=7.1')
    p(f'- thread after delete: comments {[(c.get("id"), c.get("isDeleted"), c.get("content")) for c in r.get("comments", [])]}, thread isDeleted {r.get("isDeleted")}')
    s, h, r = call('DELETE', f'{PRA}/threads/{tid}/comments/1?api-version=7.1')
    p(f'DELETE root comment 1 of a thread → {s}')
    s, h, r = get(f'{PRA}/threads/{tid}?api-version=7.1')
    p(f'- thread after root delete: isDeleted {r.get("isDeleted")}, comments {[(c.get("id"), c.get("isDeleted")) for c in r.get("comments", [])]}')
    if isinstance(t_left, dict) and t_left.get('id'):
        s, h, r = call('PATCH', f'{PRA}/threads/{t_left["id"]}?api-version=7.1', {'properties': {'boardhop.spike': {'$type': 'System.String', '$value': 'w39'}}})
        p(f'PATCH thread properties (custom) → {s}: properties keys `{sorted((r.get("properties") or {}).keys()) if s < 300 else err(r)}`')
s, h, th = get(f'{PRA}/threads?$iteration=1&$baseIteration=0&api-version=7.1')
p(f'- threads read at $iteration=1: {[(t["id"], (t.get("threadContext") or {}).get("filePath"), bool((t.get("threadContext") or {}).get("leftFileStart")), bool((t.get("threadContext") or {}).get("rightFileStart")), t.get("status")) for t in th.get("value", []) if t.get("threadContext")]}')

# ------------------------------------------------------------------ 5. labels, properties, work items, share, statuses, second push
sec('5. Labels, properties, work item link, share, statuses, iteration 2')
s, h, r = post(f'{PRA}/labels?api-version=7.1', {'name': 'boardhop-spike'})
p(f'POST labels {{name}} → {s}: `{short(r, 200)}`')
label_id = r.get('id') if s < 300 else None
s, h, r = post(f'{PRA}/labels?api-version=7.1', {'name': 'boardhop-spike'})
p(f'POST the same label again → {s}: `{short(r if s >= 300 else {k: r.get(k) for k in ("id", "name")}, 200)}`')
s, h, lb = get(f'{PRA}/labels?api-version=7.1')
p(f'GET labels → {[(l.get("name"), l.get("active")) for l in lb.get("value", [])]}')
pra = pr_get(A)
p(f'- PR.labels on GET pullRequests/{{id}}: {short(pra.get("labels"), 200)}')
s, h, r = call('DELETE', f'{PRA}/labels/{urllib.parse.quote("boardhop-spike")}?api-version=7.1')
p(f'DELETE labels/{{name}} → {s}')
s, h, r = call('DELETE', f'{PRA}/labels/{label_id}?api-version=7.1') if label_id else (0, {}, {})
p(f'DELETE labels/{{id}} (already removed) → {s}')
s, h, r = call('DELETE', f'{PRA}/labels/w39-on-create?api-version=7.1')
p(f'DELETE labels/w39-on-create → {s}')
s, h, lb = get(f'{PRA}/labels?api-version=7.1')
p(f'GET labels after deletes → {len(lb.get("value", []))}')
# properties
s, h, r = jpatch(f'{PRA}/properties?api-version=7.1', [{'op': 'add', 'path': '/boardhop.spike', 'value': 'w39'}])
p(f'PATCH properties add → {s}: keys `{sorted((r.get("value") or {}).keys()) if s < 300 else err(r)}`')
s, h, r = jpatch(f'{PRA}/properties?api-version=7.1', [{'op': 'remove', 'path': '/boardhop.spike'}])
p(f'PATCH properties remove → {s}: keys `{sorted((r.get("value") or {}).keys()) if s < 300 else err(r)}`')
# work items: unlink the create-time link and re-link from the work item side
s, h, w = wi_get(WI)
rels = w.get('relations') or []
art = f'vstfs:///Git/PullRequestId/{PROJECT_ID}/{REPO}/{A}'
idx = next((i for i, rel in enumerate(rels) if rel.get('rel') == 'ArtifactLink' and rel.get('url', '').lower() == art.lower()), None)
p(f'- work item #{WI} rev {w.get("rev")}: ArtifactLink to PR A at relations[{idx}]: `{short(rels[idx] if idx is not None else None, 300)}`')
if idx is not None:
    s, h, r = wi_patch(WI, [{'op': 'test', 'path': '/rev', 'value': w['rev']}, {'op': 'remove', 'path': f'/relations/{idx}'}])
    p(f'PATCH work item remove relations/{idx} (unlink) → {s}: rev {r.get("rev") if s < 300 else err(r)}')
    s, h, wis = get(f'{PRA}/workitems?api-version=7.1')
    p(f'- GET PR workitems after unlink → {[x.get("id") for x in wis.get("value", [])]}')
s, h, w = wi_get(WI)
s, h, r = wi_patch(WI, [{'op': 'test', 'path': '/rev', 'value': w['rev']},
                        {'op': 'add', 'path': '/relations/-', 'value': {'rel': 'ArtifactLink', 'url': art, 'attributes': {'name': 'Pull Request', 'comment': 'spike w39'}}}])
p(f'PATCH work item add ArtifactLink (link) → {s}: rev {r.get("rev") if s < 300 else err(r)}')
s, h, wis = get(f'{PRA}/workitems?api-version=7.1')
p(f'- GET PR workitems after link → {[x.get("id") for x in wis.get("value", [])]}')
s, h, r = post(f'{PRA}/workitems?api-version=7.1', [{'id': str(WI)}])
p(f'POST pullRequests/{{id}}/workitems (undocumented) → {s}: `{short(r, 150)}`')
# share
s, h, r = post(f'{PRA}/share?api-version=7.1', {'receivers': [{'id': ME['id']}], 'message': 'spike w39 share (self)'})
p(f'POST share (to me) → {s} body `{short(r, 150)}`')
# statuses
s, h, r = post(f'{PRA}/statuses?api-version=7.1', {'state': 'succeeded', 'description': 'spike w39 status', 'context': {'name': 'spike', 'genre': 'boardhop'}, 'targetUrl': 'https://example.invalid/w39'})
p(f'POST statuses → {s}: {short({k: r.get(k) for k in ("id", "state", "iterationId", "context")} if s < 300 else err(r), 300)}')
s, h, r = post(f'{PRA}/iterations/1/statuses?api-version=7.1', {'state': 'pending', 'description': 'spike w39 iteration status', 'context': {'name': 'spike-iter', 'genre': 'boardhop'}})
p(f'POST iterations/1/statuses → {s}: {short({k: r.get(k) for k in ("id", "state", "iterationId")} if s < 300 else err(r), 200)}')
s, h, st = get(f'{PRA}/statuses?api-version=7.1')
p(f'GET statuses → {[(x.get("id"), x.get("state"), x.get("iterationId"), x["context"]["name"]) for x in st.get("value", [])]}')
# second push → iteration 2
a_lines2 = [(f'{l} [w39 A2]' if i == 8 else l) for i, l in enumerate(a_lines, 1)]
sha_a2 = push(BR_A, sha_a1, 'spike w39: PR A second push, edit line 8 and one.txt', [edit('/src/app.ts', '\n'.join(a_lines2) + '\n'), edit('/spike/w39/one.txt', 'one, edited\n')])
time.sleep(4)
s, h, its = get(f'{PRA}/iterations?api-version=7.1')
p(f'- iterations: {[(i["id"], i.get("reason")) for i in its.get("value", [])]}')
last = its['value'][-1]['id']
s, h, c2 = get(f'{PRA}/iterations/{last}/changes?api-version=7.1')
p(f'- iteration {last} changes (vs base): {[(e.get("changeTrackingId"), e.get("changeId"), e["item"]["path"], e.get("changeType")) for e in c2.get("changeEntries", [])]}')
s, h, c1 = get(f'{PRA}/iterations/1/changes?api-version=7.1')
p(f'- iteration 1 changes: {[(e.get("changeTrackingId"), e.get("changeId"), e["item"]["path"]) for e in c1.get("changeEntries", [])]}')
s, h, cc = get(f'{PRA}/iterations/{last}/changes?$compareTo=1&api-version=7.1')
p(f'- iteration {last} $compareTo=1: {[(e.get("changeTrackingId"), e.get("changeId"), e["item"]["path"], e.get("changeType")) for e in cc.get("changeEntries", [])]}')
s, h, pg = get(f'{PRA}/iterations/{last}/changes?$top=2&api-version=7.1')
p(f'- paging $top=2 → entries {len(pg.get("changeEntries", []))}, nextSkip {pg.get("nextSkip")}, nextTop {pg.get("nextTop")}')
if pg.get('nextSkip'):
    s, h, pg2 = get(f'{PRA}/iterations/{last}/changes?$top={pg["nextTop"]}&$skip={pg["nextSkip"]}&api-version=7.1')
    p(f'- page 2 → entries {len(pg2.get("changeEntries", []))}, nextSkip {pg2.get("nextSkip")}, nextTop {pg2.get("nextTop")}')
s, h, pc = get(f'{PRA}/commits?$top=1&api-version=7.1')
p(f'- commits?$top=1 → {len(pc.get("value", []))}, continuation `{h.get("x-ms-continuationtoken") or h.get("X-MS-ContinuationToken")}`')
s, h, th = get(f'{PRA}/threads?$iteration={last}&$baseIteration=0&api-version=7.1')
p(f'- threads at iteration {last}: {[(t["id"], (t.get("threadContext") or {}).get("filePath"), ((t.get("threadContext") or {}).get("rightFileStart") or {}).get("line"), ((t.get("threadContext") or {}).get("leftFileStart") or {}).get("line"), short((t.get("pullRequestThreadContext") or {}).get("trackingCriteria"), 120)) for t in th.get("value", []) if t.get("threadContext")]}')
s, h, th = get(f'{PRA}/threads?api-version=7.1')
p(f'- system thread kinds on PR A so far: {sorted({(t.get("properties") or {}).get("CodeReviewThreadType", {}).get("$value", "-") for t in th.get("value", [])})}')
kinds = {}
for t in th.get('value', []):
    k = (t.get('properties') or {}).get('CodeReviewThreadType', {}).get('$value')
    if k and k not in kinds:
        kinds[k] = (sorted(t['properties'].keys()), short((t.get('comments') or [{}])[0].get('content'), 120))
for k, v in kinds.items():
    p(f'  - {k}: properties `{v[0]}`; content `{v[1]}`')

# ------------------------------------------------------------------ 6. PR B: conflicts
sec('6. PR B: deliberate edit/edit conflict')
BR_BT = f'refs/heads/spike/w39-{TS}-b-target'
BR_BS = f'refs/heads/spike/w39-{TS}-b-source'
mk_branch(BR_BT, main_sha)
mk_branch(BR_BS, main_sha)
t_lines = [(f'{l} [w39 target]' if i == 3 else l) for i, l in enumerate(base_lines, 1)]
s_lines = [(f'{l} [w39 source]' if i == 3 else l) for i, l in enumerate(base_lines, 1)]
push(BR_BT, main_sha, 'spike w39: target side of the conflict', [edit('/src/app.ts', '\n'.join(t_lines) + '\n'), add('/spike/w39/both.txt', 'target\n')])
push(BR_BS, main_sha, 'spike w39: source side of the conflict', [edit('/src/app.ts', '\n'.join(s_lines) + '\n'), add('/spike/w39/both.txt', 'source\n')])
s, h, prb = post(f'{R}/pullrequests?api-version=7.1', {'sourceRefName': BR_BS, 'targetRefName': BR_BT, 'title': f'spike w39 PR B conflict ({TS})', 'description': 'Deliberate conflict. Abandoned by the spike.'})
B = prb.get('pullRequestId') if s < 300 else None
p(f'POST PR B → {s}: id {B}, mergeStatus {prb.get("mergeStatus") if s < 300 else err(prb)}')
if B:
    LEFT['prs'].append(B)
    PRB = f'{R}/pullRequests/{B}'
    for _ in range(10):
        prb = pr_get(B)
        if prb.get('mergeStatus') not in (None, 'queued', 'notSet'):
            break
        time.sleep(2)
    p(f'- PR B mergeStatus {prb.get("mergeStatus")}, mergeFailureType {prb.get("mergeFailureType")}, mergeFailureMessage `{short(prb.get("mergeFailureMessage"), 200)}`')
    s, h, cf = get(f'{PRB}/conflicts?api-version=7.1')
    vals = cf.get('value', [])
    p(f'GET conflicts → {s}: {len(vals)}; {[(c.get("conflictId"), c.get("conflictType"), c.get("conflictPath"), c.get("resolutionStatus")) for c in vals]}')
    if vals:
        p(f'- first conflict: `{short(vals[0], 900)}`')
        s, h, one = get(f'{PRB}/conflicts/{vals[0]["conflictId"]}?api-version=7.1')
        p(f'GET conflicts/{{id}} → {s}: keys `{sorted(one.keys()) if s < 300 else err(one)}`')
        s, h, ev = get(f'{ORG_URL}/{P}/_apis/policy/evaluations?artifactId={urllib.parse.quote("vstfs:///CodeReview/CodeReviewId/" + PROJECT_ID + "/" + str(B), safe="")}&api-version=7.1-preview.1')
        p(f'- policy evaluations on PR B (no policies on its target) → {s}: {len(ev.get("value", [])) if s == 200 else err(ev)}')
        # a resolution attempt: take source for the edit/edit conflict
        ee = next((c for c in vals if c['conflictType'] == 'editEdit'), vals[0])
        s, h, r = call('PATCH', f'{PRB}/conflicts/{ee["conflictId"]}?api-version=7.1', {'resolution': {'mergeType': 'takeSourceContent'}, 'resolutionStatus': 'resolved'})
        p(f'PATCH conflicts/{{id}} takeSourceContent → {s}: {short({k: r.get(k) for k in ("conflictId", "resolutionStatus", "resolutionError", "resolvedBy", "resolution")} if s < 300 else err(r), 500)}')
        time.sleep(3)
        s, h, cf2 = get(f'{PRB}/conflicts?api-version=7.1')
        p(f'- conflicts after resolve: {[(c.get("conflictId"), c.get("conflictType"), c.get("resolutionStatus")) for c in cf2.get("value", [])]}')
        s, h, r = jsonpatch_pr(f'{PRB}?api-version=7.1', {'mergeOptions': {'detectRenameFalsePositives': False}})
        p(f'PATCH mergeOptions on PR B (restart merge) → {s}: mergeStatus {r.get("mergeStatus") if s < 300 else err(r)}')
        time.sleep(4)
        prb = pr_get(B)
        s, h, its = get(f'{PRB}/iterations?api-version=7.1')
        p(f'- PR B after: mergeStatus {prb.get("mergeStatus")}, iterations {[(i["id"], i.get("reason")) for i in its.get("value", [])]}')
    # auto-complete on a conflicting PR
    s, h, r = jsonpatch_pr(f'{PRB}?api-version=7.1', {'autoCompleteSetBy': {'id': ME['id']}, 'completionOptions': {'mergeStrategy': 'noFastForward', 'deleteSourceBranch': True}})
    p(f'PATCH set auto-complete on the conflicting PR → {s}: status {r.get("status") if s < 300 else err(r)}, autoComplete set {bool(r.get("autoCompleteSetBy")) if s < 300 else "-"}')
    s, h, r = jsonpatch_pr(f'{PRB}?api-version=7.1', {'status': 'abandoned'})
    p(f'PATCH status=abandoned → {s}: {r.get("status") if s < 300 else err(r)}, autoComplete still set {bool(r.get("autoCompleteSetBy")) if s < 300 else "-"}')
    if s < 300:
        LEFT['prs'].remove(B)
del_branch(BR_BS)
del_branch(BR_BT)

# ------------------------------------------------------------------ 7. cherry-pick and revert
sec('7. cherryPicks and reverts (async ref operations)')


def async_op(kind, body):
    s, h, r = post(f'{R}/{kind}?api-version=7.1', body)
    p(f'POST {kind} → {s}: {short({k: r.get(k) for k in ("cherryPickId", "revertId", "status", "detailedStatus", "parameters")} if s < 300 else err(r), 500)}')
    if s >= 300:
        return None
    oid = r.get('cherryPickId') or r.get('revertId')
    for _ in range(15):
        s, h, r = get(f'{R}/{kind}/{oid}?api-version=7.1')
        if r.get('status') in ('completed', 'failed', 'abandoned'):
            break
        time.sleep(2)
    p(f'- GET {kind}/{oid} → {s}: status {r.get("status")}, detailedStatus `{short(r.get("detailedStatus"), 300)}`, keys `{sorted(r.keys())}`')
    return r


cp_branch = f'refs/heads/spike/w39-{TS}-cherrypick'
r = async_op('cherryPicks', {'generatedRefName': cp_branch, 'ontoRefName': 'refs/heads/main', 'repository': {'name': SCRATCH},
                             'source': {'commitList': [{'commitId': sha_a2}]}})
if r and r.get('status') == 'completed':
    LEFT['branches'].append(cp_branch)
    s, h, refs2 = get(f'{R}/refs?filter=heads/spike/w39-{TS}-cherrypick&api-version=7.1')
    p(f'- generated branch exists: {[x["name"] for x in refs2.get("value", [])]}')
# cherry-pick by pull request id
cp2_branch = f'refs/heads/spike/w39-{TS}-cherrypick-pr'
r = async_op('cherryPicks', {'generatedRefName': cp2_branch, 'ontoRefName': POLICY_BRANCH, 'repository': {'name': SCRATCH},
                             'source': {'pullRequestId': A}})
if r and r.get('status') == 'completed':
    LEFT['branches'].append(cp2_branch)
# revert of a completed PR (8319) onto main
rv_branch = f'refs/heads/spike/w39-{TS}-revert'
r = async_op('reverts', {'generatedRefName': rv_branch, 'ontoRefName': 'refs/heads/main', 'repository': {'name': SCRATCH},
                         'source': {'pullRequestId': 8319}})
if r and r.get('status') == 'completed':
    LEFT['branches'].append(rv_branch)
    s, h, d = get(f'{R}/diffs/commits?baseVersion=main&targetVersion={urllib.parse.quote(rv_branch[len("refs/heads/"):])}&diffCommonCommit=true&api-version=7.1')
    p(f'- revert branch vs main: {len(d.get("changes", []))} changes, aheadCount {d.get("aheadCount")}')
for b in (cp_branch, cp2_branch, rv_branch):
    del_branch(b)

# ------------------------------------------------------------------ 8. what is left
sec('8. Left behind')
pra = pr_get(A)
p(f'- PR A {A}: status {pra.get("status")}, isDraft {pra.get("isDraft")}, target {pra.get("targetRefName")}, autoComplete {bool(pra.get("autoCompleteSetBy"))}, mergeStatus {pra.get("mergeStatus")}')
p(f'- branches kept: {LEFT["branches"] + [POLICY_BRANCH]}')
p(f'- policies created this run: {LEFT["policies"]}')
p(f'- PRs still active from this run: {LEFT["prs"]}')
OUT.append(dump_costs())
write_result('w39_pr_writes/report.md', '\n'.join(OUT))
