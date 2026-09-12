"""s32 (read-only): does the work item **type list** carry `transitions`?

Phase 3 makes the detail page's state sheet offer only the legal
transitions. The app already caches `wit/workitemtypes` (the list) for the
colors and icons; if that read carries `transitions`, the sheet needs no
extra call. Compares the list read with the single-type read for the scratch
project's Bug and Task.
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)

s, h, listed = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes?api-version=7.1')
out = []


def say(*parts):
    out.append(' '.join(str(p) for p in parts))


say('HTTP', s, 'types:', len(listed.get('value') or []))
for t in (listed.get('value') or []):
    keys = sorted(t.keys())
    say(f"  {t['name']:<16} keys={keys}")
    if 'transitions' in t:
        say('      transitions[""] =', (t['transitions'] or {}).get(''))
        say('      transitions[New] =', [x.get('to') for x in (t['transitions'] or {}).get('New', [])])

for name in ('Bug', 'Task'):
    s, h, one = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/{name}?api-version=7.1')
    tr = one.get('transitions') or {}
    say()
    say(f'single read {name}: HTTP {s} keys={sorted(one.keys())}')
    say('  transitions from New:', [x.get('to') for x in tr.get('New', [])])
    say('  xmlForm bytes:', len(one.get('xmlForm') or ''))

# Are the Reason rules per type readable, and is Reason ever alwaysRequired?
for name in ('Bug', 'Task'):
    s, h, fields = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/{name}'
                       '/fields/System.Reason?$expand=All&api-version=7.1')
    say()
    say(f'{name} System.Reason: HTTP {s} alwaysRequired=', fields.get('alwaysRequired'),
          'default=', fields.get('defaultValue'),
          'allowed=', fields.get('allowedValues'))

say(dump_costs('s32'))
write_result('s32-types-list-transitions.md', chr(10).join(out))
print(chr(10).join(out))
