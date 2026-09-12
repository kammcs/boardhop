"""s28: does `graph/storagekeys/{descriptor}` give the identity id the work
item patch wants? The people picker's Graph search returns a GraphUser with a
descriptor but no id (spike s25), so the id has to be resolved when the user
picks someone. Read-only, scratch project team only: take a member's known id
and descriptor from `teams/{id}/members`, then check the storage key matches.
"""
import json, os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, post, dump_costs, write_result  # noqa: E402

PROJECT = 'DevOps Mobile App'
VSSPS = f'https://vssps.dev.azure.com/{ORG}'
out = ['# Spike s28 — Graph storage keys as the identity id', '']

s, h, project = get(f'{ORG_URL}/_apis/projects/{urllib.parse.quote(PROJECT)}?api-version=7.1')
pid = project['id']
team_id = project['defaultTeam']['id']
s, h, members = get(f'{ORG_URL}/_apis/projects/{pid}/teams/{team_id}/members?api-version=7.1')
rows = [m['identity'] for m in members.get('value', [])]
print('members:', s, len(rows))
out.append(f'members: HTTP {s}, {len(rows)} rows; keys {sorted(rows[0].keys()) if rows else None}')

for identity in rows[:2]:
    descriptor = identity.get('descriptor') or (identity.get('_links', {}).get('avatar', {}).get('href', '').rsplit('/', 1)[-1])
    s, h, key = get(f'{VSSPS}/_apis/graph/storagekeys/{descriptor}?api-version=7.1-preview.1')
    same = isinstance(key, dict) and key.get('value') == identity.get('id')
    print('storagekey:', s, 'matches member id:', same)
    out.append(f'- storagekeys HTTP {s}: keys {sorted(key.keys()) if isinstance(key, dict) else key}; '
               f'matches the member id: {same}')

# What a scoped subject query answers, and whether it carries an id.
s, h, scope = get(f'{VSSPS}/_apis/graph/descriptors/{pid}?api-version=7.1-preview.1')
out.append(f'project descriptor: HTTP {s}')
s, h, found = post(f'{VSSPS}/_apis/graph/subjectquery?api-version=7.1-preview.1',
                   {'query': 'k', 'subjectKind': ['User'], 'scopeDescriptor': scope.get('value')})
users = found.get('value', []) if isinstance(found, dict) else []
print('subjectquery:', s, len(users))
out.append(f'scoped subjectquery HTTP {s}, {len(users)} rows; keys {sorted(users[0].keys()) if users else None}; '
           f'has an `id` field: {any("id" in u for u in users)}')
if users:
    u = users[0]
    d = u.get('descriptor')
    s, h, key = get(f'{VSSPS}/_apis/graph/storagekeys/{d}?api-version=7.1-preview.1')
    out.append(f'- storage key for the first hit: HTTP {s}, resolved: {isinstance(key, dict) and bool(key.get("value"))}')
    print('resolved search hit:', s)

s, h, templates = get(f'{ORG_URL}/{urllib.parse.quote(PROJECT)}/{urllib.parse.quote(PROJECT + " Team")}/_apis/wit/templates?api-version=7.1')
out.append(f'templates: HTTP {s}, count {templates.get("count") if isinstance(templates, dict) else templates}')

out.append(dump_costs())
write_result('s28_storage_keys.md', '\n'.join(out))
print('done')
