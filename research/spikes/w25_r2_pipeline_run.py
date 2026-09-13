"""w25: research/14 §7 — one run of the scratch pipeline `boardhop-scratch`
(id 139) so the R2 capture set (w24 `hooks`) receives run-state-changed,
stage-state-changed, approval-pending (the Deploy environment; Kelly grants
or rejects it from the phone, which also fires approval-completed) and
build.complete v2. Spends about three hosted-agent minutes on the puremedia
org — approved by Kelly 2026-09-13 (research/14 D8). Scratch project only."""
import os, sys, time

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P  # noqa: E402

PIPELINE_ID = 139

out = ['# Spike w25 — one scratch pipeline run for the R2 capture set', '']
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == SCRATCH, proj
s, h, pipe = get(f'{ORG_URL}/{P}/_apis/pipelines/{PIPELINE_ID}?api-version=7.1')
assert pipe.get('name') == 'boardhop-scratch', short(pipe, 300)

s, h, run = post(f'{ORG_URL}/{P}/_apis/pipelines/{PIPELINE_ID}/runs?api-version=7.1',
                 {'resources': {'repositories': {'self': {'refName': 'refs/heads/main'}}}})
print('queued run:', s, run.get('id'), run.get('name'))
out += [f'- queued `{pipe["name"]}` run **{run.get("name")}** (build id {run.get("id")}) — HTTP {s}', '']

# Follow it until the Deploy checkpoint is waiting or the run ends (≤ 4 min).
build_id = run.get('id')
last = None
for i in range(48):
    time.sleep(5)
    s, h, b = get(f'{ORG_URL}/{P}/_apis/build/builds/{build_id}?api-version=7.1')
    s, h, tl = get(f'{ORG_URL}/{P}/_apis/build/builds/{build_id}/timeline?api-version=7.1')
    stages = [(r.get('name'), r.get('state'), r.get('result')) for r in (tl.get('records') or []) if r.get('type') == 'Stage']
    cur = (b.get('status'), b.get('result'), tuple(sorted(stages)))
    if cur != last:
        last = cur
        print(f't+{(i + 1) * 5:3d}s build {b.get("status")}/{b.get("result")} stages {stages}')
        out.append(f'- t+{(i + 1) * 5}s: build `{b.get("status")}` / `{b.get("result")}`, stages `{stages}`')
    waiting = any(r.get('type') == 'Checkpoint.Approval' or (r.get('type') == 'Stage' and r.get('state') == 'pending')
                  for r in (tl.get('records') or []))
    if b.get('status') == 'completed' or waiting:
        break

s, h, appr = get(f'{ORG_URL}/{P}/_apis/pipelines/approvals?state=pending&$expand=steps&api-version=7.1')
pend = [(a.get('id'), (a.get('pipeline') or {}).get('name'), ((a.get('pipeline') or {}).get('owner') or {}).get('name'))
        for a in (appr.get('value') or []) if isinstance(appr, dict)]
print('pending approvals:', s, pend)
out += ['', f'Pending approvals now (HTTP {s}): `{pend}`', '',
        'Kelly: approve or reject the Deploy stage from the phone; that fires `approval-completed` and then `build.complete`.', '']
out.append(dump_costs())
write_result('w25_r2_pipeline_run.md', '\n'.join(out))
