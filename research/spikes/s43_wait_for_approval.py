"""s43: read-only. Follow scratch build 20163 (w25) until its Deploy approval
is pending or the run completes; prints the pending approval ids."""
import os, sys, time

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result  # noqa: E402
from scratch import P  # noqa: E402

BUILD = int(os.environ.get('S43_BUILD', '20163'))
out = [f'# Spike s43 — wait for the approval on build {BUILD}', '']
last = None
for i in range(60):
    s, h, b = get(f'{ORG_URL}/{P}/_apis/build/builds/{BUILD}?api-version=7.1')
    s, h, tl = get(f'{ORG_URL}/{P}/_apis/build/builds/{BUILD}/timeline?api-version=7.1')
    recs = tl.get('records') or [] if isinstance(tl, dict) else []
    stages = sorted((r.get('name'), r.get('state'), r.get('result')) for r in recs if r.get('type') == 'Stage')
    cps = [(r.get('type'), r.get('state')) for r in recs if str(r.get('type', '')).startswith('Checkpoint')]
    cur = (b.get('status'), b.get('result'), tuple(stages), tuple(cps))
    if cur != last:
        last = cur
        line = f't+{i * 5}s build {b.get("status")}/{b.get("result")} stages {stages} checkpoints {cps}'
        print(line)
        out.append('- ' + line)
    if b.get('status') == 'completed' or (os.environ.get('S43_UNTIL') != 'completed' and any(t == 'Checkpoint.Approval' for t, _ in cps)):
        break
    time.sleep(5)
s, h, appr = get(f'{ORG_URL}/{P}/_apis/pipelines/approvals?state=pending&$expand=steps&api-version=7.1')
pend = [(a.get('id'), ((a.get('pipeline') or {}).get('owner') or {}).get('name')) for a in (appr.get('value') or [])]
print('pending approvals:', pend)
out += ['', f'pending approvals: `{pend}`', dump_costs()]
write_result('s43_wait_for_approval.md', '\n'.join(out))
