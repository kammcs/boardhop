"""w12: does a task's log become readable while the task is still running
once its output exceeds an agent log page? Scratch project only: edits the
scratch pipeline's azure-pipelines.yml on main so the 90 s wait prints a
~200-byte line every second, queues a run, then polls the timeline and
the logs list for two and a half minutes, printing when the running task
record gets a log id and how many lines the partial log read returns."""
import os, re, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call  # noqa: E402
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
print('yaml tip', tip[:7], 'chars', len(yml))
CHATTY = ('for i in $(seq 1 90); do echo "tick $i $(date -u +%T) '
          '$(head -c 180 /dev/zero | tr \'\\0\' x)"; sleep 1; done')
if 'seq 1 90' in yml:
    print('yaml already chatty')
else:
    new_yml, n = re.subn(r'script: sleep 90\b', 'script: ' + CHATTY, yml)
    assert n == 1, f'expected one sleep 90 step, found {n}'
    s, h, push = post(
        f'{ORG_URL}/{P}/_apis/git/repositories/{RID}/pushes?api-version=7.1',
        {
            'refUpdates': [{'name': 'refs/heads/main', 'oldObjectId': tip}],
            'commits': [{
                'comment': 'w12: make the wait step print a line per second',
                'changes': [{
                    'changeType': 'edit',
                    'item': {'path': '/azure-pipelines.yml'},
                    'newContent': {'content': new_yml, 'contentType': 'rawtext'},
                }],
            }],
        },
    )
    print('push:', s, (push.get('commits') or [{}])[0].get('commitId', '')[:7] if isinstance(push, dict) else str(push)[:200])

s, h, run = post(
    f'{ORG_URL}/{P}/_apis/pipelines/{PIPELINE_ID}/runs?api-version=7.1',
    {'resources': {'repositories': {'self': {'refName': 'refs/heads/main'}}}},
)
build_id = run.get('id')
print('queued run:', s, build_id, run.get('name'))

seen = {}
for i in range(30):
    s, h, tl = get(f'{ORG_URL}/{P}/_apis/build/builds/{build_id}/timeline?api-version=7.1')
    for r in tl.get('records', []):
        if r.get('type') != 'Task':
            continue
        log_id = (r.get('log') or {}).get('id')
        key = (r.get('state'), log_id)
        if seen.get(r['id']) != key:
            seen[r['id']] = key
            print(f"  t+{i*5:3d}s {r.get('state'):10} log={log_id} {r.get('name')}")
            if log_id and r.get('state') == 'inProgress':
                s2, h2, log = get(f'{ORG_URL}/{P}/_apis/build/builds/{build_id}/logs/{log_id}?api-version=7.1')
                lines = log.get('value') if isinstance(log, dict) else None
                print(f"       partial log read: HTTP {s2}, {len(lines) if isinstance(lines, list) else '?'} lines so far")
    s, h, logs = get(f'{ORG_URL}/{P}/_apis/build/builds/{build_id}/logs?api-version=7.1')
    counts = [(l.get('id'), l.get('lineCount')) for l in logs.get('value', [])]
    if counts and seen.get('logs') != counts:
        seen['logs'] = counts
        print(f"  t+{i*5:3d}s logs list: {counts}")
    if tl.get('records') and all(r.get('state') == 'completed' for r in tl['records'] if r.get('type') == 'Task' and 'Wait' in (r.get('name') or '')):
        wait_done = True
    time.sleep(5)
print('done')
