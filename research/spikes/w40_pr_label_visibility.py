"""w40: writes, scratch project only. Adds the label `boardhop-spike` to scratch
PR 8401 (left in place for acceptance) and reads it back through every PR
route, to settle where `labels` is populated."""
import json, os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scratch import *  # noqa: E402,F403
from lib import ORG_URL, get, post, dump_costs, write_result, short  # noqa: E402

PR_ID = 8401
OUT = ['# Spike w40 — label visibility on PR 8401', '']


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if r['name'] == SCRATCH)
REPO = repo['id']
R = f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}'
PR = f'{R}/pullRequests/{PR_ID}'
s, h, r = post(f'{PR}/labels?api-version=7.1', {'name': 'boardhop-spike'})
p(f'- POST labels → {s}: {short({k: r.get(k) for k in ("id", "name", "active")}, 200)}')
s, h, r = post(f'{PR}/labels?projectId={urllib.parse.quote(SCRATCH)}&api-version=7.1', {'name': 'boardhop-spike-2'})
p(f'- POST labels with projectId → {s}: {short({k: r.get(k) for k in ("id", "name", "active")}, 200)}')
for url in (f'{PR}?api-version=7.1', f'{ORG_URL}/_apis/git/pullrequests/{PR_ID}?api-version=7.1',
            f'{PR}?includeCommits=true&includeWorkItemRefs=true&api-version=7.1'):
    s, h, r = get(url)
    p(f'- GET `{url.replace(ORG_URL, "{org}")}` → {s}: labels={short(r.get("labels"), 160)}')
for url in (f'{R}/pullrequests?searchCriteria.status=active&api-version=7.1',
            f'{ORG_URL}/{P}/_apis/git/pullrequests?searchCriteria.status=active&api-version=7.1',
            f'{ORG_URL}/_apis/git/pullrequests?searchCriteria.status=active&$top=50&api-version=7.1'):
    s, h, r = get(url)
    me = next((x for x in r.get('value', []) if x.get('pullRequestId') == PR_ID), None)
    p(f'- list `{url.replace(ORG_URL, "{org}")}` → {s}: labels on 8401={short([l.get("name") for l in (me or {}).get("labels") or []], 160)}')
s, h, r = get(f'{PR}/labels?api-version=7.1')
p(f'- GET labels → {[(l.get("name"), l.get("active")) for l in r.get("value", [])]}')
s, h, r = get(f'{ORG_URL}/{P}/_apis/wit/tags?api-version=7.1-preview.1')
p(f'- project tags list (`wit/tags`) → {s}: names containing boardhop: {[t.get("name") for t in r.get("value", []) if "boardhop" in (t.get("name") or "")] if s == 200 else short(r, 200)}')
s, h, r = call('DELETE', f'{PR}/labels/boardhop-spike-2?api-version=7.1')
p(f'- DELETE labels/boardhop-spike-2 → {s}')
OUT.append(dump_costs())
write_result('w40_pr_label_visibility/report.md', '\n'.join(OUT))
