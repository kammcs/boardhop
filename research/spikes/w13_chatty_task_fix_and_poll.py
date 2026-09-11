"""w13: repair the chatty wait step w12 wrote (its quoted backslash broke
the YAML scanner), queue a run, and poll the timeline and log list for
two and a half minutes to see when the running task's log becomes
readable. Scratch project only."""
import os, re, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post  # noqa: E402
from scratch import SCRATCH as PROJECT  # noqa: E402

P = urllib.parse.quote(PROJECT)
PIPELINE_ID = 139

s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == PROJECT, proj
s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if not r.get('isDisabled'))
assert repo['project']['id'] == proj['id']
RID = repo['id']

s, h, item = get(f'{ORG_URL}/{P}/_apis/git/repositories/{RID}/items?path=/azure-pipelines.yml&includeContent=true&$format=json&versionDescriptor.version=main&api-version=7.1')
yml = item['content']
tip = item['commitId']
print('yaml tip', tip[:7])
m = re.search(r'^(\s*)- script: for i in \$\(seq 1 90\).*$', yml, re.M)
if m:
    indent = m.group(1)
    block = (
        f'{indent}- script: |\n'
        f'{indent}    for i in $(seq 1 90); do\n'
        f'{indent}      echo "tick $i $(date -u +%T) $(printf %0180d 0)"\n'
        f'{indent}      sleep 1\n'
        f'{indent}    done'
    )
    new_yml = yml[:m.start()] + block + yml[m.end():]
    s, h, push = post(
        f'{ORG_URL}/{P}/_apis/git/repositories/{RID}/pushes?api-version=7.1',
        {
            'refUpdates': [{'name': 'refs/heads/main', 'oldObjectId': tip}],
            'commits': [{
                'comment': 'w13: chatty wait step as a block scalar',
                'changes': [{
                    'changeType': 'edit',
                    'item': {'path': '/azure-pipelines.yml'},
                    'newContent': {'content': new_yml, 'contentType': 'rawtext'},
                }],
            }],
        },
    )
    print('push:', s, (push.get('commits') or [{}])[0].get('commitId', '')[:7] if isinstance(push, dict) else str(push)[:200])
else:
    print('no one-line chatty step found; leaving the YAML as it is')

s, h, run = post(
    f'{ORG_URL}/{P}/_apis/pipelines/{PIPELINE_ID}/runs?api-version=7.1',
    {'resources': {'repositories': {'self': {'refName': 'refs/heads/main'}}}},
)
build_id = run.get('id') if isinstance(run, dict) else None
print('queued run:', s, build_id, run.get('name') if isinstance(run, dict) else str(run)[:300])
if not build_id:
    sys.exit(0)

seen = {}
for i in range(30):
    s, h, tl = get(f'{ORG_URL}/{P}/_apis/build/builds/{build_id}/timeline?api-version=7.1')
    records = tl.get('records', []) if isinstance(tl, dict) else []
    for r in records:
        if r.get('type') != 'Task':
            continue
        log_id = (r.get('log') or {}).get('id')
        key = (r.get('state'), log_id)
        if seen.get(r['id']) != key:
            seen[r['id']] = key
            print(f"  t+{i*5:3d}s {r.get('state'):10} log={log_id} {r.get('name')}")
        if log_id and r.get('state') == 'inProgress' and i % 2 == 0:
            s2, h2, log = get(f'{ORG_URL}/{P}/_apis/build/builds/{build_id}/logs/{log_id}?api-version=7.1')
            lines = log.get('value') if isinstance(log, dict) else None
            print(f"  t+{i*5:3d}s   partial read of log {log_id}: HTTP {s2}, {len(lines) if isinstance(lines, list) else '?'} lines")
    s, h, logs = get(f'{ORG_URL}/{P}/_apis/build/builds/{build_id}/logs?api-version=7.1')
    counts = [(l.get('id'), l.get('lineCount')) for l in logs.get('value', [])] if isinstance(logs, dict) else []
    if counts and seen.get('logs') != counts:
        seen['logs'] = counts
        print(f"  t+{i*5:3d}s logs list: {counts}")
    time.sleep(5)
print('done')
