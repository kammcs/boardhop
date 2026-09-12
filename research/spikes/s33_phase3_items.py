"""s33 (read-only): read back the scratch items the phase 3 walkthrough
edited, to confirm what the edit form actually wrote — title, state, reason,
priority, story points and the revision.
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)
IDS = [15542, 15543, 15544, 15546]

out = []
s, h, items = get(f'{ORG_URL}/{P}/_apis/wit/workitems'
                  f'?ids={",".join(str(i) for i in IDS)}&$expand=all&api-version=7.1')
out.append(f'HTTP {s}')
for it in (items.get('value') or []):
    f = it.get('fields') or {}
    out.append('')
    out.append(f"#{it['id']} rev {it['rev']} {f.get('System.WorkItemType')} — {f.get('System.Title')}")
    out.append(f"  state: {f.get('System.State')} | reason: {f.get('System.Reason')}"
               f" | priority: {f.get('Microsoft.VSTS.Common.Priority')}"
               f" | story points: {f.get('Microsoft.VSTS.Scheduling.StoryPoints')}")
    out.append(f"  assigned: {(f.get('System.AssignedTo') or {}).get('displayName')}"
               f" | changed: {f.get('System.ChangedDate')}")
    out.append(f"  multilineFieldsFormat: {it.get('multilineFieldsFormat')}")

print('\n'.join(out))
write_result('s33-phase3-items.md', '\n'.join(out) + '\n' + dump_costs('s33'))
