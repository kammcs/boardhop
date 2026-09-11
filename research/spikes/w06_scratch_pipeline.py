"""w06: create a scratch YAML pipeline in the "DevOps Mobile App" project so the
app's pipeline writes (queue, cancel, retry, approvals) can be exercised.
Writes only in the scratch project (Kelly's go-ahead 2026-09-11). Idempotent:
skips what already exists. Set DRY=1 to only report access and pools."""
import json, os, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)
API = 'api-version=7.1'
DRY = os.environ.get('DRY') == '1'
PIPELINE_NAME = 'boardhop-scratch'
ENV_NAME = 'boardhop-scratch'
YAML_PATH = '/azure-pipelines.yml'

# 1. Access check on the Build/Pipelines area with this PAT.
s, h, defs = get(f'{ORG_URL}/{P}/_apis/build/definitions?{API}')
print('build/definitions (scratch):', s, defs.get('count') if isinstance(defs, dict) else str(defs)[:120])
if s == 401 or s == 403:
    sys.exit('PAT cannot read the Build API; stop here.')

# 2. Which pools do real pipelines use? (read-only, other projects)
s, h, pools = get(f'{ORG_URL}/_apis/distributedtask/pools?{API}')
print('pools:', s, [(p['id'], p['name'], p.get('isHosted')) for p in pools.get('value', [])] if s < 300 else str(pools)[:160])
s, h, agents = get(f'{ORG_URL}/_apis/distributedtask/pools?{API}')
for pool in (pools.get('value', []) if isinstance(pools, dict) else []):
    if pool.get('isHosted'):
        continue
    s2, h2, ag = get(f"{ORG_URL}/_apis/distributedtask/pools/{pool['id']}/agents?{API}")
    if s2 < 300:
        print('  pool', pool['name'], 'agents:', [(a['name'], a.get('status'), a.get('enabled')) for a in ag.get('value', [])])

# 3. Scratch repo.
s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?{API}')
repo = next((r for r in repos.get('value', []) if r['project']['name'] == PROJECT), None)
print('repo:', repo and (repo['name'], repo['id'], repo.get('defaultBranch')))
if DRY or not repo:
    sys.exit(0)
rid = repo['id']
default = repo.get('defaultBranch', 'refs/heads/main')

# 4. Push the YAML to the default branch if missing.
s, h, item = get(f'{ORG_URL}/{P}/_apis/git/repositories/{rid}/items?path={urllib.parse.quote(YAML_PATH)}&{API}')
yaml_text = f"""# Scratch pipeline for Boardhop's pipeline write tests (queue, cancel,
# retry stage, approvals). Manual queue only.
trigger: none
pr: none

parameters:
  - name: fail
    displayName: Fail the Build stage
    type: boolean
    default: false

pool: {{ name: POOL_PLACEHOLDER }}

stages:
  - stage: Build
    jobs:
      - job: Build
        steps:
          - script: echo "Boardhop scratch build $(Build.BuildNumber)"
            displayName: Hello
          - script: sleep 90
            displayName: Wait 90 s (cancel window)
          - ${{{{ if eq(parameters.fail, true) }}}}:
              - script: echo "##[error]Deliberate failure" && exit 1
                displayName: Fail on purpose
          - script: echo "##[warning]A warning for the log accents"
            displayName: Warn
  - stage: Deploy
    dependsOn: Build
    jobs:
      - deployment: Deploy
        environment: {ENV_NAME}
        strategy:
          runOnce:
            deploy:
              steps:
                - script: echo "Deployed after approval"
                  displayName: Deploy
"""
# Prefer a self-hosted pool with an online agent; fall back to Azure Pipelines.
pool_name = 'Azure Pipelines'
for pool in (pools.get('value', []) if isinstance(pools, dict) else []):
    if pool.get('isHosted'):
        continue
    s2, h2, ag = get(f"{ORG_URL}/_apis/distributedtask/pools/{pool['id']}/agents?{API}")
    if s2 < 300 and any(a.get('status') == 'online' and a.get('enabled') for a in ag.get('value', [])):
        pool_name = pool['name']
        break
if pool_name == 'Azure Pipelines':
    yaml_text = yaml_text.replace('pool: { name: POOL_PLACEHOLDER }', 'pool:\n  vmImage: ubuntu-latest')
else:
    yaml_text = yaml_text.replace('POOL_PLACEHOLDER', pool_name)
print('pool chosen:', pool_name)

if s == 200:
    print('yaml already on', default)
else:
    s, h, ref = get(f'{ORG_URL}/{P}/_apis/git/repositories/{rid}/refs?filter=heads/{default.split("/",2)[-1]}&{API}')
    old = ref['value'][0]['objectId']
    s, h, push = post(f'{ORG_URL}/{P}/_apis/git/repositories/{rid}/pushes?{API}', {
        'refUpdates': [{'name': default, 'oldObjectId': old}],
        'commits': [{'comment': 'Add Boardhop scratch pipeline YAML', 'changes': [
            {'changeType': 'add', 'item': {'path': YAML_PATH}, 'newContent': {'content': yaml_text, 'contentType': 'rawtext'}}]}],
    })
    print('push yaml:', s, push.get('commits', [{}])[0].get('commitId', '')[:8] if s < 300 else str(push)[:200])

# 5. Environment (for the approval check).
s, h, envs = get(f'{ORG_URL}/{P}/_apis/pipelines/environments?{API}')
env = next((e for e in envs.get('value', []) if e['name'] == ENV_NAME), None) if s < 300 else None
print('environments:', s, [e['name'] for e in envs.get('value', [])] if s < 300 else str(envs)[:160])
if env is None and s < 300:
    s, h, env = post(f'{ORG_URL}/{P}/_apis/pipelines/environments?{API}', {'name': ENV_NAME, 'description': 'Boardhop approval tests'})
    print('create environment:', s, env.get('id') if s < 300 else str(env)[:200])
    if s >= 300:
        env = None

# 6. Approval check on the environment, approver = the PAT user.
if env:
    s, h, cd = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview')
    me = cd['authenticatedUser']['id']
    s, h, checks = get(f"{ORG_URL}/{P}/_apis/pipelines/checks/configurations?resourceType=environment&resourceId={env['id']}&api-version=7.1-preview.1")
    print('checks on env:', s, [c['type']['name'] for c in checks.get('value', [])] if s < 300 else str(checks)[:160])
    if s < 300 and not any(c['type']['name'] == 'Approval' for c in checks.get('value', [])):
        body = {
            'type': {'id': '8C6F20A7-A545-4486-9777-F762FAFE0D4D', 'name': 'Approval'},
            'settings': {'approvers': [{'id': me}], 'executionOrder': 'anyOrder', 'minRequiredApprovers': 1,
                         'instructions': 'Boardhop approval test: approve from the app.', 'blockedApprovers': []},
            'resource': {'type': 'environment', 'id': str(env['id']), 'name': ENV_NAME},
            'timeout': 43200,
        }
        s, h, r = post(f'{ORG_URL}/{P}/_apis/pipelines/checks/configurations?api-version=7.1-preview.1', body)
        print('create approval check:', s, r.get('id') if s < 300 else str(r)[:300])

# 7. Pipeline definition.
s, h, pipes = get(f'{ORG_URL}/{P}/_apis/pipelines?{API}')
existing = next((p for p in pipes.get('value', []) if p['name'] == PIPELINE_NAME), None) if s < 300 else None
if existing:
    print('pipeline exists:', existing['id'])
else:
    s, h, r = post(f'{ORG_URL}/{P}/_apis/pipelines?{API}', {
        'name': PIPELINE_NAME, 'folder': '\\',
        'configuration': {'type': 'yaml', 'path': YAML_PATH,
                          'repository': {'id': rid, 'name': repo['name'], 'type': 'azureReposGit'}},
    })
    print('create pipeline:', s, r.get('id') if s < 300 else str(r)[:300])
