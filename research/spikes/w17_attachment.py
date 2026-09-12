"""w17: attachments from the form. Scratch project only. Uploads a tiny
PNG with `uploadType=simple`, creates a Task that carries it as an
`AttachedFile` relation in the same create call, reads it back, and
downloads the bytes with the Authorization header to confirm the route
needs it (research/01 §10.3)."""
import base64, json, os, sys, urllib.parse, urllib.request, urllib.error

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import ORG_URL, get, call, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P  # noqa: E402

# 1x1 transparent PNG
PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
out = ['# Spike w17 — attachment upload and relation (scratch project)', '']

s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == SCRATCH, proj


def raw(method, url, data=None, headers=None):
    hd = {'Authorization': lib._AUTH}
    hd.update(headers or {})
    req = urllib.request.Request(url, data=data, method=method, headers=hd)
    try:
        r = urllib.request.urlopen(req)
        return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


url = f'{ORG_URL}/{P}/_apis/wit/attachments?fileName=w17-pixel.png&uploadType=simple&api-version=7.1'
s, h, body = raw('POST', url, PNG, {'Content-Type': 'application/octet-stream'})
att = json.loads(body) if s in (200, 201) else body.decode('utf-8', 'replace')
print('upload:', s, att if isinstance(att, dict) else att[:200])
out += [f'## upload (`uploadType=simple`, octet-stream, {len(PNG)} bytes) — HTTP {s}', '```json', short(att, 400), '```', '']
if s not in (200, 201):
    write_result('w17_attachment.md', '\n'.join(out + [dump_costs()]))
    sys.exit(1)

ops = [
    {'op': 'add', 'path': '/fields/System.Title', 'value': '[spike] w17 task with an attachment'},
    {'op': 'add', 'path': '/fields/System.Description', 'value': f'<p>Attached in the create call: <img src="{att["url"]}" alt="pixel"></p>'},
    {'op': 'add', 'path': '/fields/System.Tags', 'value': 'spike; w17'},
    {'op': 'add', 'path': '/relations/-', 'value': {'rel': 'AttachedFile', 'url': att['url'], 'attributes': {'comment': 'w17 upload', 'name': 'w17-pixel.png'}}},
]
s, h, created = call('POST', f'{ORG_URL}/{P}/_apis/wit/workitems/$Task?api-version=7.1&$expand=relations', ops,
                     headers={'Content-Type': 'application/json-patch+json'})
print('create with AttachedFile:', s, created.get('id') if isinstance(created, dict) else str(created)[:300])
if s not in (200, 201):
    out += [f'## create with the relation — HTTP {s}', '```json', short(created, 800), '```', '']
    write_result('w17_attachment.md', '\n'.join(out + [dump_costs()]))
    sys.exit(1)
wid = created['id']
rels = created.get('relations') or []
out += [f'## create with the AttachedFile relation — HTTP {s}: #{wid}', '',
        f'relations: ' + json.dumps(rels)[:800], '',
        f'AttachedFileCount: {created["fields"].get("System.AttachedFileCount")}', '']

# download with and without the header
s1, h1, b1 = raw('GET', att['url'] + '?fileName=w17-pixel.png&download=true&api-version=7.1')
req = urllib.request.Request(att['url'] + '?fileName=w17-pixel.png&download=true&api-version=7.1')
try:
    r = urllib.request.urlopen(req)
    s2, ct2, n2 = r.status, r.headers.get('Content-Type'), len(r.read())
except urllib.error.HTTPError as e:
    s2, ct2, n2 = e.code, e.headers.get('Content-Type'), len(e.read())
print('download with auth:', s1, h1.get('Content-Type'), len(b1), 'bytes match', b1 == PNG, '| without auth:', s2, ct2, n2)
out += ['## download', '', f'- with Authorization — HTTP {s1}, {h1.get("Content-Type")}, {len(b1)} bytes, identical: {b1 == PNG}',
        f'- without Authorization — HTTP {s2}, {ct2}, {n2} bytes', '']

out.append(dump_costs())
write_result('w17_attachment.md', '\n'.join(out))
