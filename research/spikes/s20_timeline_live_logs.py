"""s20: while a scratch run is executing, does a timeline record that is
inProgress already carry a `log` reference? Read-only: polls the newest
active build of the scratch pipeline for up to two minutes and prints the
state and log id of every non-completed task record on each pass."""
import os, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402
from scratch import SCRATCH as PROJECT  # noqa: E402

P = urllib.parse.quote(PROJECT)
s, h, builds = get(f'{ORG_URL}/{P}/_apis/build/builds?statusFilter=inProgress,notStarted&$top=1&queryOrder=queueTimeDescending&api-version=7.1')
value = builds.get('value') or []
if not value:
    print('no active build in the scratch project; queue one from the app first')
    sys.exit(0)
b = value[0]
print('build', b['id'], b.get('buildNumber'), b.get('status'))
seen = {}
for i in range(24):
    s, h, tl = get(f'{ORG_URL}/{P}/_apis/build/builds/{b["id"]}/timeline?api-version=7.1')
    for r in tl.get('records', []):
        if r.get('type') not in ('Task', 'Job'):
            continue
        key = (r.get('name'), r.get('state'), (r.get('log') or {}).get('id'))
        if r.get('state') != 'completed' and seen.get(r.get('id')) != key:
            seen[r['id']] = key
            print(f"  t+{i*5:3d}s {r.get('type'):4} {r.get('state'):10} log={(r.get('log') or {}).get('id')} {r.get('name')}")
    if all(r.get('state') == 'completed' for r in tl.get('records', []) if r.get('type') == 'Task' and r.get('parentId')):
        pass
    time.sleep(5)
print('done')
