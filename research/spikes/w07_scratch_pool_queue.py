"""w07: give the scratch project an agent queue for the org's dev pool and
authorize the scratch pipeline to use it (the first queued run failed with
"pool not authorized", see w06). Writes only in "DevOps Mobile App"."""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)
POOL_NAME = 'dev-sd-vnet-agent-pool'
PIPELINE = 'boardhop-scratch'

s, h, pools = get(f'{ORG_URL}/_apis/distributedtask/pools?poolName={urllib.parse.quote(POOL_NAME)}&api-version=7.1')
pool = pools['value'][0]
print('pool:', pool['id'], pool['name'])

s, h, queues = get(f'{ORG_URL}/{P}/_apis/distributedtask/queues?api-version=7.1')
print('queues in scratch project:', s, [(q['id'], q['name']) for q in queues.get('value', [])] if s < 300 else str(queues)[:200])
queue = next((q for q in queues.get('value', []) if q['pool']['id'] == pool['id']), None) if s < 300 else None
if queue is None:
    s, h, queue = post(f'{ORG_URL}/{P}/_apis/distributedtask/queues?authorizePipelines=true&api-version=7.1',
                       {'name': POOL_NAME, 'pool': {'id': pool['id']}})
    print('create queue:', s, queue.get('id') if s < 300 else str(queue)[:300])
    if s >= 300:
        sys.exit(1)

s, h, pipes = get(f'{ORG_URL}/{P}/_apis/pipelines?api-version=7.1')
pipeline = next(p for p in pipes['value'] if p['name'] == PIPELINE)
s, h, perm = call('PATCH', f"{ORG_URL}/{P}/_apis/pipelines/pipelinePermissions/queue/{queue['id']}?api-version=7.1-preview.1",
                  {'pipelines': [{'id': pipeline['id'], 'authorized': True}]})
print('authorize pipeline for queue:', s, [(p['id'], p['authorized']) for p in perm.get('pipelines', [])] if s < 300 else str(perm)[:300])
