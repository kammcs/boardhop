"""w32: writes, scratch project "DevOps Mobile App" only.

What Azure DevOps accepts for **images and files inside comments** — the two
surfaces Boardhop has to support: a work item comment and a pull request thread
comment.

Writes: two small attachments plus one ~1 MB size probe uploaded to the work
item attachment store, three labelled comments on scratch work item **#15545**,
two attachments uploaded to scratch **PR 8334**, one thread + one reply there,
and one throwaway attachment on each surface used only for the delete probe.
Every comment body starts "spike w32 attachment probe". Nothing outside the
scratch project is written.

    python3 _run_with_mcp_creds.py w32_attachment_probe.py
    W32_MODE=read python3 _run_with_mcp_creds.py w32_attachment_probe.py   # read-back only
    W32_BIG=0 …                                                           # skip the 1 MB probe
"""
import json, os, re, struct, sys, urllib.parse, urllib.request, urllib.error, zlib

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import ORG_URL, ORG, get, post, call, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P  # noqa: E402

WI = int(os.environ.get('W32_WI', '15545'))
PR = int(os.environ.get('W32_PR', '8334'))
MODE = os.environ.get('W32_MODE', 'write')
BIG = os.environ.get('W32_BIG', '1') != '0'
MARKER = 'spike w32 attachment probe'
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
out = [f'# Spike w32 — attachments in comments (scratch writes, mode={MODE})', '']


def sec(t):
    out.extend(['', f'## {t}', ''])


def u(s):
    """Collapse the org/project prefix so the shapes read cleanly."""
    if not isinstance(s, str):
        return s
    return s.replace(ORG_URL + '/', '{org}/')


def make_png(w, h):
    """A deterministic little PNG (no Pillow on this machine)."""
    rows = []
    for y in range(h):
        px = bytearray()
        for x in range(w):
            px += bytes(((x * 5 + y * 3) % 256, (x * 11) % 256, (y * 7 + 40) % 256))
        rows.append(b'\x00' + bytes(px))
    raw = b''.join(rows)

    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


PNG = make_png(48, 48)
TXT = (f'{MARKER}\nA 200-byte plain text file used to check how a non-image attachment '
       'renders in a comment on both surfaces.\n').encode() + b'.' * 40
BIG_BYTES = bytes((i * 37 + (i >> 8) * 11) % 256 for i in range(1_000_000))  # ~1 MB, poorly compressible


def raw(method, url, data=None, headers=None):
    hd = {'Authorization': lib._AUTH}
    hd.update(headers or {})
    req = urllib.request.Request(url, data=data, method=method, headers=hd)
    try:
        r = urllib.request.urlopen(req)
        st, hh, body = r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        st, hh, body = e.code, dict(e.headers), e.read()
    lib.COST_LOG.append((method, lib.redact(url), st, hh.get('X-RateLimit-Cost'),
                         hh.get('X-RateLimit-Delay'), 0))
    return st, hh, body


def anon(method, url):
    """Same request with no Authorization header at all."""
    req = urllib.request.Request(url, method=method)
    try:
        r = urllib.request.urlopen(req)
        return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


# guard: the project we are about to write to really is the scratch project
s, _, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert isinstance(proj, dict) and proj['name'] == SCRATCH, proj
PROJ_GUID = proj['id']
out.append(f'- scratch project `{SCRATCH}` guid `{PROJ_GUID}`, work item #{WI}, PR {PR}')
out.append(f'- payloads: PNG {len(PNG)} bytes, TXT {len(TXT)} bytes'
           + (f', size probe {len(BIG_BYTES)} bytes' if BIG else ''))

state = {}
STATE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results',
                          'w32_attachment_probe', 'state.json')
if MODE != 'write' and os.path.exists(STATE_PATH):
    state = json.load(open(STATE_PATH, encoding='utf-8'))

# =====================================================================  1. work item attachments
sec('1. Work item attachment store — upload')

if MODE == 'write':
    for key, name, data, ctype in (('png', 'w32-probe.png', PNG, 'application/octet-stream'),
                                   ('txt', 'w32-probe.txt', TXT, 'application/octet-stream')):
        url = (f'{ORG_URL}/{P}/_apis/wit/attachments?fileName={name}'
               f'&uploadType=simple&api-version=7.1')
        st, hh, body = raw('POST', url, data, {'Content-Type': ctype})
        try:
            att = json.loads(body)
        except Exception:
            att = body.decode('utf-8', 'replace')[:300]
        out.append(f'- `POST wit/attachments?fileName={name}&uploadType=simple` '
                   f'({len(data)} bytes, octet-stream) → **HTTP {st}**, cost '
                   f'`{hh.get("X-RateLimit-Cost")}`, keys '
                   f'{sorted(att.keys()) if isinstance(att, dict) else att}')
        if isinstance(att, dict):
            out.append(f'  - `url`: `{u(att["url"])}`')
            state[key] = att
    # content-type probe: does the service care what we declare?
    st, hh, body = raw('POST', f'{ORG_URL}/{P}/_apis/wit/attachments?fileName=w32-ctype.png'
                               f'&uploadType=simple&api-version=7.1', PNG,
                       {'Content-Type': 'image/png'})
    out.append(f'- same upload declared `Content-Type: image/png` → **HTTP {st}** '
               f'(so the declared type is {"accepted" if st in (200, 201) else "rejected"}; '
               'the store keys the type off the file name)')
    if st in (200, 201):
        state['ctype'] = json.loads(body)
    # throwaway used only for the delete probe below
    st, hh, body = raw('POST', f'{ORG_URL}/{P}/_apis/wit/attachments?fileName=w32-delete-me.txt'
                               f'&uploadType=simple&api-version=7.1', TXT,
                       {'Content-Type': 'application/octet-stream'})
    if st in (200, 201):
        state['wi_throwaway'] = json.loads(body)
    if BIG:
        st, hh, body = raw('POST', f'{ORG_URL}/{P}/_apis/wit/attachments?fileName=w32-1mb.bin'
                                   f'&uploadType=simple&api-version=7.1', BIG_BYTES,
                           {'Content-Type': 'application/octet-stream'})
        out.append(f'- **size probe**: `uploadType=simple` with {len(BIG_BYTES):,} bytes → '
                   f'**HTTP {st}**, cost `{hh.get("X-RateLimit-Cost")}`')
        if st in (200, 201):
            state['wi_big'] = json.loads(body)
    # what does the service say about a chunked start?
    st, hh, body = raw('POST', f'{ORG_URL}/{P}/_apis/wit/attachments?fileName=w32-chunk.bin'
                               f'&uploadType=chunked&api-version=7.1', b'',
                       {'Content-Type': 'application/octet-stream'})
    out.append(f'- `uploadType=chunked` with an empty body (the documented "start a chunked '
               f'upload" call) → **HTTP {st}**: '
               f'`{lib.redact(body.decode("utf-8", "replace"))[:200]}`')
    if st in (200, 201):
        try:
            state['wi_chunk'] = json.loads(body)
        except Exception:
            pass

PNG_URL = (state.get('png') or {}).get('url')
TXT_URL = (state.get('txt') or {}).get('url')

# =====================================================================  2. work item comments
sec(f'2. Work item comments on #{WI} that reference them')

PROBES = [
    ('A', 'markdown image', 'markdown', lambda: f'{MARKER} A — markdown image\n\n'
                                                f'![w32 probe]({PNG_URL})'),
    ('B', 'html image', 'html', lambda: f'<p>{MARKER} B — html image</p>'
                                        f'<p><img src="{PNG_URL}" alt="w32 probe"></p>'),
    ('C', 'markdown link to a .txt', 'markdown', lambda: f'{MARKER} C — markdown file link\n\n'
                                                         f'[w32-probe.txt]({TXT_URL})'),
]

rel_before = rel_after = None
if MODE == 'write' and PNG_URL and TXT_URL:
    s, _, item = get(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}?api-version=7.1&$expand=relations')
    rel_before = [r for r in (item.get('relations') or []) if r.get('rel') == 'AttachedFile']
    for key, label, fmt, body_fn in PROBES:
        s, _, r = post(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}/comments'
                       f'?api-version=7.1-preview.4&format={fmt}', {'text': body_fn()})
        out.append(f'- POST `comments?format={fmt}` ({key} {label}) → HTTP {s}, id '
                   f'{r.get("id") if isinstance(r, dict) else short(r, 160)}')
    s, _, item = get(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}?api-version=7.1&$expand=relations')
    rel_after = [r for r in (item.get('relations') or []) if r.get('rel') == 'AttachedFile']
    out.append('')
    out.append(f'- `AttachedFile` relations on #{WI} **before** the three comments: '
               f'**{len(rel_before)}**, **after**: **{len(rel_after)}** → posting a comment that '
               f'references an attachment '
               f'{"DOES" if len(rel_after) > len(rel_before) else "does NOT"} add a relation.')

s, _, r = get(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}/comments'
              f'?api-version=7.1-preview.4&$expand=renderedText&order=desc&$top=60')
comments = (r.get('comments') or []) if isinstance(r, dict) else []
out.append('')
out.append(f'Read back with `$expand=renderedText&order=desc` (HTTP {s}, {len(comments)} comments):')
for key, label, fmt, _fn in PROBES:
    c = next((c for c in comments if (c.get('text') or '').find(f'{MARKER} {key} ') >= 0), None)
    out.extend(['', f'### {key}. {label} — sent `format={fmt}`', ''])
    if not c:
        out.append('- not found in the read-back')
        continue
    out.append(f'- comment keys: {sorted(c.keys())}')
    out.append(f'- stored `format`: `{c.get("format")}`')
    out.append('- stored `text`:')
    out.extend(['```', u(c.get('text') or ''), '```'])
    out.append('- `renderedText`:')
    out.extend(['```html', u(c.get('renderedText') or ''), '```'])
    rt = c.get('renderedText') or ''
    out.append(f'- `<img` in renderedText: **{rt.count("<img")}**; '
               f'`<a ` : **{rt.count("<a ")}**; '
               f'attachment guid preserved: **{bool(PNG_URL and PNG_URL.rsplit("/", 1)[-1] in rt) or bool(TXT_URL and TXT_URL.rsplit("/", 1)[-1] in rt)}**')

# ---- does the rendered URL keep the project name or get rewritten to the guid?
rt_all = ' '.join((c.get('renderedText') or '') for c in comments)
hosts = sorted(set(re.findall(r'https?://[^"\')\s]+/_apis/wit/attachments/[^"\')\s]*', rt_all)))
out.extend(['', '- attachment URL shapes seen in `renderedText` on this item:'])
for h in hosts[:6]:
    out.append(f'  - `{u(h)}`')

# =====================================================================  3. fetching the bytes
sec('3. Fetching a work item attachment')
for key, name, expect in (('png', 'w32-probe.png', PNG), ('txt', 'w32-probe.txt', TXT)):
    a = state.get(key)
    if not a:
        continue
    for label, q in (('bare url', ''),
                     (f'?fileName={name}&download=true', f'?fileName={name}&download=true'),
                     (f'?fileName={name} (inline)', f'?fileName={name}')):
        st, hh, body = raw('GET', a['url'] + q)
        out.append(f'- **with** Authorization, `{key}` {label} → HTTP {st}, '
                   f'`{hh.get("Content-Type")}`, {len(body)} bytes, identical: '
                   f'**{body == expect}**'
                   + (f', `Content-Disposition: {hh.get("Content-Disposition")}`'
                      if hh.get('Content-Disposition') else ''))
    st, hh, body = anon('GET', a['url'] + f'?fileName={name}')
    out.append(f'- **without** Authorization, `{key}` → HTTP {st}, `{hh.get("Content-Type")}`, '
               f'{len(body)} bytes'
               + (f', redirects to `{u(hh.get("Location"))[:90]}`' if hh.get('Location') else ''))

# =====================================================================  4. PR attachments
sec(f'4. Pull request attachments (PR {PR})')
s, _, pr = get(f'{ORG_URL}/{P}/_apis/git/pullrequests/{PR}?api-version=7.1')
REPO = (pr.get('repository') or {}).get('id') if isinstance(pr, dict) else None
REPO_NAME = (pr.get('repository') or {}).get('name') if isinstance(pr, dict) else None
out.append(f'- PR {PR} lives in repository `{REPO_NAME}` (`{REPO}`)')
PRA = f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}/pullRequests/{PR}/attachments'

if MODE == 'write':
    # the documented route puts the file name in the PATH
    for key, name, data in (('pr_png', 'w32-pr-probe.png', PNG),
                            ('pr_txt', 'w32-pr-probe.txt', TXT),
                            ('pr_throwaway', 'w32-pr-delete-me.txt', TXT)):
        st, hh, body = raw('POST', f'{PRA}/{name}?api-version=7.1', data,
                           {'Content-Type': 'application/octet-stream'})
        try:
            att = json.loads(body)
        except Exception:
            att = body.decode('utf-8', 'replace')[:300]
        out.append(f'- `POST …/pullRequests/{PR}/attachments/{name}` ({len(data)} bytes) → '
                   f'**HTTP {st}**, cost `{hh.get("X-RateLimit-Cost")}`, '
                   f'{sorted(att.keys()) if isinstance(att, dict) else att}')
        if isinstance(att, dict) and st in (200, 201):
            state[key] = att
            out.append(f'  - `url`: `{u(att.get("url"))}`')
            out.append(f'  - `id`: `{att.get("id")}`, `displayName`: `{att.get("displayName")}`, '
                       f'`contentHash` present: {bool(att.get("contentHash"))}')
    # the query-string form the brief guessed at
    st, hh, body = raw('POST', f'{PRA}?fileName=w32-query-form.png&api-version=7.1', PNG,
                       {'Content-Type': 'application/octet-stream'})
    out.append(f'- the query-string form `POST …/attachments?fileName=…` → **HTTP {st}** '
               f'`{lib.redact(body.decode("utf-8", "replace"))[:160]}`')
    # duplicate name
    st, hh, body = raw('POST', f'{PRA}/w32-pr-probe.png?api-version=7.1', PNG,
                       {'Content-Type': 'application/octet-stream'})
    out.append(f'- re-uploading the **same file name** → **HTTP {st}** '
               f'`{lib.redact(body.decode("utf-8", "replace"))[:160]}`')

s, _, lst = get(f'{PRA}?api-version=7.1')
rows = (lst.get('value') or []) if isinstance(lst, dict) else []
out.append('')
out.append(f'- `GET …/pullRequests/{PR}/attachments` → HTTP {s}, **{len(rows)}** rows; '
           f'row keys {sorted(rows[0].keys()) if rows else "-"}')
for r0 in rows:
    out.append(f'  - `{r0.get("displayName")}` id `{r0.get("id")}` url `{u(r0.get("url"))}`')
if rows and MODE != 'write':
    for r0 in rows:
        if r0.get('displayName') == 'w32-pr-probe.png':
            state['pr_png'] = r0
        if r0.get('displayName') == 'w32-pr-probe.txt':
            state['pr_txt'] = r0
        if r0.get('displayName') == 'w32-pr-delete-me.txt':
            state['pr_throwaway'] = r0

PR_PNG_URL = (state.get('pr_png') or {}).get('url')
PR_TXT_URL = (state.get('pr_txt') or {}).get('url')

# =====================================================================  5. PR thread comments
sec(f'5. PR thread comments on {PR} that reference them')
if MODE == 'write' and PR_PNG_URL and PR_TXT_URL:
    body = {'status': 'active', 'comments': [
        {'parentCommentId': 0, 'commentType': 'text',
         'content': f'{MARKER} — markdown image\n\n![w32 probe]({PR_PNG_URL})'}]}
    s, _, th = post(f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}/pullRequests/{PR}/threads'
                    f'?api-version=7.1', body)
    tid = th.get('id') if isinstance(th, dict) else None
    out.append(f'- POST thread with a markdown image → HTTP {s}, thread `{tid}`')
    state['pr_thread'] = tid
    if tid:
        s, _, cm = post(f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}/pullRequests/{PR}'
                        f'/threads/{tid}/comments?api-version=7.1',
                        {'parentCommentId': 1, 'commentType': 'text',
                         'content': f'{MARKER} — file link [w32-pr-probe.txt]({PR_TXT_URL})'})
        out.append(f'- POST reply with a markdown file link → HTTP {s}, comment '
                   f'`{cm.get("id") if isinstance(cm, dict) else short(cm, 160)}`')
        # a work-item-store attachment URL pasted into a PR comment
        s, _, cm = post(f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}/pullRequests/{PR}'
                        f'/threads/{tid}/comments?api-version=7.1',
                        {'parentCommentId': 1, 'commentType': 'text',
                         'content': f'{MARKER} — cross-store: a **wit** attachment url '
                                    f'![wit]({PNG_URL})'})
        out.append(f'- POST reply pointing at a *work item* attachment url → HTTP {s}')

tid = state.get('pr_thread')
if tid:
    s, _, th = get(f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}/pullRequests/{PR}'
                   f'/threads/{tid}?api-version=7.1')
    cs = (th.get('comments') or []) if isinstance(th, dict) else []
    out.append('')
    out.append(f'Read back thread {tid} (HTTP {s}, {len(cs)} comments):')
    for c in cs:
        out.append(f'- comment {c.get("id")} keys {sorted(c.keys())}')
        out.extend(['```', u(c.get('content') or ''), '```'])
    out.append(f'- any `renderedText` on a PR comment: '
               f'**{any("renderedText" in c for c in cs)}**')
    out.append(f'- thread keys: {sorted(th.keys()) if isinstance(th, dict) else "-"}; '
               f'`properties`: {list((th.get("properties") or {}).keys()) if isinstance(th, dict) else "-"}')

# =====================================================================  6. fetching a PR attachment
sec('6. Fetching a pull request attachment')
for key, expect in (('pr_png', PNG), ('pr_txt', TXT)):
    a = state.get(key)
    if not a or not a.get('url'):
        continue
    st, hh, body = raw('GET', a['url'])
    out.append(f'- **with** Authorization, `{key}` → HTTP {st}, `{hh.get("Content-Type")}`, '
               f'{len(body)} bytes, identical: **{body == expect}**'
               + (f', `Content-Disposition: {hh.get("Content-Disposition")}`'
                  if hh.get('Content-Disposition') else ''))
    st, hh, body = anon('GET', a['url'])
    out.append(f'- **without** Authorization, `{key}` → HTTP {st}, `{hh.get("Content-Type")}`, '
               f'{len(body)} bytes'
               + (f', redirects to `{u(hh.get("Location"))[:90]}`' if hh.get('Location') else ''))
    # the download alias the web uses
    st, hh, body = raw('GET', a['url'] + '?download=true&api-version=7.1')
    out.append(f'  - with `?download=true&api-version=7.1` → HTTP {st}, '
               f'`{hh.get("Content-Type")}`, {len(body)} bytes')

# =====================================================================  7. delete / clean-up
sec('7. Delete and clean-up')
if MODE == 'write':
    a = state.get('pr_throwaway')
    if a:
        st, hh, body = raw('DELETE', f'{PRA}/{a.get("displayName")}?api-version=7.1')
        out.append(f'- `DELETE …/pullRequests/{PR}/attachments/{a.get("displayName")}` → '
                   f'**HTTP {st}** `{lib.redact(body.decode("utf-8", "replace"))[:160]}`')
        st, hh, body = raw('GET', a['url'])
        out.append(f'  - fetching it afterwards → HTTP {st}')
    a = state.get('wi_throwaway')
    if a:
        aid = a['url'].rstrip('/').split('/')[-1].split('?')[0]
        for route in (f'{ORG_URL}/{P}/_apis/wit/attachments/{aid}?api-version=7.1',):
            st, hh, body = raw('DELETE', route)
            out.append(f'- `DELETE wit/attachments/{{guid}}` → **HTTP {st}** '
                       f'`{lib.redact(body.decode("utf-8", "replace"))[:200]}`')
    # is a query-form upload listed?
    s, _, lst = get(f'{PRA}?api-version=7.1')
    rows2 = (lst.get('value') or []) if isinstance(lst, dict) else []
    out.append(f'- attachments left on PR {PR} after the delete probe: **{len(rows2)}** '
               f'({", ".join(r0.get("displayName", "?") for r0 in rows2)})')

out.append('')
out.append(f'**Left behind in scratch:** {len(PROBES)} comments on #{WI} (marker "{MARKER}"), '
           f'one thread + replies on PR {PR}, and the attachments listed above.')

os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
with open(STATE_PATH, 'w', encoding='utf-8', newline='\n') as f:
    json.dump(state, f, indent=1)

out.append(dump_costs())
write_result('w32_attachment_probe/w32.md', '\n'.join(out))
