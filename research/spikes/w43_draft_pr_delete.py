"""w43: writes, scratch project "DevOps Mobile App" only.

Follow-up to w42: pushes a delete of `/README.md` onto the w42 draft PR's
source branch (main is untouched), then reads the iteration changes back to
record the shape a deleted file comes in (`item.path` null, path only in
`originalPath`), which left the app's PR page blank.

    python _run_with_mcp_creds.py w43_draft_pr_delete.py
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scratch import *  # noqa
from lib import ORG_URL, get, post, write_result
PID = 8451
s, h, pr = get(f'{ORG_URL}/{P}/_apis/git/pullrequests/{PID}?api-version=7.1')
assert pr['repository']['project']['name'] == SCRATCH and pr['isDraft']
R = f'{ORG_URL}/{P}/_apis/git/repositories/{pr["repository"]["id"]}'
br = pr['sourceRefName']
s, h, refs = get(f'{R}/refs?filter={br[len("refs/"):]}&api-version=7.1')
tip = next(r['objectId'] for r in refs['value'] if r['name'] == br)
OUT = [f'# Spike w43 — delete on a draft PR (scratch, PR {PID})', '']
s, h, r = post(f'{R}/pushes?api-version=7.1', {
    'refUpdates': [{'name': br, 'oldObjectId': tip}],
    'commits': [{'comment': 'spike w43: delete README.md on the draft branch',
                 'changes': [{'changeType': 'delete', 'item': {'path': '/README.md'}}]}]})
OUT.append(f'- push delete /README.md → {s}')
import time; time.sleep(5)
s, h, its = get(f'{R}/pullRequests/{PID}/iterations?api-version=7.1')
last = its['value'][-1]['id']
s, h, ch = get(f'{R}/pullRequests/{PID}/iterations/{last}/changes?$top=2000&api-version=7.1')
OUT.append(f'- iteration {last} changes → {s}')
for e in ch.get('changeEntries', []):
    OUT.append('  ' + json.dumps({k: e.get(k) for k in ('changeType', 'originalPath', 'item')}))
write_result('w43_draft_pr_delete/report.md', '\n'.join(OUT))
print('\n'.join(OUT))
