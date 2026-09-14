"""s51 (read-only): why does the app's byte fetch of a PR attachment answer 500? Try the header
combinations Dio sends (Accept, Accept-Encoding gzip, api-version) against the w32 PR attachment."""
import os, sys, urllib.request, gzip
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402
st, _, pr = get(f'{ORG_URL}/_apis/git/pullrequests/8334?api-version=7.1')
proj, repo = pr['repository']['project']['id'], pr['repository']['id']
st, _, lst = get(f'{ORG_URL}/{proj}/_apis/git/repositories/{repo}/pullRequests/8334/attachments?api-version=7.1')
rows = lst.get('value', [])
print('attachments', st, [(r['displayName']) for r in rows])
txt = next((r for r in rows if r['displayName'].endswith('.txt')), None)
png = next((r for r in rows if r['displayName'].endswith('.png')), None)
pat = os.environ['ADO_PAT']
import base64
auth = 'Basic ' + base64.b64encode(f':{pat}'.encode()).decode()
def probe(label, url, headers):
    h = {'Authorization': auth, **headers}
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read()
            enc = r.headers.get('Content-Encoding')
            if enc == 'gzip': body = gzip.decompress(body)
            print(f'{label:34s} {r.status} {r.headers.get("Content-Type")} enc={enc} len={len(body)}')
    except urllib.error.HTTPError as e:
        print(f'{label:34s} {e.code} {e.headers.get("Content-Type")} {e.read()[:200]!r}')
for r in (txt, png):
    if not r: continue
    u = r['url']
    print('--', r['displayName'])
    probe('plain', u, {})
    probe('accept */*', u, {'Accept': '*/*'})
    probe('gzip', u, {'Accept-Encoding': 'gzip'})
    probe('accept json', u, {'Accept': 'application/json'})
    probe('accept json+gzip', u, {'Accept': 'application/json', 'Accept-Encoding': 'gzip'})
    probe('api-version query', u + ('&' if '?' in u else '?') + 'api-version=7.1', {})
    probe('octet-stream accept', u, {'Accept': 'application/octet-stream'})
