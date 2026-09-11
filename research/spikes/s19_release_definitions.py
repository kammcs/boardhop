"""s19: does puremedia use classic release management at all? Read-only:
counts release definitions and pending approvals per project on the vsrm
host, to decide whether classic release approvals are worth building."""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402

ORG = ORG_URL.rsplit('/', 1)[-1]
VSRM = f'https://vsrm.dev.azure.com/{ORG}'
s, h, projects = get(f'{ORG_URL}/_apis/projects?api-version=7.1')
for p in projects.get('value', []):
    P = urllib.parse.quote(p['name'])
    s, h, defs = get(f'{VSRM}/{P}/_apis/release/definitions?api-version=7.1&$top=5')
    count = defs.get('count') if isinstance(defs, dict) else None
    s2, h2, appr = get(f'{VSRM}/{P}/_apis/release/approvals?statusFilter=pending&api-version=7.1')
    pend = appr.get('count') if isinstance(appr, dict) else None
    print(f"{p['name']}: definitions HTTP {s} count={count}; pending approvals HTTP {s2} count={pend}")
    for d in (defs.get('value') or [])[:3] if isinstance(defs, dict) else []:
        print('   -', d.get('name'), 'modified', d.get('modifiedOn', '')[:10])
