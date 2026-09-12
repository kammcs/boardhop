"""s29: which `System.AssignedTo` value does a create accept?

Phase 1's people picker takes the team member list (`teams/{id}/members`) and
sends `identity.id`, and the emulator answered "The identity value '…' for
field 'Assigned To' is an unknown identity". This checks the three candidate
forms with `validateOnly=true` (a read: nothing is created) in the scratch
project: the member id, "Display Name <unique>", and the bare unique name.
Read-only.
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, post, dump_costs, write_result  # noqa: E402

PROJECT = 'DevOps Mobile App'
VSSPS = f'https://vssps.dev.azure.com/{ORG}'
out = ['# Spike s29 — the value System.AssignedTo accepts on create', '']

s, h, project = get(f'{ORG_URL}/_apis/projects/{urllib.parse.quote(PROJECT)}?api-version=7.1')
pid, team_id = project['id'], project['defaultTeam']['id']
s, h, members = get(f'{ORG_URL}/_apis/projects/{pid}/teams/{team_id}/members?api-version=7.1')
rows = [m['identity'] for m in members.get('value', [])]
me = next((r for r in rows if 'kelly' in (r.get('uniqueName') or '').lower()), rows[0])
out.append(f'member keys: {sorted(me.keys())}')
out.append(f'member id looks like a GUID: {len(me.get("id") or "") == 36}')

descriptor = (me.get('descriptor')
              or (me.get('_links', {}).get('avatar', {}).get('href', '').rsplit('/', 1)[-1]))
s, h, key = get(f'{VSSPS}/_apis/graph/storagekeys/{descriptor}?api-version=7.1-preview.1')
storage = key.get('value') if isinstance(key, dict) else None
out.append(f'storagekeys HTTP {s}; equals the member id: {storage == me.get("id")}')

candidates = {
    'member id': me.get('id'),
    'storage key': storage,
    '"Display Name <unique>"': f'{me.get("displayName")} <{me.get("uniqueName")}>',
    'unique name only': me.get('uniqueName'),
    'display name only': me.get('displayName'),
}
url = (f'{ORG_URL}/{urllib.parse.quote(PROJECT)}/_apis/wit/workitems/$Task'
       '?validateOnly=true&api-version=7.1')
for label, value in candidates.items():
    if not value:
        out.append(f'- {label}: skipped (no value)')
        continue
    ops = [{'op': 'add', 'path': '/fields/System.Title', 'value': '[s29] dry run'},
           {'op': 'add', 'path': '/fields/System.AssignedTo', 'value': value}]
    s, h, body = post(url, ops, headers={'Content-Type': 'application/json-patch+json'})
    ok = s == 200
    echoed = ''
    if ok and isinstance(body, dict):
        field = body.get('fields', {}).get('System.AssignedTo')
        echoed = field.get('uniqueName') if isinstance(field, dict) else str(field)
    message = '' if ok else (body.get('message') if isinstance(body, dict) else str(body))[:160]
    print(label, s, echoed or message)
    out.append(f'- {label}: HTTP {s}{" → " + str(echoed) if ok else " — " + str(message)}')

dump_costs(out)
write_result('s29_assignedto_value.md', '\n'.join(out))
