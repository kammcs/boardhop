"""w08: point the scratch pipeline YAML at the hosted "Azure Pipelines" pool
(the scratch project cannot get a queue for the self-hosted dev pool: 403 on
queue creation, see w07) and authorize the pipeline for that queue. Writes
only in "DevOps Mobile App"."""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)
API = 'api-version=7.1'
YAML_PATH = '/azure-pipelines.yml'
POOL = os.environ.get('POOL', 'hosted')  # hosted | <queue name>

s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?{API}')
repo = next(r for r in repos['value'] if r['project']['name'] == PROJECT)
rid = repo['id']
s, h, text = get(f'{ORG_URL}/{P}/_apis/git/repositories/{rid}/items?path={urllib.parse.quote(YAML_PATH)}&{API}', headers={'Accept': 'text/plain'}, raw=True)
lines = text.split('\n')
start = next(i for i, l in enumerate(lines) if l.startswith('pool:'))
end = start + 1
while end < len(lines) and lines[end].startswith('  '):
    end += 1
new_pool = ['pool:', '  vmImage: ubuntu-latest'] if POOL == 'hosted' else [f'pool: {{ name: {POOL} }}']
new_text = '\n'.join(lines[:start] + new_pool + lines[end:])
if new_text == text:
    print('yaml unchanged')
else:
    s, h, ref = get(f'{ORG_URL}/{P}/_apis/git/repositories/{rid}/refs?filter=heads/main&{API}')
    old = ref['value'][0]['objectId']
    s, h, push = post(f'{ORG_URL}/{P}/_apis/git/repositories/{rid}/pushes?{API}', {
        'refUpdates': [{'name': 'refs/heads/main', 'oldObjectId': old}],
        'commits': [{'comment': f'Scratch pipeline: use the {POOL} pool', 'changes': [
            {'changeType': 'edit', 'item': {'path': YAML_PATH}, 'newContent': {'content': new_text, 'contentType': 'rawtext'}}]}],
    })
    print('push yaml:', s, push.get('commits', [{}])[0].get('commitId', '')[:8] if s < 300 else str(push)[:200])

s, h, queues = get(f'{ORG_URL}/{P}/_apis/distributedtask/queues?{API}')
qname = 'Azure Pipelines' if POOL == 'hosted' else POOL
queue = next(q for q in queues['value'] if q['name'] == qname)
s, h, pipes = get(f'{ORG_URL}/{P}/_apis/pipelines?{API}')
pipeline = next(p for p in pipes['value'] if p['name'] == 'boardhop-scratch')
s, h, perm = get(f"{ORG_URL}/{P}/_apis/pipelines/pipelinePermissions/queue/{queue['id']}?api-version=7.1-preview.1")
print('queue', queue['id'], qname, 'permissions:', s, perm.get('allPipelines'), [(p['id'], p['authorized']) for p in perm.get('pipelines', [])] if s < 300 else str(perm)[:200])
if s < 300 and not (perm.get('allPipelines') or {}).get('authorized') and not any(p['id'] == pipeline['id'] and p['authorized'] for p in perm.get('pipelines', [])):
    s, h, perm = call('PATCH', f"{ORG_URL}/{P}/_apis/pipelines/pipelinePermissions/queue/{queue['id']}?api-version=7.1-preview.1",
                      {'pipelines': [{'id': pipeline['id'], 'authorized': True}]})
    print('authorize:', s, [(p['id'], p['authorized']) for p in perm.get('pipelines', [])] if s < 300 else str(perm)[:300])
