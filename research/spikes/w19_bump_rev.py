"""w19 (scratch project only): bump one work item's revision from outside
the app, so the edit form's HTTP 412 conflict flow can be provoked on the
emulator.

Usage: python _run_with_mcp_creds.py w19_bump_rev.py [id] [suffix]
Default id 15543, default suffix " [w19]".

Writes go only to "DevOps Mobile App" (CLAUDE.md hard rule 1) and only to
the ids listed in SCRATCH_IDS; the patch is guarded with `test /rev` like
every write the app makes.
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, patch, dump_costs, write_result  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)
SCRATCH_IDS = {15503, 15504, 15505, 15506, 15507,
               15539, 15540, 15541, 15542, 15543, 15544, 15545,
               15546, 15547, 15548}

item_id = int(sys.argv[1]) if len(sys.argv) > 1 else 15543
suffix = sys.argv[2] if len(sys.argv) > 2 else ' [w19]'
if item_id not in SCRATCH_IDS:
    sys.exit(f'{item_id} is not one of the scratch items; refusing to write.')

out = []
s, h, item = get(f'{ORG_URL}/{P}/_apis/wit/workitems/{item_id}?api-version=7.1')
if s != 200 or (item.get('fields') or {}).get('System.TeamProject') != PROJECT:
    sys.exit(f'HTTP {s}: #{item_id} is not in the scratch project.')
rev = item['rev']
title = item['fields']['System.Title']
out.append(f'#{item_id} rev {rev}: {title!r}')

ops = [
    {'op': 'test', 'path': '/rev', 'value': rev},
    {'op': 'add', 'path': '/fields/System.Title', 'value': title + suffix},
]
s, h, body = patch(f'{ORG_URL}/{P}/_apis/wit/workitems/{item_id}?api-version=7.1', ops)
out.append(f'PATCH HTTP {s}')
if s == 200:
    out.append(f"now rev {body['rev']}: {body['fields']['System.Title']!r}")
else:
    out.append(str(body)[:400])

print('\n'.join(out))
write_result('w19-bump-rev.md', '\n'.join(out) + '\n' + dump_costs('w19'))
