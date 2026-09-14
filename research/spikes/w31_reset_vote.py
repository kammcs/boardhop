"""w31 (scratch write): reset the PAT identity's vote on scratch PR 8334 to 0 after a simulator
mis-tap cast a Reject (2026-09-14). Writes only to "DevOps Mobile App"."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, call  # noqa: E402
st, _, me = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
mid = me['authenticatedUser']['id']
st, _, pr = get(f'{ORG_URL}/_apis/git/pullrequests/8334?api-version=7.1')
assert pr['repository']['project']['name'] == 'DevOps Mobile App', 'not the scratch project'
url = f"{ORG_URL}/{pr['repository']['project']['id']}/_apis/git/repositories/{pr['repository']['id']}/pullrequests/8334/reviewers/{mid}?api-version=7.1"
st, _, body = call('PUT', url, {'vote': 0})
print('reset', st, body.get('vote') if isinstance(body, dict) else body)
