"""s64 (read-only): the pull request REST surface Boardhop does not use yet.

Questions:

  A  the full `GitPullRequest` shape on scratch PR 8334 (repo route, repo-free
     route, includeCommits / includeWorkItemRefs): autoCompleteSetBy,
     completionOptions, mergeOptions, mergeStatus, mergeFailureType, labels,
     isDraft, supportsIterations, hasMultipleMergeBases; key presence over a
     client sample (counts only).
  B  threads: system thread `properties` catalog (names, $type, and the values
     of the enum-like keys only), CodeReviewThreadType distribution, comment
     types, identities map, left-side and file-level contexts, `usersLiked`.
  C  likes GET shape on a scratch comment.
  D  conflicts GET on 8334 and on client PRs whose mergeStatus is conflicts
     (counts and conflictType only).
  E  policy configurations (git-scoped route and project route): type ids,
     names, settings keys; merge-strategy and required-reviewer shapes.
  F  iteration changes paging ($top=1 → nextSkip/nextTop), $compareTo,
     iterations?includeCommits, iteration commits, PR commits with
     continuation, changeTrackingId stability across iterations.
  G  pullrequestquery by commit id; list criteria (queryTimeRangeType,
     sourceRefName, org-wide route with status=all).
  H  labels, properties, workitems, reviewers, statuses, iteration statuses,
     attachments GET shapes on 8334.
  I  any readable "viewed file" state: Settings entries (me), Contribution
     HierarchyQuery data providers (unofficial, shape only).
  J  rate-limit costs.

GETs (and query POSTs) only; nothing is written. Client PR titles, descriptions,
comment text and names never reach the result file: only counts and shapes.
"""
import json, os, re, sys, urllib.parse
from collections import Counter

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402

SCRATCH = 'DevOps Mobile App'
P = urllib.parse.quote(SCRATCH)
PR_ID = 8334
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
OUT = ['# Spike s64 — pull request capabilities (read-only)', '']
ME = {}


def q(s):
    return urllib.parse.quote(str(s), safe='')


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


def keys(d, depth=0):
    """Key tree without values (safe for client objects)."""
    if not isinstance(d, dict):
        return type(d).__name__
    out = {}
    for k, v in d.items():
        if isinstance(v, dict) and depth < 2:
            out[k] = keys(v, depth + 1)
        elif isinstance(v, list):
            out[k] = f'list[{len(v)}]' + (f' of {keys(v[0], depth + 1)}' if v and isinstance(v[0], dict) and depth < 1 else '')
        else:
            out[k] = type(v).__name__
    return out


SAFE_ENUM_KEYS = {'CodeReviewThreadType', 'CodeReviewVoteResult', 'CodeReviewRefNewCommitsCount',
                  'CodeReviewRefUpdatedCommitsCount', 'Microsoft.TeamFoundation.Discussion.SupportsMarkdown',
                  'CodeReviewStatusUpdatedStatus', 'CodeReviewIsDraftUpdate', 'CodeReviewTargetRefUpdate',
                  'CodeReviewAutoCompleteUpdate', 'CodeReviewPolicyStatus', 'CodeReviewReviewersUpdatedNumAdded',
                  'CodeReviewReviewersUpdatedNumRemoved', 'CodeReviewReviewersUpdatedNumChanged',
                  'CodeReviewReviewersUpdatedNumRequired', 'CodeReviewReviewersUpdatedNumOptional',
                  'CodeReviewVotedByIdentity', 'CodeReviewVotedByDisplayName',
                  'CodeReviewRefNameNew', 'CodeReviewRefNameOld', 'CodeReviewIsDraftUpdatedTo'}


def prop_catalog(threads, safe_values=True):
    """properties: name -> Counter of $type; values only for enum-like keys."""
    names = Counter()
    types = {}
    values = {}
    for t in threads:
        for k, v in (t.get('properties') or {}).items():
            names[k] += 1
            ty = v.get('$type') if isinstance(v, dict) else type(v).__name__
            types.setdefault(k, Counter())[ty] += 1
            val = v.get('$value') if isinstance(v, dict) else v
            if k in SAFE_ENUM_KEYS or (isinstance(val, (int, bool)) and 'Identity' not in k and 'Name' not in k):
                values.setdefault(k, Counter())[str(val)[:40]] += 1
    return names, types, values


# ------------------------------------------------------------------ 0. who / where
s, _, r = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
ME['id'] = (r.get('authenticatedUser') or {}).get('id', '') if isinstance(r, dict) else ''
s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if r['name'] == SCRATCH)
REPO = repo['id']
R = f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}'
PR = f'{R}/pullRequests/{PR_ID}'
PROJECT_ID = repo['project']['id']
p(f'scratch repo `{SCRATCH}` id {REPO}, project id {PROJECT_ID}, PR {PR_ID}')

# ------------------------------------------------------------------ A. PR shape
sec('A. GitPullRequest shape (scratch PR 8334)')
s, h, pr = get(f'{PR}?api-version=7.1')
p(f'GET repo route → {s}; keys: `{sorted(pr.keys())}`')
for k in ('status', 'isDraft', 'mergeStatus', 'mergeFailureType', 'mergeFailureMessage', 'autoCompleteSetBy',
          'completionOptions', 'mergeOptions', 'labels', 'supportsIterations', 'hasMultipleMergeBases',
          'completionQueueTime', 'closedBy', 'artifactId', 'codeReviewId', 'forkSource', 'workItemRefs', 'commits'):
    p(f'- `{k}`: `{short(pr.get(k, "<absent>"), 300)}`')
s, h, pr2 = get(f'{ORG_URL}/_apis/git/pullrequests/{PR_ID}?api-version=7.1')
p(f'GET repo-free org route → {s}; same keys: {sorted(pr2.keys()) == sorted(pr.keys()) if s == 200 else "n/a"}')
s, h, pr3 = get(f'{PR}?includeCommits=true&includeWorkItemRefs=true&api-version=7.1')
p(f'GET includeCommits&includeWorkItemRefs → {s}; extra keys: `{sorted(set(pr3.keys()) - set(pr.keys()))}`')
p(f'- commits: {len(pr3.get("commits") or [])} entries, first keys `{sorted((pr3.get("commits") or [{}])[0].keys())}`')
p(f'- workItemRefs: `{short(pr3.get("workItemRefs"), 400)}`')
p(f'- reviewers[0] keys: `{sorted((pr.get("reviewers") or [{}])[0].keys())}`')
p(f'- `_links` keys: `{sorted((pr.get("_links") or {}).keys())}`')

# Client sample: key presence and value distributions only.
sec('A2. Client sample: key presence and distributions (counts only)')
s, h, allprs = get(f'{ORG_URL}/_apis/git/pullrequests?searchCriteria.status=all&$top=200&api-version=7.1')
sample = allprs.get('value', []) if s == 200 else []
p(f'org-wide `pullrequests?status=all&$top=200` → {s}, {len(sample)} PRs, count header {h.get("X-MS-ContinuationToken", "none")}')
kc = Counter()
for x in sample:
    kc.update(x.keys())
p('key presence over the sample:')
for k, n in sorted(kc.items()):
    p(f'- `{k}`: {n}')
for k in ('status', 'mergeStatus', 'isDraft', 'supportsIterations', 'hasMultipleMergeBases', 'mergeFailureType'):
    p(f'- `{k}` values: {dict(Counter(str(x.get(k, "<absent>")) for x in sample))}')
p(f'- autoCompleteSetBy present: {sum(1 for x in sample if x.get("autoCompleteSetBy"))}')
p(f'- completionOptions present: {sum(1 for x in sample if x.get("completionOptions"))}; keys seen: '
  f'{sorted({k for x in sample for k in (x.get("completionOptions") or {})})}')
p(f'- completionOptions.mergeStrategy values: {dict(Counter(str((x.get("completionOptions") or {}).get("mergeStrategy")) for x in sample if x.get("completionOptions")))}')
p(f'- mergeOptions present: {sum(1 for x in sample if x.get("mergeOptions"))}; keys seen: '
  f'{sorted({k for x in sample for k in (x.get("mergeOptions") or {})})}')
p(f'- labels present: {sum(1 for x in sample if x.get("labels"))}; label keys: '
  f'{sorted({k for x in sample for l in (x.get("labels") or []) for k in l})}')
p(f'- reviewers with isRequired: {sum(1 for x in sample for r in x.get("reviewers", []) if r.get("isRequired"))}; '
  f'isContainer: {sum(1 for x in sample for r in x.get("reviewers", []) if r.get("isContainer"))}; '
  f'votedFor present: {sum(1 for x in sample for r in x.get("reviewers", []) if r.get("votedFor"))}; '
  f'hasDeclined: {sum(1 for x in sample for r in x.get("reviewers", []) if r.get("hasDeclined"))}; '
  f'isFlagged: {sum(1 for x in sample for r in x.get("reviewers", []) if r.get("isFlagged"))}')
active_ac = [x for x in sample if x.get('status') == 'active' and x.get('autoCompleteSetBy')]
if active_ac:
    p(f'- an active PR with auto-complete: completionOptions keys `{sorted(active_ac[0]["completionOptions"].keys())}`, '
      f'values `{short({k: v for k, v in active_ac[0]["completionOptions"].items() if k != "mergeCommitMessage"}, 400)}`')
conflict_prs = [x for x in sample if x.get('mergeStatus') == 'conflicts']
p(f'- PRs with mergeStatus=conflicts: {len(conflict_prs)}')

# ------------------------------------------------------------------ B. threads
sec('B. Threads and system thread properties')
s, h, th = get(f'{PR}/threads?api-version=7.1')
threads = th.get('value', [])
p(f'scratch PR threads → {s}, {len(threads)} threads; thread keys `{sorted({k for t in threads for k in t})}`')
ttype = Counter((t.get('properties') or {}).get('CodeReviewThreadType', {}).get('$value', '<none>') for t in threads)
p(f'- CodeReviewThreadType: {dict(ttype)}')
p(f'- comment types: {dict(Counter(c.get("commentType") for t in threads for c in t.get("comments", [])))}')
p(f'- comment keys: `{sorted({k for t in threads for c in t.get("comments", []) for k in c})}`')
p(f'- thread status values: {dict(Counter(t.get("status") for t in threads))}')
p(f'- with threadContext: {sum(1 for t in threads if t.get("threadContext"))}; with pullRequestThreadContext: '
  f'{sum(1 for t in threads if t.get("pullRequestThreadContext"))}; isDeleted: {sum(1 for t in threads if t.get("isDeleted"))}')
p(f'- identities map present: {sum(1 for t in threads if t.get("identities"))}')
names, types, values = prop_catalog(threads)
p('- properties catalog (scratch):')
for k, n in sorted(names.items()):
    p(f'  - `{k}` ×{n} {dict(types[k])} {dict(values.get(k, {})) if k in values else ""}')
sysx = [t for t in threads if (t.get('properties') or {}).get('CodeReviewThreadType')]
for kind in sorted({t['properties']['CodeReviewThreadType']['$value'] for t in sysx}):
    t = next(t for t in sysx if t['properties']['CodeReviewThreadType']['$value'] == kind)
    c0 = (t.get('comments') or [{}])[0]
    p(f'- example {kind}: comment content `{short(c0.get("content"), 200)}`, commentType {c0.get("commentType")}, '
      f'identities keys `{sorted((t.get("identities") or {}).keys())}`, status {t.get("status")}')
# threads at an iteration pair, and a left-side / file-level anchored thread if any
s, h, th2 = get(f'{PR}/threads?$iteration=1&$baseIteration=0&api-version=7.1')
p(f'threads?$iteration=1&$baseIteration=0 → {s}, {len(th2.get("value", []))} threads; pullRequestThreadContext keys '
  f'`{sorted({k for t in th2.get("value", []) for k in (t.get("pullRequestThreadContext") or {})})}`')
ctx_shapes = Counter()
for t in threads:
    tc = t.get('threadContext') or {}
    if tc:
        ctx_shapes[('left' if tc.get('leftFileStart') else '') + ('right' if tc.get('rightFileStart') else '') or 'file-only'] += 1
p(f'- threadContext side shapes (scratch): {dict(ctx_shapes)}')
anch = next((t for t in threads if t.get('threadContext')), None)
if anch:
    p(f'- an anchored thread: threadContext `{short(anch["threadContext"], 400)}`; pullRequestThreadContext `{short(anch.get("pullRequestThreadContext"), 400)}`')
likes_n = sum(len(c.get('usersLiked') or []) for t in threads for c in t.get('comments', []))
p(f'- usersLiked entries over scratch comments: {likes_n}')

# Client sample of threads: property catalog + context shapes, counts only.
sec('B2. Client thread sample (counts only)')
client_threads = []
for x in [x for x in sample if x['repository']['project']['name'] != SCRATCH][:12]:
    rp = x['repository']
    s, h, t = get(f'{ORG_URL}/{rp["project"]["id"]}/_apis/git/repositories/{rp["id"]}/pullRequests/{x["pullRequestId"]}/threads?api-version=7.1')
    if s == 200:
        client_threads.extend(t.get('value', []))
p(f'{len(client_threads)} threads over 12 client PRs')
p(f'- CodeReviewThreadType: {dict(Counter((t.get("properties") or {}).get("CodeReviewThreadType", {}).get("$value", "<none>") for t in client_threads))}')
p(f'- comment types: {dict(Counter(c.get("commentType") for t in client_threads for c in t.get("comments", [])))}')
p(f'- status values: {dict(Counter(t.get("status") for t in client_threads))}')
ctx_shapes = Counter()
multi = 0
for t in client_threads:
    tc = t.get('threadContext') or {}
    if tc:
        ctx_shapes[('left' if tc.get('leftFileStart') else '') + ('right' if tc.get('rightFileStart') else '') or 'file-only'] += 1
        rs, re_ = tc.get('rightFileStart') or {}, tc.get('rightFileEnd') or {}
        if rs and re_ and rs.get('line') != re_.get('line'):
            multi += 1
p(f'- threadContext side shapes: {dict(ctx_shapes)}; multi-line ranges: {multi}')
p(f'- usersLiked entries: {sum(len(c.get("usersLiked") or []) for t in client_threads for c in t.get("comments", []))}; '
  f'deleted comments: {sum(1 for t in client_threads for c in t.get("comments", []) if c.get("isDeleted"))}; '
  f'edited comments (lastContentUpdatedDate != publishedDate): '
  f'{sum(1 for t in client_threads for c in t.get("comments", []) if c.get("lastContentUpdatedDate") and c.get("lastContentUpdatedDate") != c.get("publishedDate"))}')
names, types, values = prop_catalog(client_threads)
p('- properties catalog (client, names/types/enum values only):')
for k, n in sorted(names.items()):
    p(f'  - `{k}` ×{n} {dict(types[k])} {dict(values.get(k, {})) if k in values else ""}')
# The content template of each system kind (system text is service-generated; identities are placeholders)
seen = set()
for t in client_threads:
    kind = (t.get('properties') or {}).get('CodeReviewThreadType', {}).get('$value')
    if kind and kind not in seen:
        seen.add(kind)
        c0 = (t.get('comments') or [{}])[0]
        content = c0.get('content') or ''
        # keep only the service's template if it uses ${n} placeholders; otherwise its shape
        p(f'- {kind}: identities keys `{sorted((t.get("identities") or {}).keys())}`; content uses placeholders: '
          f'{bool(re.search(r"\$\{\d+\}", content))}; content length {len(content)}; '
          f'template `{short(re.sub(r"[0-9a-f]{40}", "<sha>", content), 160) if re.search(r"\$\{\d+\}", content) else "<free text, withheld>"}`')

# ------------------------------------------------------------------ C. likes
sec('C. Likes GET')
c_thread = next((t for t in threads if (t.get('comments') or [{}])[0].get('commentType') == 'text'), None)
if c_thread:
    cid = c_thread['comments'][0]['id']
    s, h, lk = get(f'{PR}/threads/{c_thread["id"]}/comments/{cid}/likes?api-version=7.1')
    p(f'GET threads/{c_thread["id"]}/comments/{cid}/likes → {s}: `{short(lk, 400)}`')

# ------------------------------------------------------------------ D. conflicts
sec('D. Conflicts')
s, h, cf = get(f'{PR}/conflicts?api-version=7.1')
p(f'GET conflicts on 8334 (mergeStatus {pr.get("mergeStatus")}) → {s}: `{short(cf, 300)}`')
for x in conflict_prs[:3]:
    rp = x['repository']
    s, h, cf = get(f'{ORG_URL}/{rp["project"]["id"]}/_apis/git/repositories/{rp["id"]}/pullRequests/{x["pullRequestId"]}/conflicts?api-version=7.1')
    vals = cf.get('value', []) if isinstance(cf, dict) else []
    p(f'client PR (status {x.get("status")}) conflicts → {s}: {len(vals)} entries; keys `{sorted({k for c in vals for k in c})}`; '
      f'conflictType {dict(Counter(c.get("conflictType") for c in vals))}; resolutionStatus {dict(Counter(c.get("resolutionStatus") for c in vals))}')
    if vals:
        c0 = dict(vals[0])
        c0['conflictPath'] = '<path withheld>'
        for k in ('sourceBlob', 'targetBlob', 'baseBlob', 'mergeBaseCommit', 'mergeSourceCommit', 'mergeTargetCommit', 'mergeOrigin'):
            if k in c0:
                c0[k] = keys(c0[k])
        p(f'  first entry (paths withheld): `{short(c0, 700)}`')
    s, h, cf = get(f'{ORG_URL}/{rp["project"]["id"]}/_apis/git/repositories/{rp["id"]}/pullRequests/{x["pullRequestId"]}/conflicts?excludeResolved=true&$top=5&api-version=7.1')
    p(f'  with excludeResolved=true&$top=5 → {s}, {len(cf.get("value", [])) if isinstance(cf, dict) else "?"}')

# ------------------------------------------------------------------ E. policies
sec('E. Policy configurations')
s, h, pol = get(f'{ORG_URL}/{P}/_apis/git/policy/configurations?repositoryId={REPO}&refName=refs/heads/main&api-version=7.1')
vals = pol.get('value', []) if isinstance(pol, dict) else []
p(f'git-scoped `git/policy/configurations?repositoryId&refName=refs/heads/main` (scratch) → {s}, {len(vals)}: '
  f'{[(v["type"]["displayName"], v["type"]["id"], v.get("isBlocking"), v.get("isEnabled")) for v in vals]}')
if vals:
    p(f'- config keys `{sorted(vals[0].keys())}`; settings example `{short(vals[0].get("settings"), 500)}`')
s, h, pol = get(f'{ORG_URL}/{P}/_apis/policy/configurations?api-version=7.1')
vals = pol.get('value', []) if isinstance(pol, dict) else []
p(f'project route `policy/configurations` (scratch) → {s}, {len(vals)}: {[(v["type"]["displayName"], v.get("isBlocking"), v.get("isEnabled")) for v in vals]}')
# a client project: type ids, names, settings keys only
cp = next((x['repository']['project'] for x in sample if x['repository']['project']['name'] != SCRATCH), None)
if cp:
    s, h, pol = get(f'{ORG_URL}/{cp["id"]}/_apis/policy/configurations?api-version=7.1')
    vals = pol.get('value', []) if isinstance(pol, dict) else []
    p(f'a client project `policy/configurations` → {s}, {len(vals)} configurations')
    bytype = {}
    for v in vals:
        bytype.setdefault((v['type']['displayName'], v['type']['id']), []).append(v)
    for (name, tid), vs in sorted(bytype.items()):
        skeys = sorted({k for v in vs for k in (v.get('settings') or {}) if k != 'scope'})
        scope_keys = sorted({k for v in vs for sc in (v.get('settings') or {}).get('scope', []) for k in sc})
        p(f'- `{name}` `{tid}` ×{len(vs)} blocking {dict(Counter(v.get("isBlocking") for v in vs))}; settings keys `{skeys}`; scope keys `{scope_keys}`')
        if 'allowSquash' in skeys or 'requiredReviewerIds' in skeys or 'minimumApproverCount' in skeys:
            ex = dict(vs[0]['settings'])
            ex.pop('scope', None)
            if 'requiredReviewerIds' in ex:
                ex['requiredReviewerIds'] = f'list[{len(ex["requiredReviewerIds"])}]'
            if 'message' in ex:
                ex['message'] = f'<{len(ex["message"] or "")} chars>'
            p(f'  example settings `{short(ex, 400)}`')
    s, h, pt = get(f'{ORG_URL}/{cp["id"]}/_apis/policy/types?api-version=7.1')
    p(f'- `policy/types` → {s}: {[(t["displayName"], t["id"]) for t in pt.get("value", [])] if s == 200 else short(pt, 200)}')

# ------------------------------------------------------------------ F. iterations
sec('F. Iterations, changes paging, commits')
s, h, its = get(f'{PR}/iterations?includeCommits=true&api-version=7.1')
itv = its.get('value', [])
p(f'iterations?includeCommits=true → {s}, {len(itv)}; keys `{sorted(itv[-1].keys()) if itv else []}`')
p(f'- reasons: {[i.get("reason") for i in itv]}; commits per iteration: {[len(i.get("commits") or []) for i in itv]}; '
  f'hasMoreCommits: {[i.get("hasMoreCommits") for i in itv]}')
p(f'- last iteration (no commits): `{short({k: v for k, v in itv[-1].items() if k not in ("commits", "author", "push", "_links")}, 700) if itv else ""}`')
last = itv[-1]['id'] if itv else 1
s, h, ch = get(f'{PR}/iterations/{last}/changes?$top=1&api-version=7.1')
p(f'iterations/{last}/changes?$top=1 → {s}: keys `{sorted(ch.keys())}`, nextSkip {ch.get("nextSkip")}, nextTop {ch.get("nextTop")}, entries {len(ch.get("changeEntries", []))}')
if ch.get('nextSkip'):
    s, h, ch2 = get(f'{PR}/iterations/{last}/changes?$top={ch["nextTop"]}&$skip={ch["nextSkip"]}&api-version=7.1')
    p(f'- page 2 → {s}: entries {len(ch2.get("changeEntries", []))}, nextSkip {ch2.get("nextSkip")}, nextTop {ch2.get("nextTop")}')
s, h, ch = get(f'{PR}/iterations/{last}/changes?api-version=7.1')
p(f'- full: {len(ch.get("changeEntries", []))} entries; entry keys `{sorted(ch["changeEntries"][0].keys()) if ch.get("changeEntries") else []}`; '
  f'item keys `{sorted(ch["changeEntries"][0]["item"].keys()) if ch.get("changeEntries") else []}`')
p(f'- changeTrackingId/changeId/path per entry: {[(e.get("changeTrackingId"), e.get("changeId"), e["item"].get("path"), e.get("changeType")) for e in ch.get("changeEntries", [])]}')
if last > 1:
    s, h, ch1 = get(f'{PR}/iterations/1/changes?api-version=7.1')
    p(f'- iteration 1 for comparison: {[(e.get("changeTrackingId"), e.get("changeId"), e["item"].get("path")) for e in ch1.get("changeEntries", [])]}')
    s, h, chc = get(f'{PR}/iterations/{last}/changes?$compareTo={last - 1}&api-version=7.1')
    p(f'- iterations/{last}/changes?$compareTo={last - 1} → {s}: {[(e.get("changeTrackingId"), e["item"].get("path"), e.get("changeType")) for e in chc.get("changeEntries", [])]}')
s, h, ic = get(f'{PR}/iterations/{last}/commits?api-version=7.1')
p(f'iterations/{last}/commits → {s}: {len(ic.get("value", []))} commits; keys `{sorted(ic["value"][0].keys()) if ic.get("value") else []}`')
s, h, pc = get(f'{PR}/commits?$top=2&api-version=7.1')
p(f'commits?$top=2 → {s}: {len(pc.get("value", []))} commits, continuation header `{h.get("x-ms-continuationtoken") or h.get("X-MS-ContinuationToken")}`')
s, h, pc = get(f'{PR}/commits?api-version=7.1')
p(f'commits (all) → {s}: {len(pc.get("value", []))}')

# ------------------------------------------------------------------ G. queries
sec('G. pullrequestquery and list criteria')
sha = pr.get('lastMergeSourceCommit', {}).get('commitId')
s, h, pq = post(f'{R}/pullrequestquery?api-version=7.1', {'queries': [{'items': [sha], 'type': 'commit'}, {'items': [sha], 'type': 'lastMergeCommit'}]})
p(f'POST pullrequestquery (commit + lastMergeCommit on the source tip) → {s}: `{short(pq, 900)}`')
for crit in ('searchCriteria.status=completed&searchCriteria.queryTimeRangeType=closed&searchCriteria.minTime=2026-09-01T00:00:00Z',
             f'searchCriteria.sourceRefName={q(pr["sourceRefName"])}&searchCriteria.status=all',
             f'searchCriteria.targetRefName=refs/heads/main&searchCriteria.status=active',
             'searchCriteria.status=abandoned&$top=5'):
    s, h, lst = get(f'{R}/pullrequests?{crit}&api-version=7.1')
    p(f'- repo list `{crit}` → {s}: {len(lst.get("value", [])) if isinstance(lst, dict) else short(lst, 200)}')
s, h, lst = get(f'{ORG_URL}/_apis/git/pullrequests?searchCriteria.status=completed&searchCriteria.queryTimeRangeType=closed&searchCriteria.minTime=2026-09-01T00:00:00Z&$top=50&api-version=7.1')
p(f'- org-wide completed since 2026-09-01 (closed) → {s}: {len(lst.get("value", [])) if isinstance(lst, dict) else short(lst, 200)}')

# ------------------------------------------------------------------ H. sub-resources
sec('H. Sub-resources on 8334')
for tail in ('labels', 'properties', 'workitems', 'reviewers', 'statuses', f'iterations/{last}/statuses', 'attachments'):
    s, h, r = get(f'{PR}/{tail}?api-version=7.1')
    p(f'- GET {tail} → {s}: `{short(r, 500)}`')
s, h, r = get(f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}/pullRequests/{PR_ID}/labels?api-version=7.1-preview.1')
p(f'- GET labels at 7.1-preview.1 → {s}')
s, h, r = get(f'{PR}/threads/{threads[0]["id"]}?api-version=7.1') if threads else (0, {}, {})
p(f'- GET threads/{{id}} → {s}: keys `{sorted(r.keys()) if isinstance(r, dict) else r}`')

# ------------------------------------------------------------------ I. viewed-file state
sec('I. Per-user "viewed file" state (unofficial probes)')
for url in (f'{ORG_URL}/_apis/settings/entries/me?api-version=7.1-preview.1',
            f'{ORG_URL}/_apis/settings/entries/me/?api-version=7.1-preview.1',
            f'{ORG_URL}/{P}/_apis/settings/entries/me?api-version=7.1-preview.1',
            f'{ORG_URL}/_apis/settings/entries/me/Repos?api-version=7.1-preview.1',
            f'{ORG_URL}/_apis/settings/entries/me/PullRequest?api-version=7.1-preview.1',
            f'{ORG_URL}/_apis/settings/entries/me/Code?api-version=7.1-preview.1',
            f'{ORG_URL}/_apis/settings/entries/me/VersionControl?api-version=7.1-preview.1',
            f'{ORG_URL}/{P}/_apis/settings/entries/me/PullRequest/{PR_ID}?api-version=7.1-preview.1'):
    s, h, r = get(url)
    body = short(r, 400)
    p(f'- `{url.replace(ORG_URL, "{org}")}` → {s}: {"keys " + str(sorted(r.keys())) if isinstance(r, dict) and s == 200 else body[:200]}')
    if s == 200 and isinstance(r, dict) and r.get('value'):
        p(f'  value keys: `{sorted(r["value"].keys()) if isinstance(r["value"], dict) else r["value"]}`')
# Contribution data provider used by the web PR page (shape only, unofficial)
s, h, r = post(f'{ORG_URL}/_apis/Contribution/HierarchyQuery/project/{PROJECT_ID}?api-version=7.1-preview.1', {
    'contributionIds': ['ms.vss-code-web.pull-request-detail-data-provider'],
    'dataProviderContext': {'properties': {'pullRequestId': PR_ID, 'repositoryId': REPO,
                                           'sourcePage': {'routeValues': {'project': SCRATCH}}}}})
p(f'HierarchyQuery pull-request-detail-data-provider → {s}: top keys `{sorted(r.keys()) if isinstance(r, dict) else short(r, 200)}`')
if isinstance(r, dict):
    dp = r.get('dataProviders') or {}
    p(f'- dataProviders keys `{sorted(dp.keys())}`; exceptions `{short(r.get("dataProviderExceptions"), 300)}`')
    for k, v in dp.items():
        if isinstance(v, dict):
            p(f'- `{k}` keys `{sorted(v.keys())}`')
            for kk in v:
                if 'view' in kk.lower() or 'review' in kk.lower() or 'file' in kk.lower():
                    p(f'  - `{kk}`: `{short(v[kk], 300)}`')

OUT.append(dump_costs())
write_result('s64_pr_capabilities/report.md', '\n'.join(OUT))
