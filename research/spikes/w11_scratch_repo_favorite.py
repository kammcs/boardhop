"""w11: favorite the scratch project's repository through the Favorites API,
read it back, then remove it. Confirms the write shape the app's star
uses. Writes touch only the PAT user's own favorites and only point at a
repository inside the scratch project "DevOps Mobile App"."""
import json, os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call  # noqa: E402
from scratch import SCRATCH as PROJECT  # noqa: E402

P = urllib.parse.quote(PROJECT)
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == PROJECT, proj
s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repo = next(r for r in repos['value'] if not r.get('isDisabled'))
assert repo['project']['id'] == proj['id']
print('scratch repo:', repo['name'], repo['id'])

FAV = f'{ORG_URL}/_apis/Favorite/Favorites?api-version=7.1-preview.1'
body = {
    'artifactId': repo['id'],
    'artifactName': repo['name'],
    'artifactType': 'Microsoft.TeamFoundation.Git.Repository',
    'artifactScope': {'id': proj['id'], 'type': 'Project', 'name': proj['name']},
}
s, h, created = post(FAV, body)
print('POST favorite:', s, json.dumps(created)[:400])
fid = created.get('id') if isinstance(created, dict) else None

s, h, listed = get(f'{ORG_URL}/_apis/Favorite/Favorites?artifactType=Microsoft.TeamFoundation.Git.Repository&artifactScopeType=Project&artifactScopeId={proj["id"]}&api-version=7.1-preview.1')
print('GET favorites (project scope):', s, listed.get('count'), [(f.get('artifactName'), f.get('id')) for f in listed.get('value', [])])
s, h, listed_all = get(f'{ORG_URL}/_apis/Favorite/Favorites?artifactType=Microsoft.TeamFoundation.Git.Repository&artifactScopeType=Project&api-version=7.1-preview.1')
print('GET favorites (no scope id):', s, listed_all.get('count') if isinstance(listed_all, dict) else str(listed_all)[:200])

if fid:
    # DELETE needs the artifact type and scope as query parameters; without them it is a 405.
    s, h, deleted = call('DELETE', f'{ORG_URL}/_apis/Favorite/Favorites/{fid}?artifactType=Microsoft.TeamFoundation.Git.Repository&artifactScopeType=Project&artifactScopeId={proj["id"]}&api-version=7.1-preview.1')
    print('DELETE favorite:', s, str(deleted)[:120])
    s, h, after = get(f'{ORG_URL}/_apis/Favorite/Favorites?artifactType=Microsoft.TeamFoundation.Git.Repository&artifactScopeType=Project&artifactScopeId={proj["id"]}&api-version=7.1-preview.1')
    print('after delete:', s, after.get('count'))
