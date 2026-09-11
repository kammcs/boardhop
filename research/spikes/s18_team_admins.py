"""s18: who administers the scratch project's default team? Read-only.
Lists the members of the default team with their isTeamAdmin flag and
shows which identity the PAT belongs to, so we know whether the board
configuration and project picture spikes (w05, w10) can run."""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402
from scratch import SCRATCH as PROJECT  # noqa: E402

P = urllib.parse.quote(PROJECT)
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == PROJECT, proj
team = proj.get('defaultTeam') or {}
print('project:', proj['name'], proj['id'])
print('default team:', team.get('name'), team.get('id'))

s, h, me = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview')
user = me.get('authenticatedUser') or {}
print('PAT identity:', user.get('providerDisplayName'), user.get('id'))

s, h, members = get(f'{ORG_URL}/_apis/projects/{proj["id"]}/teams/{team["id"]}/members?api-version=7.1')
print('members:', s, members.get('count'))
for m in members.get('value', []):
    ident = m.get('identity', {})
    flag = 'ADMIN' if m.get('isTeamAdmin') else 'member'
    mark = ' <- PAT user' if ident.get('id') == user.get('id') else ''
    print(f"  {flag:6} {ident.get('displayName')} ({ident.get('uniqueName')}){mark}")

s, h, teams = get(f'{ORG_URL}/_apis/projects/{proj["id"]}/teams?api-version=7.1')
print('all teams:', [t.get('name') for t in teams.get('value', [])])
