"""w37: writes, scratch project "DevOps Mobile App" only.

Seeds a project wiki with a small page tree that exercises every wiki
markdown construct the reader must handle, uploads one attachment, pushes one
non-conformant file straight into the wiki git repo, links a page to scratch
work item #15545 with the "Wiki Page" artifact link, then reads everything
back. Every write carries the marker "spike w37". Nothing is deleted.

    python _run_with_mcp_creds.py w37_scratch_wiki.py     # writes, then reads back
    W37_MODE=read python _run_with_mcp_creds.py w37_…     # read-back only, no writes

Only the PAT's own identity (Kelly) is ever mentioned; its guid is masked as
<me-guid> in the result file.
"""
import base64, json, os, re, struct, sys, urllib.parse, urllib.request, urllib.error, zlib

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import ORG_URL, get, post, call, patch, dump_costs, write_result, short  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)
WI = 15545
PR = 8334
MODE = os.environ.get('W37_MODE', 'write')
MARKER = 'spike w37'
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
OUT = [f'# Spike w37 — scratch project wiki (mode={MODE})', '']
ME = {}


def q(s):
    return urllib.parse.quote(str(s), safe='')


def g(v):
    if not isinstance(v, str):
        v = json.dumps(v, indent=1)
    return re.sub(GUID, lambda m: '<me-guid>' if ME.get('id', '').lower() == m.group(0).lower() else m.group(0), v)


def p(*a):
    line = ' '.join(str(x) if isinstance(x, str) else g(x) for x in a)
    print(g(line))
    OUT.append(g(line))


def sec(t):
    OUT.extend(['', f'## {t}', ''])
    print(f'\n## {t}')


def raw_call(method, url, data, content_type, accept='application/json'):
    """lib.call json-encodes bodies; attachments need the raw bytes."""
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={'Authorization': lib._AUTH, 'Content-Type': content_type, 'Accept': accept})
    try:
        r = urllib.request.urlopen(req)
        st, h, body = r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        st, h, body = e.code, dict(e.headers), e.read()
    lib.COST_LOG.append((method, lib.redact(url), st, h.get('X-RateLimit-Cost'), h.get('X-RateLimit-Delay'), 0))
    try:
        return st, h, json.loads(body.decode('utf-8')) if 'json' in h.get('Content-Type', '') else body
    except json.JSONDecodeError:
        return st, h, body


def png_bytes(w=8, h=8, rgb=(0x2b, 0x6c, 0xb0)):
    raw = b''.join(b'\x00' + bytes(rgb) * w for _ in range(h))

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


# ------------------------------------------------------------------ 0. who / where
s, _, r = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
ME['id'] = MID = r['authenticatedUser']['id']
NAME = r['authenticatedUser'].get('providerDisplayName') or 'Me'
s, _, r = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
PROJECT_ID = r['id']
p(f'- project id `{PROJECT_ID}`; mentions use the PAT identity only (`connectionData.authenticatedUser.id`, masked `<me-guid>`).')

# ------------------------------------------------------------------ 1. the wiki
sec('1. Project wiki (create if missing)')
s, _, r = get(f'{ORG_URL}/{P}/_apis/wiki/wikis?api-version=7.1')
wl = r.get('value', []) if isinstance(r, dict) else []
wiki = next((w for w in wl if w.get('type') == 'projectWiki'), None)
if wiki is None and MODE == 'write':
    s, h, r = post(f'{ORG_URL}/{P}/_apis/wiki/wikis?api-version=7.1',
                   {'type': 'projectWiki', 'name': f'{PROJECT}.wiki', 'projectId': PROJECT_ID})
    p(f'- POST wikis (projectWiki) → HTTP {s}')
    p('```json', short(r, 1200), '```')
    wiki = r if s in (200, 201) else None
if wiki is None:
    sys.exit('no project wiki and not in write mode')
WID = wiki['id']
REPO = wiki['repositoryId']
p(f'- wiki id `{WID}` name `{wiki.get("name")}` repositoryId `{REPO}` versions {[v.get("version") for v in wiki.get("versions") or []]} mappedPath `{wiki.get("mappedPath")}`')
p(f'- remoteUrl `{wiki.get("remoteUrl")}`')
p(f'- url `{wiki.get("url")}`')
WIKI_BASE = f'{ORG_URL}/{P}/_apis/wiki/wikis/{WID}'
GIT_BASE = f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}'

# ------------------------------------------------------------------ 2. attachment
sec('2. Attachment upload (PUT attachments, octet-stream vs base64)')
PNG = png_bytes()
ATT_NAME = 'boardhop-w37.png'
if MODE == 'write':
    s, h, r = raw_call('PUT', f'{WIKI_BASE}/attachments?name={q(ATT_NAME)}&api-version=7.1', PNG, 'application/octet-stream')
    p(f'- PUT attachments?name={ATT_NAME} body=raw octet-stream ({len(PNG)} bytes) → HTTP {s} ETag={h.get("ETag")!r}')
    p('```json', short(r if not isinstance(r, bytes) else r.decode("utf-8", "replace"), 600), '```')
    ATT_PATH = r.get('path') if isinstance(r, dict) else f'/.attachments/{ATT_NAME}'
    # read the blob back through git items and compare
    s, h, data = raw_call('GET', f'{GIT_BASE}/items?path={q(ATT_PATH)}&api-version=7.1', None, 'application/json', accept='application/octet-stream')
    same = data == PNG
    p(f'- GET git items?path={ATT_PATH} (octet-stream) → HTTP {s} Content-Type={h.get("Content-Type")} bytes={len(data) if isinstance(data, bytes) else "-"} identical to upload={same}')
    if not same:
        ATT_NAME = 'boardhop-w37-b64.png'
        s, h, r = raw_call('PUT', f'{WIKI_BASE}/attachments?name={q(ATT_NAME)}&api-version=7.1', base64.b64encode(PNG), 'application/octet-stream')
        p(f'- retry PUT attachments?name={ATT_NAME} body=base64 text ({len(base64.b64encode(PNG))} bytes) → HTTP {s} ETag={h.get("ETag")!r}')
        ATT_PATH = r.get('path') if isinstance(r, dict) else f'/.attachments/{ATT_NAME}'
        s, h, data = raw_call('GET', f'{GIT_BASE}/items?path={q(ATT_PATH)}&api-version=7.1', None, 'application/json', accept='application/octet-stream')
        p(f'- GET git items?path={ATT_PATH} → HTTP {s} bytes={len(data) if isinstance(data, bytes) else "-"} identical to upload={data == PNG}')
else:
    ATT_PATH = f'/.attachments/{ATT_NAME}'

# ------------------------------------------------------------------ 3. pages
sec('3. Pages (PUT pages?path=…)')
HOME = f"""# Boardhop wiki spike

{MARKER}: this tree is Boardhop test data for the wiki reader. Home page of the tree.

[[_TOSP_]]

- Constructs: every markdown extension on one page.
- Links: relative links in all forms.
"""
CONSTRUCTS = f"""---
tags:
- boardhop
- spike
title: Constructs
---
[[_TOC_]]

# Constructs

{MARKER}. A page exercising every wiki construct the reader must handle.

## Mentions

Work item #{WI}, pull request !{PR}, person @<{MID}>, plain @{NAME} (not a mention), hex colour \\#ff0000.

## Mermaid

::: mermaid
graph LR
  A[Phone] --> B[Relay]
  B --> C[Azure DevOps]
:::

```mermaid
sequenceDiagram
  App->>ADO: GET pages
  ADO-->>App: 200
```

## Math

Inline $E = mc^2$ and a block:

$$
\\sum_{{i=1}}^{{n}} i = \\frac{{n(n+1)}}{{2}}
$$

## Video

::: video
<iframe width="560" height="315" src="https://www.youtube.com/embed/OtqFyBA6Dbk" allowfullscreen style="border:none"></iframe>
:::

## Table

| Column | Value |
|---|---|
| break | line one<br/>line two |
| mention | #{WI} |

## Task list

- [x] done item
- [ ] open item
1. [ ] numbered task

## HTML block

<div style="border:1px solid #ccc; padding:8px">
<b>bold html</b><br>
<img src="/.attachments/{ATT_NAME}" width="32" alt="html img">
</div>

<details>
<summary>Collapsed section</summary>

Hidden **markdown** inside details.
</details>

## Emoji

Ship it :rocket: :white_check_mark: and escaped \\:smile\\:

## Code

```dart
void main() => print('hello from #{WI}');
```

## Attachment

![boardhop attachment](/.attachments/{ATT_NAME})

![sized attachment](/.attachments/{ATT_NAME} =16x16)

## Anchor and footnote

Back to [the top](#constructs) and to [Math](#math). A footnote[^1].

[^1]: Footnote text (does the web render it?).
"""
LINKS = f"""# Links

{MARKER}. Relative links in every form.

- Absolute wiki path: [Constructs](/Boardhop/Constructs)
- Sibling: [Constructs](./Constructs)
- Parent: [Home](../Boardhop)
- Child with a space: [Deep child](/Boardhop/Links/Deep child)
- Child with a hyphen: [Re-Order](/Boardhop/Links/Re%2DOrder)
- Anchor on another page: [Math](/Boardhop/Constructs#math)
- Page id form: [Constructs by id](/{P}/_wiki/wikis/{q(wiki.get('name'))}/PAGEID/Constructs)
- Attachment file link: [png](/.attachments/{ATT_NAME})
- Plain URL https://dev.azure.com/puremedia/{P}/_wiki/wikis/{q(wiki.get('name'))}?pagePath=%2FBoardhop
"""
DEEP = f"# Deep child\n\n{MARKER}. Title with a space; three levels down. Up: [Links](../Links).\n"
REORDER = f"# Re-Order\n\n{MARKER}. Title with a hyphen.\n"
LEVEL4 = f"# Level 4\n\n{MARKER}. Fourth level.\n"
PAGES = [('/Boardhop', HOME), ('/Boardhop/Constructs', CONSTRUCTS), ('/Boardhop/Links', LINKS),
         ('/Boardhop/Links/Deep child', DEEP), ('/Boardhop/Links/Re-Order', REORDER),
         ('/Boardhop/Links/Deep child/Level 4', LEVEL4)]

# relations on #15545 before any page mentions it
s, _, wi_before = get(f'{ORG_URL}/{P}/_apis/wit/workitems/{WI}?$expand=relations&api-version=7.1')
rels_before = wi_before.get('relations') or []
p(f'- #{WI} before: rev={wi_before.get("rev")} relations={len(rels_before)} rels={sorted(set(r.get("rel") for r in rels_before))}')

created = {}
if MODE == 'write':
    for path, content in PAGES:
        s, h, r = call('PUT', f'{WIKI_BASE}/pages?path={q(path)}&comment={q(MARKER)}&api-version=7.1', {'content': content})
        if s == 412 or (isinstance(r, dict) and 'WikiPageAlreadyExists' in str(r.get('typeKey'))) or s == 500:
            # exists from an earlier run: fetch the ETag and edit
            s0, h0, r0 = get(f'{WIKI_BASE}/pages?path={q(path)}&api-version=7.1')
            s, h, r = call('PUT', f'{WIKI_BASE}/pages?path={q(path)}&comment={q(MARKER)}&api-version=7.1', {'content': content},
                           headers={'If-Match': h0.get('ETag', '')})
            p(f'- PUT (edit with If-Match) {path} → HTTP {s}')
        p(f'- PUT pages?path={path} → HTTP {s} ETag={h.get("ETag")!r} id={r.get("id") if isinstance(r, dict) else "-"} gitItemPath={r.get("gitItemPath") if isinstance(r, dict) else short(r, 300)} order={r.get("order") if isinstance(r, dict) else "-"}')
        if isinstance(r, dict):
            created[path] = r
    # a second PUT without If-Match on an existing page: what happens?
    s, h, r = call('PUT', f'{WIKI_BASE}/pages?path={q("/Boardhop/Links/Re-Order")}&api-version=7.1', {'content': REORDER})
    p(f'- PUT existing page without If-Match → HTTP {s} typeKey={r.get("typeKey") if isinstance(r, dict) else "-"} message={short(r.get("message", "") if isinstance(r, dict) else r, 200)}')

# ------------------------------------------------------------------ 4. a non-conformant page via git push
sec('4. Non-conformant page (git push straight into the wiki repo)')
if MODE == 'write':
    s, _, r = get(f'{GIT_BASE}/refs?filter=heads/wikiMaster&api-version=7.1')
    ref = (r.get('value') or [{}])[0] if isinstance(r, dict) else {}
    old = ref.get('objectId')
    p(f'- refs heads/wikiMaster → HTTP {s} name={ref.get("name")} objectId={old}')
    if old:
        push = {'refUpdates': [{'name': 'refs/heads/wikiMaster', 'oldObjectId': old}],
                'commits': [{'comment': f'{MARKER}: pushed files outside the wiki API',
                             'changes': [
                                 {'changeType': 'add', 'item': {'path': '/Boardhop/Pushed page.md'},
                                  'newContent': {'content': f'# Pushed page\n\n{MARKER}. File name with a space, added by git push, not in .order.\n', 'contentType': 'rawtext'}},
                                 {'changeType': 'add', 'item': {'path': '/Boardhop/Pushed-tidy.md'},
                                  'newContent': {'content': f'# Pushed tidy\n\n{MARKER}. Conventional file name, added by git push, not in .order.\n', 'contentType': 'rawtext'}},
                             ]}]}
        s, h, r = post(f'{GIT_BASE}/pushes?api-version=7.1', push)
        p(f'- POST pushes (2 files) → HTTP {s} commit={((r.get("commits") or [{}])[0].get("commitId") if isinstance(r, dict) else short(r, 300))}')

# ------------------------------------------------------------------ 5. read back
sec('5. Read back: tree, pages by path and id, ETag, text/plain, stats, pagesbatch')
s, h, tree = get(f'{WIKI_BASE}/pages?path=/&recursionLevel=full&api-version=7.1')
p(f'- GET pages?path=/&recursionLevel=full → HTTP {s} ETag={h.get("ETag")!r}')


def walk(pg, depth):
    for sp in pg.get('subPages') or []:
        p(f'  {"  " * depth}- path=`{sp.get("path")}` gitItemPath=`{sp.get("gitItemPath")}` order={sp.get("order")} '
          f'isParentPage={sp.get("isParentPage")} isNonConformant={sp.get("isNonConformant")} id={sp.get("id")} keys={sorted(sp.keys())}')
        walk(sp, depth + 1)


walk(tree, 0)
p('')
ids = {}
for path, content in PAGES + [('/Boardhop/Pushed page', None), ('/Boardhop/Pushed tidy', None), ('/Boardhop/Pushed-tidy', None),
                              ('/Boardhop/Links/Re Order', None), ('/Boardhop/Links/Re%2DOrder', None)]:
    s, h, r = get(f'{WIKI_BASE}/pages?path={q(path)}&includeContent=true&api-version=7.1')
    if s != 200 or not isinstance(r, dict):
        p(f'- GET pages?path={path} → HTTP {s} {short(r, 300)}')
        continue
    ids[path] = r.get('id')
    same = (r.get('content') == content) if content is not None else None
    p(f'- GET pages?path={path}&includeContent=true → HTTP {s} id={r.get("id")} ETag={h.get("ETag")!r} order={r.get("order")} '
      f'gitItemPath=`{r.get("gitItemPath")}` isNonConformant={r.get("isNonConformant")} isParentPage={r.get("isParentPage")} '
      f'content chars={len(r.get("content") or "")} roundtrip identical={same} remoteUrl=`{r.get("remoteUrl")}`')
    if same is False:
        a, b = content, r.get('content') or ''
        i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
        p(f'    first difference at {i}: sent {a[max(0, i - 20):i + 40]!r} got {b[max(0, i - 20):i + 40]!r}')
    if content is None:
        p('    content:', short(r.get('content') or '', 300))

# the git-pushed pages by id (ids from pagesbatch): 248 non-conformant, 249 conventional name
for pid_ in (248, 249):
    s, h, r = get(f'{WIKI_BASE}/pages/{pid_}?includeContent=true&api-version=7.1')
    p(f'- GET pages/{pid_}?includeContent=true (git-pushed page) → HTTP {s} path={r.get("path") if isinstance(r, dict) else "-"} '
      f'gitItemPath={r.get("gitItemPath") if isinstance(r, dict) else "-"} isNonConformant={r.get("isNonConformant") if isinstance(r, dict) else "-"} '
      f'order={r.get("order") if isinstance(r, dict) else "-"} content chars={len(r.get("content") or "") if isinstance(r, dict) else short(r, 200)}')
    s, h, r = get(f'{WIKI_BASE}/pages/{pid_}/stats?pageViewsForDays=30&api-version=7.1')
    p(f'- GET pages/{pid_}/stats → HTTP {s} keys={sorted(r.keys()) if isinstance(r, dict) else short(r, 200)}')
cid = ids.get('/Boardhop/Constructs')
if cid is not None:
    s, h, r = get(f'{WIKI_BASE}/pages/{cid}?includeContent=true&api-version=7.1')
    etag = h.get('ETag')
    p(f'- GET pages/{cid}?includeContent=true → HTTP {s} ETag={etag!r} path={r.get("path") if isinstance(r, dict) else "-"} content chars={len(r.get("content") or "") if isinstance(r, dict) else "-"}')
    s, h, r2 = get(f'{WIKI_BASE}/pages/{cid}?recursionLevel=oneLevel&api-version=7.1')
    p(f'- GET pages/{cid}?recursionLevel=oneLevel → HTTP {s} subPages={len(r2.get("subPages") or []) if isinstance(r2, dict) else "-"} keys={sorted(r2.keys()) if isinstance(r2, dict) else "-"}')
    s, h, text = call('GET', f'{WIKI_BASE}/pages/{cid}?api-version=7.1', headers={'Accept': 'text/plain'}, raw=True)
    p(f'- GET pages/{cid} Accept: text/plain → HTTP {s} Content-Type={h.get("Content-Type")} ETag={h.get("ETag")!r} chars={len(text)} equals content={text == CONSTRUCTS}')
    s, h, body = call('GET', f'{WIKI_BASE}/pages/{cid}?includeContent=true&api-version=7.1', headers={'If-None-Match': etag or ''}, raw=True)
    p(f'- GET pages/{cid} If-None-Match=<ETag> → HTTP {s} bytes={len(body)}')
    s, h, r = get(f'{WIKI_BASE}/pages/{cid}/stats?pageViewsForDays=30&api-version=7.1')
    p(f'- GET pages/{cid}/stats?pageViewsForDays=30 → HTTP {s} {short(r, 400)}')
    s, h, r = get(f'{WIKI_BASE}/pages?path={q("/Boardhop/Constructs")}&versionDescriptor.version=wikiMaster&api-version=7.1')
    p(f'- GET pages?path=…&versionDescriptor.version=wikiMaster → HTTP {s} id={r.get("id") if isinstance(r, dict) else "-"}')
    s, h, r = get(f'{WIKI_BASE}/pages?path={q("/Boardhop/Constructs")}&versionDescriptor.version=nope&api-version=7.1')
    p(f'- GET pages?path=…&versionDescriptor.version=nope → HTTP {s} typeKey={r.get("typeKey") if isinstance(r, dict) else "-"}')
# by wiki name instead of id
s, h, r = get(f'{ORG_URL}/{P}/_apis/wiki/wikis/{q(wiki.get("name"))}/pages?path={q("/Boardhop")}&api-version=7.1')
p(f'- GET wikis/{{wikiName}}/pages?path=/Boardhop → HTTP {s} id={r.get("id") if isinstance(r, dict) else "-"}')
s, h, r = post(f'{WIKI_BASE}/pagesbatch?api-version=7.1', {'top': 20, 'pageViewsForDays': 30})
p(f'- POST pagesbatch top=20 → HTTP {s} continuation={h.get("x-ms-continuationtoken") or h.get("X-MS-ContinuationToken")!r}')
p('```json', short(r, 2500), '```')

# git side
sec('6. Git side of the wiki repo')
s, h, r = get(f'{GIT_BASE}/items?scopePath=/&recursionLevel=full&versionDescriptor.version=wikiMaster&api-version=7.1')
items = r.get('value', []) if isinstance(r, dict) else []
p(f'- GET git items?scopePath=/&recursionLevel=full → HTTP {s} items={len(items)}')
for it in items:
    p(f'  - `{it.get("path")}` {it.get("gitObjectType")}')
for op in ('/.order', '/Boardhop/.order', '/Boardhop/Links/.order'):
    s, h, text = call('GET', f'{GIT_BASE}/items?path={q(op)}&versionDescriptor.version=wikiMaster&api-version=7.1', headers={'Accept': 'text/plain'}, raw=True)
    p(f'- `{op}` → HTTP {s} lines={text.splitlines() if s == 200 else short(text, 200)}')
s, h, r = get(f'{GIT_BASE}/items?path={q("/Boardhop/Constructs.md")}&includeContent=true&versionDescriptor.version=wikiMaster&api-version=7.1')
p(f'- GET git items?path=/Boardhop/Constructs.md&includeContent=true → HTTP {s} identical to page content={r.get("content") == CONSTRUCTS if isinstance(r, dict) else "-"} keys={sorted(r.keys()) if isinstance(r, dict) else "-"}')
s, h, r = get(f'{GIT_BASE}/commits?searchCriteria.itemPath={q("/Boardhop/Constructs.md")}&searchCriteria.$top=5&api-version=7.1')
p(f'- GET git commits?itemPath=/Boardhop/Constructs.md (page history) → HTTP {s} count={r.get("count") if isinstance(r, dict) else "-"} '
  f'first keys={sorted((r.get("value") or [{}])[0].keys()) if isinstance(r, dict) and r.get("value") else "-"} comment={((r.get("value") or [{}])[0].get("comment") if isinstance(r, dict) else "-")!r}')

# ------------------------------------------------------------------ 7. work item link
sec(f'7. Wiki Page artifact link on #{WI}')
s, _, wi_mid = get(f'{ORG_URL}/{P}/_apis/wit/workitems/{WI}?$expand=relations&api-version=7.1')
rels_mid = wi_mid.get('relations') or []
p(f'- #{WI} after the pages that mention it were created, before the link: rev={wi_mid.get("rev")} relations={len(rels_mid)} '
  f'(a `#{WI}` in a wiki page creates a relation: {len(rels_mid) != len(rels_before)})')
ARTIFACT = f'vstfs:///Wiki/WikiPage/{PROJECT_ID}%2F{WID}%2F' + '%2F'.join(q(seg) for seg in 'Boardhop/Constructs'.split('/'))
p(f'- artifact URI (MCP server form, leading slash dropped, segments joined by %2F): `{ARTIFACT}`')
already = [r for r in rels_mid if r.get('url') == ARTIFACT]
if MODE == 'write' and not already:
    ops = [{'op': 'test', 'path': '/rev', 'value': wi_mid['rev']},
           {'op': 'add', 'path': '/relations/-', 'value': {'rel': 'ArtifactLink', 'url': ARTIFACT,
                                                           'attributes': {'name': 'Wiki Page', 'comment': f'{MARKER} link'}}}]
    s, h, r = patch(f'{ORG_URL}/{P}/_apis/wit/workitems/{WI}?api-version=7.1', ops)
    p(f'- PATCH relations/- ArtifactLink name="Wiki Page" → HTTP {s} rev={r.get("rev") if isinstance(r, dict) else short(r, 400)}')
    if s != 200:
        p('```json', short(r, 800), '```')
s, _, wi_after = get(f'{ORG_URL}/{P}/_apis/wit/workitems/{WI}?$expand=relations&api-version=7.1')
rels_after = wi_after.get('relations') or []
p(f'- #{WI} after: rev={wi_after.get("rev")} relations={len(rels_after)}')
for rel in rels_after:
    if rel.get('rel') == 'ArtifactLink' and 'Wiki' in (rel.get('url') or ''):
        p('```json', short(rel, 800), '```')
# the web-visible link count field
s, _, r = get(f'{ORG_URL}/{P}/_apis/wit/workitems/{WI}?fields=System.ExternalLinkCount,System.RelatedLinkCount,System.HyperLinkCount&api-version=7.1')
p(f'- link count fields → HTTP {s} {short(r.get("fields") if isinstance(r, dict) else r, 300)}')

# ------------------------------------------------------------------ 8. search
sec('8. Wiki search on the scratch project (index lag expected)')
SEARCH = ORG_URL.replace('https://dev.azure.com', 'https://almsearch.dev.azure.com')
s, h, r = post(f'{SEARCH}/{P}/_apis/search/wikisearchresults?api-version=7.1', {'searchText': 'Boardhop', '$top': 5, 'includeFacets': True})
p(f'- POST wikisearchresults "Boardhop" → HTTP {s} count={r.get("count") if isinstance(r, dict) else short(r, 200)} infoCode={r.get("infoCode") if isinstance(r, dict) else "-"}')
if isinstance(r, dict) and r.get('results'):
    p('```json', short(r['results'][0], 1200), '```')

write_result('w37_scratch_wiki/w37.md', '\n'.join(OUT) + dump_costs())
