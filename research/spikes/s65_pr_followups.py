"""s65 (read-only): follow-ups to s64/w39 on scratch PR 8401.

  A  where labels show up: GET pullRequests/{id} (repo and org routes), the
     repo list, the org-wide list, includeLabels-style query params.
  B  git-scoped policy configurations for scratch/policy-target after the
     w39 writes settled (both policies expected).
  C  the `VersionControl/UserOptions` user settings entry (diff preferences?).
  D  iteration 2 (reason retarget) changes, and the thread positions at the
     last iteration for the multi-line and left-side threads.
"""
import json, os, re, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402

SCRATCH = 'DevOps Mobile App'
P = urllib.parse.quote(SCRATCH)
PR_ID = 8401
POLICY_BRANCH = 'refs/heads/scratch/policy-target'
OUT = ['# Spike s65 — PR follow-ups (read-only)', '']


def p(*a):
    line = ' '.join(str(x) if isinstance(x, str) else json.dumps(x, indent=1, default=str) for x in a)
    print(line)
    OUT.append(line)


s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if r['name'] == SCRATCH)
REPO = repo['id']
R = f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}'
PR = f'{R}/pullRequests/{PR_ID}'

OUT.append('\n## A. Labels visibility\n')
s, h, lb = get(f'{PR}/labels?api-version=7.1')
p(f'- GET labels → {s}: {[l.get("name") for l in lb.get("value", [])]}')
for url in (f'{PR}?api-version=7.1', f'{PR}?includeLabels=true&api-version=7.1', f'{ORG_URL}/_apis/git/pullrequests/{PR_ID}?api-version=7.1',
            f'{ORG_URL}/_apis/git/pullrequests/{PR_ID}?includeLabels=true&api-version=7.1'):
    s, h, r = get(url)
    p(f'- `{url.replace(ORG_URL, "{org}")}` → {s}: labels={short(r.get("labels"), 120) if isinstance(r, dict) else "?"}')
for url in (f'{R}/pullrequests?searchCriteria.status=active&api-version=7.1',
            f'{R}/pullrequests?searchCriteria.status=active&searchCriteria.includeLinks=true&api-version=7.1',
            f'{ORG_URL}/{P}/_apis/git/pullrequests?searchCriteria.status=active&api-version=7.1',
            f'{ORG_URL}/_apis/git/pullrequests?searchCriteria.status=active&$top=50&api-version=7.1'):
    s, h, r = get(url)
    me = next((x for x in r.get('value', []) if x.get('pullRequestId') == PR_ID), None) if isinstance(r, dict) else None
    p(f'- list `{url.replace(ORG_URL, "{org}")}` → {s}: 8401 present={bool(me)}, labels={short(me.get("labels"), 120) if me else "-"}; PRs with labels in the page: {sum(1 for x in r.get("value", []) if x.get("labels")) if isinstance(r, dict) else "?"}')

OUT.append('\n## B. Policies on scratch/policy-target\n')
s, h, pol = get(f'{ORG_URL}/{P}/_apis/git/policy/configurations?repositoryId={REPO}&refName={urllib.parse.quote(POLICY_BRANCH)}&api-version=7.1')
p(f'- git-scoped → {s}: {[(v["type"]["displayName"], v["id"], v["isBlocking"], {k: v2 for k, v2 in v["settings"].items() if k != "scope"}) for v in pol.get("value", [])]}')
s, h, pol = get(f'{ORG_URL}/{P}/_apis/git/policy/configurations?repositoryId={REPO}&api-version=7.1')
p(f'- git-scoped, repo only → {s}: {[(v["type"]["displayName"], v["id"], [ (sc.get("refName"), sc.get("matchKind")) for sc in v["settings"].get("scope", [])]) for v in pol.get("value", [])]}')
s, h, pol = get(f'{ORG_URL}/{P}/_apis/policy/configurations?api-version=7.1')
p(f'- project route → {s}: {[(v["type"]["displayName"], v["id"]) for v in pol.get("value", [])]}')
s, h, ev = get(f'{ORG_URL}/{P}/_apis/policy/evaluations?artifactId={urllib.parse.quote("vstfs:///CodeReview/CodeReviewId/" + repo["project"]["id"] + "/" + str(PR_ID), safe="")}&api-version=7.1-preview.1')
p(f'- evaluations on 8401 → {s}: {[(e["configuration"]["type"]["displayName"], e.get("status"), e["configuration"]["id"], short(e.get("context"), 200)) for e in ev.get("value", [])]}')
if ev.get('value'):
    p(f'- evaluation keys `{sorted(ev["value"][0].keys())}`; configuration keys `{sorted(ev["value"][0]["configuration"].keys())}`')

OUT.append('\n## C. VersionControl/UserOptions\n')
s, h, r = get(f'{ORG_URL}/_apis/settings/entries/me/VersionControl/UserOptions?api-version=7.1-preview.1')
p(f'- → {s}: `{short(r, 1200)}`')
s, h, r = get(f'{ORG_URL}/_apis/settings/entries/me?api-version=7.1-preview.1')
v = r.get('value', {}) if isinstance(r, dict) else {}
p(f'- all `me` entries: {[(k, short(val, 200)) for k, val in v.items()]}')

OUT.append('\n## D. Retarget iteration changes and tracked thread positions\n')
s, h, its = get(f'{PR}/iterations?api-version=7.1')
p(f'- iterations: {[(i["id"], i.get("reason"), i.get("oldTargetRefName"), i.get("newTargetRefName"), (i.get("sourceRefCommit") or {}).get("commitId", "")[:8], (i.get("targetRefCommit") or {}).get("commitId", "")[:8]) for i in its.get("value", [])]}')
s, h, ch = get(f'{PR}/iterations/2/changes?api-version=7.1')
p(f'- iteration 2 (retarget) changes → {s}: {[(e.get("changeTrackingId"), e["item"]["path"], e.get("changeType")) for e in ch.get("changeEntries", [])]}')
s, h, ch = get(f'{PR}/iterations/2/changes?$compareTo=1&api-version=7.1')
p(f'- iteration 2 $compareTo=1 → {s}: {[(e.get("changeTrackingId"), e["item"]["path"], e.get("changeType")) for e in ch.get("changeEntries", [])]}')
last = its['value'][-1]['id']
s, h, th = get(f'{PR}/threads?$iteration={last}&$baseIteration=0&api-version=7.1')
for t in th.get('value', []):
    if t.get('threadContext'):
        p(f'- thread {t["id"]} status {t.get("status")}: threadContext `{short(t["threadContext"], 300)}`; prc `{short(t.get("pullRequestThreadContext"), 500)}`')
s, h, th = get(f'{PR}/threads?$iteration={last}&$baseIteration={last - 1}&api-version=7.1')
p(f'- threads at $iteration={last}&$baseIteration={last - 1}: {[(t["id"], short(t.get("threadContext"), 160)) for t in th.get("value", []) if t.get("threadContext")]}')

OUT.append(dump_costs())
write_result('s65_pr_followups/report.md', '\n'.join(OUT))
