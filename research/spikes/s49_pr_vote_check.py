"""s49 (read-only): the reviewers' votes on scratch PR 8334 after a mis-tap on the simulator."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402
st, _, body = get(f'{ORG_URL}/_apis/git/pullrequests/8334?api-version=7.1')
print(st, body.get('status'), [(r.get('vote'), r.get('isRequired')) for r in body.get('reviewers', [])])
