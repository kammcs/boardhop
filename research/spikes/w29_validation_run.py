"""w29: scratch write, approved by Kelly 2026-09-13 ("a few more pipeline
workflows to validate"). Queues one run of `boardhop-scratch` (id 139) for
the relay R2 validation:

  W29_FAIL=true   -> the Build stage fails on purpose: build.complete failed,
                     a `buildFailed` push to the requester (actor exempt).
  W29_FAIL=false  -> normal run: approval-pending at Deploy (a push to the
                     requester as sole approver), then after approval a
                     succeeded build.complete (`buildFixed` when the previous
                     result on main was a failure).

Prints the run id and name only; the relay log and the phone are the result."""
import os, sys, time

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P  # noqa: E402

PIPELINE_ID = 139
FAIL = os.environ.get('W29_FAIL', 'false').lower() == 'true'

out = [f'# Spike w29 — validation run of boardhop-scratch (fail={FAIL})', '']
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == SCRATCH, proj
s, h, pipe = get(f'{ORG_URL}/{P}/_apis/pipelines/{PIPELINE_ID}?api-version=7.1')
assert pipe.get('name') == 'boardhop-scratch', short(pipe, 300)
body = {'resources': {'repositories': {'self': {'refName': 'refs/heads/main'}}},
        'templateParameters': {'fail': 'true' if FAIL else 'false'}}
s, h, run = post(f'{ORG_URL}/{P}/_apis/pipelines/{PIPELINE_ID}/runs?api-version=7.1', body)
print('queued run:', s, run.get('id'), run.get('name'), 'fail' if FAIL else 'normal', time.strftime('%H:%M:%S'))
out += [f'- queued run **{run.get("name")}** (build id {run.get("id")}), fail={FAIL} — HTTP {s} at {time.strftime("%H:%M:%S")}', '']
out.append(dump_costs())
write_result(f'w29_validation_run_{"fail" if FAIL else "normal"}.md', '\n'.join(out))
