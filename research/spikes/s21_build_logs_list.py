"""s21: can a running task's log be found without the timeline link? Read-
only: for the newest scratch build, lists `builds/{id}/logs` (id, created,
lines) next to the timeline's task records (start time, linked log id) to
see whether log creation order matches task start order."""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402
from scratch import SCRATCH as PROJECT  # noqa: E402

P = urllib.parse.quote(PROJECT)
s, h, builds = get(f'{ORG_URL}/{P}/_apis/build/builds?$top=1&queryOrder=queueTimeDescending&api-version=7.1')
b = builds['value'][0]
print('build', b['id'], b.get('buildNumber'), b.get('status'), b.get('result'))
s, h, logs = get(f'{ORG_URL}/{P}/_apis/build/builds/{b["id"]}/logs?api-version=7.1')
print('logs:', logs.get('count'))
for l in logs.get('value', []):
    print(f"  log {l.get('id'):3} created {str(l.get('createdOn'))[11:19]} changed {str(l.get('lastChangedOn'))[11:19]} lines={l.get('lineCount')}")
s, h, tl = get(f'{ORG_URL}/{P}/_apis/build/builds/{b["id"]}/timeline?api-version=7.1')
print('timeline records with logs:')
for r in sorted(tl.get('records', []), key=lambda r: (r.get('startTime') or '')):
    if r.get('type') in ('Task', 'Job', 'Stage', 'Checkpoint'):
        print(f"  {r.get('type'):10} start {str(r.get('startTime'))[11:19]} finish {str(r.get('finishTime'))[11:19]} state={r.get('state'):10} log={(r.get('log') or {}).get('id')} {r.get('name')}")
