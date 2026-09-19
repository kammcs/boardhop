"""w42: writes, scratch project "DevOps Mobile App" only.

Reproduces customer feedback "draft PRs render no data": creates a plain draft
pull request (no reviewers, no work items) from a fresh branch with one edited
file, and dumps the shape of `GET pullRequests/{id}` for it, the project list
entry and the iterations, so the app can be pointed at it.

Left behind: the draft PR and its source branch `spike/w42-<ts>`. Marker "spike w42".

    python _run_with_mcp_creds.py w42_draft_pr.py
"""
import json, os, sys, time

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from scratch import *  # noqa: E402,F403
from lib import ORG_URL, get, post, dump_costs, write_result, short  # noqa: E402

TS = time.strftime('%Y%m%d-%H%M%S')
ZERO = '0' * 40
OUT = [f'# Spike w42 — draft pull request (scratch, {TS})', '']


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if r['name'] == SCRATCH)
R = f'{ORG_URL}/{P}/_apis/git/repositories/{repo["id"]}'
s, h, refs = get(f'{R}/refs?filter=heads/main&api-version=7.1')
main_sha = next(r['objectId'] for r in refs['value'] if r['name'] == 'refs/heads/main')
BR = f'refs/heads/spike/w42-{TS}'
s, h, mk = post(f'{R}/refs?api-version=7.1', [{'name': BR, 'oldObjectId': ZERO, 'newObjectId': main_sha}])
p(f'- create branch {BR} → {s}')
s, h, r = post(f'{R}/pushes?api-version=7.1', {
    'refUpdates': [{'name': BR, 'oldObjectId': main_sha}],
    'commits': [{'comment': 'spike w42: draft PR', 'changes': [
        {'changeType': 'add', 'item': {'path': f'/spike/w42/{TS}.txt'},
         'newContent': {'content': 'draft\n', 'contentType': 'rawtext'}}]}]})
p(f'- push → {s}')
s, h, pr = post(f'{R}/pullrequests?supportsIterations=true&api-version=7.1', {
    'sourceRefName': BR, 'targetRefName': 'refs/heads/main',
    'title': f'spike w42 draft PR ({TS})', 'description': 'Created by spike w42 as a draft. Safe to abandon.',
    'isDraft': True})
p(f'- POST pullrequests isDraft → {s}: id {pr.get("pullRequestId")}, isDraft {pr.get("isDraft")}')
pid = pr['pullRequestId']
time.sleep(5)
s, h, g = get(f'{R}/pullRequests/{pid}?api-version=7.1')
p(f'- GET by id → {s}; keys {sorted(g.keys())}')
p('  ' + short({k: v for k, v in g.items() if k not in ('_links', 'repository', 'createdBy', 'url', 'artifactId')}, 2500))
s, h, lst = get(f'{ORG_URL}/{P}/_apis/git/pullrequests?searchCriteria.status=active&api-version=7.1')
entry = next((x for x in lst.get('value', []) if x['pullRequestId'] == pid), None)
p(f'- project list entry keys {sorted(entry.keys()) if entry else None}')
s, h, it = get(f'{R}/pullRequests/{pid}/iterations?api-version=7.1')
p(f'- iterations → {s}: {len(it.get("value", []))}')
s, h, th = get(f'{R}/pullRequests/{pid}/threads?api-version=7.1')
p(f'- threads → {s}: {len(th.get("value", []))}')
write_result('w42_draft_pr/report.md', '\n'.join(OUT))
dump_costs()
