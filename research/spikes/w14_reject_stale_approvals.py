"""w14: the log-tailing probes left several scratch runs waiting at the
Deploy environment approval. Reject every pending approval in the scratch
project except the one for the newest run, so the app's Approvals tab
shows a single realistic item. Scratch project only."""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, call  # noqa: E402
from scratch import SCRATCH as PROJECT  # noqa: E402

P = urllib.parse.quote(PROJECT)
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == PROJECT, proj
s, h, appr = get(f'{ORG_URL}/{P}/_apis/pipelines/approvals?state=pending&$expand=steps&api-version=7.1-preview.1')
items = appr.get('value', []) if isinstance(appr, dict) else []
print('pending approvals:', s, len(items))
def run_id(a):
    owner = (a.get('pipeline') or {}).get('owner') or {}
    return int(owner.get('id') or 0)
items.sort(key=run_id)
for a in items[:-1]:
    s, h, r = call('PATCH', f'{ORG_URL}/{P}/_apis/pipelines/approvals?api-version=7.1-preview.1',
                   [{'approvalId': a['id'], 'status': 'rejected', 'comment': 'w14: stale probe run'}])
    print('  rejected', a['id'], 'run', run_id(a), '->', s)
if items:
    print('kept pending:', items[-1]['id'], 'run', run_id(items[-1]))
