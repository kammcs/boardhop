"""Spike 2: does a PAT work against the Profiles and Accounts APIs?

Microsoft's PAT doc (updated 2026-09-04) says these APIs accept only Entra tokens;
the REST reference lists the vso.profile scope, which is PAT-selectable.
"""
from lib import *

out = ['# Spike 2 — PAT against Profiles and Accounts APIs', f'Org: {ORG_URL}', '']

s, h, b = get('https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1', raw=True)
out += ['## GET app.vssps.visualstudio.com/_apis/profile/profiles/me', f'HTTP {s}',
        f'Content-Type: {h.get("Content-Type")}', '```', short(b, 800), '```', '']
pid = None
try:
    pid = json.loads(b).get('id')
    out.append(f'profile id obtained: {bool(pid)}')
except Exception:
    out.append('response was not JSON (sign-in redirect or error page)')

if pid:
    s2, h2, b2 = get(f'https://app.vssps.visualstudio.com/_apis/accounts?memberId={pid}&api-version=7.1', raw=True)
    out += ['', '## GET /_apis/accounts?memberId=…', f'HTTP {s2}', '```', short(b2, 800), '```']

s3, h3, b3 = get(f'{ORG_URL}/_apis/connectionData')
if isinstance(b3, dict):
    view = {'deploymentType': b3.get('deploymentType'), 'instanceId': b3.get('instanceId'),
            'authenticatedUser': {k: b3['authenticatedUser'].get(k) for k in ['id', 'providerDisplayName', 'isActive']}}
else:
    view = b3
out += ['', '## GET {org}/_apis/connectionData (alternative identity source, no vssps host)', f'HTTP {s3}', '```', short(view, 800), '```']
out.append(dump_costs())
write_result('s02_pat_profile_accounts.md', '\n'.join(out))
