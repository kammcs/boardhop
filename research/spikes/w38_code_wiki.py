"""w38: writes, scratch project "DevOps Mobile App" only.

Closes the "code wikis unverified" gap of research/20. Pushes a `docs/`
folder on two branches of the scratch repository, publishes it as a **code
wiki** ("Boardhop docs"), adds the second branch as a version, then reads the
tree, the pages, the attachment and search back for both versions and records
which path forms the service answers.

    python _run_with_mcp_creds.py w38_code_wiki.py        # writes, then reads back
    W38_MODE=read python _run_with_mcp_creds.py w38_…     # read-back only, no writes

Everything is idempotent: an existing branch, wiki or version is reused.
Nothing outside the scratch project is touched and nothing is deleted.
"""
import json, os, re, struct, sys, time, urllib.parse, zlib

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)
WI = 15545
MODE = os.environ.get('W38_MODE', 'write')
MARKER = 'spike w38'
UNIQUE = 'quaggleboard'
WIKI_NAME = 'Boardhop docs'
B1, B2 = 'wiki-docs', 'wiki-docs-v2'
ZERO = '0' * 40
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
OUT = [f'# Spike w38 — code wiki in the scratch project (mode={MODE})', '']
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


def png_bytes(w=8, h=8, rgb=(0x2b, 0x6c, 0xb0)):
    raw = b''.join(b'\x00' + bytes(rgb) * w for _ in range(h))

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


import base64  # noqa: E402

PNG_B64 = base64.b64encode(png_bytes()).decode()

HOME = f"""# Boardhop docs

{MARKER}: the home page of a **code wiki** published from `/docs`.

[[_TOSP_]]

Work item #{WI} tracks the wiki reader.

Read the [Guide](./Guide) next.

Relative attachment: ![p](.attachments/w38.png)

Root-form attachment: ![p](/.attachments/w38.png)
"""

HOME_V2 = HOME.replace(
    f'{MARKER}: the home page',
    f'Version 2 of this page, on branch `{B2}`.\n\n{MARKER}: the home page')

GUIDE = f"""---
tags:
- boardhop
- codewiki
---
[[_TOC_]]

# Guide

{MARKER}. The word {UNIQUE} appears only in this code wiki, nowhere else in
the organization, so a search hit for it can only come from here.

## Table

| Column | Value |
|---|---|
| break | line one<br/>line two |
| item | #{WI} |

## Code

```dart
void main() => print('a code wiki page');
```

Back to [Home](../Home).
"""

DEEP = f"""# Deep

{MARKER}. Two levels down, under Guide.

An absolute link: [text](/Home).

## Anchor target

Jump to [the anchor](#anchor-target).
"""

ORDER = 'Home\nGuide\n'

FILES = [
    ('/docs/Home.md', HOME, 'rawtext'),
    ('/docs/Guide.md', GUIDE, 'rawtext'),
    ('/docs/Guide/Deep.md', DEEP, 'rawtext'),
    ('/docs/.attachments/w38.png', PNG_B64, 'base64encoded'),
    ('/docs/.order', ORDER, 'rawtext'),
]

# ------------------------------------------------------------------ 0. who / where
s, _, r = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
ME['id'] = r['authenticatedUser']['id']
s, _, r = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
PROJECT_ID = r['id']
p(f'- project `{PROJECT}` id `{PROJECT_ID}`')

# ------------------------------------------------------------------ 1. the repository
sec('1. The scratch repository and its default branch')
s, _, r = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
repos = r.get('value', []) if isinstance(r, dict) else []
p(f'- GET git/repositories → HTTP {s} count={len(repos)}')
for it in repos:
    p(f'  - `{it.get("name")}` id `{it.get("id")}` defaultBranch={it.get("defaultBranch")} isDisabled={it.get("isDisabled")}')
repo = next((x for x in repos if not x.get('isDisabled')), None)
if repo is None:
    sys.exit('no repository in the scratch project')
REPO_ID, REPO_NAME = repo['id'], repo['name']
DEFAULT_REF = repo.get('defaultBranch') or 'refs/heads/main'
DEFAULT_BRANCH = DEFAULT_REF.split('/')[-1]
GIT = f'{ORG_URL}/{P}/_apis/git/repositories/{REPO_ID}'
s, _, r = get(f'{GIT}/refs?filter=heads/&api-version=7.1')
heads = {x['name']: x['objectId'] for x in (r.get('value') or [])} if isinstance(r, dict) else {}
p(f'- refs heads → {sorted(heads)}')
BASE = heads.get(DEFAULT_REF)
p(f'- default branch `{DEFAULT_BRANCH}` head `{BASE}`')


def push(branch, old, changes, comment):
    body = {'refUpdates': [{'name': f'refs/heads/{branch}', 'oldObjectId': old}],
            'commits': [{'comment': comment, 'changes': changes}]}
    s, h, r = post(f'{GIT}/pushes?api-version=7.1', body)
    cid = (r.get('commits') or [{}])[0].get('commitId') if isinstance(r, dict) else None
    p(f'- POST pushes {branch} (old={old[:8] if old else old}, {len(changes)} changes) → HTTP {s} commit={cid}')
    if s not in (200, 201):
        p('```json', short(r, 700), '```')
    return cid


# ------------------------------------------------------------------ 2. the two branches
sec('2. Push `docs/` on two branches')
if f'refs/heads/{B1}' not in heads and MODE == 'write':
    changes = [{'changeType': 'add', 'item': {'path': path},
                'newContent': {'content': content, 'contentType': ct}}
               for path, content, ct in FILES]
    push(B1, BASE, changes, f'{MARKER}: docs/ folder for a code wiki')
else:
    p(f'- `{B1}` already exists at `{heads.get(f"refs/heads/{B1}")}` (no push)')
s, _, r = get(f'{GIT}/refs?filter=heads/&api-version=7.1')
heads = {x['name']: x['objectId'] for x in (r.get('value') or [])} if isinstance(r, dict) else {}
H1 = heads.get(f'refs/heads/{B1}')
if f'refs/heads/{B2}' not in heads and MODE == 'write':
    push(B2, H1, [{'changeType': 'edit', 'item': {'path': '/docs/Home.md'},
                   'newContent': {'content': HOME_V2, 'contentType': 'rawtext'}}],
         f'{MARKER}: Version 2 of the home page')
else:
    p(f'- `{B2}` already exists at `{heads.get(f"refs/heads/{B2}")}` (no push)')
s, _, r = get(f'{GIT}/items?scopePath=/docs&recursionLevel=full&versionDescriptor.version={B1}&api-version=7.1')
p(f'- GET git items scopePath=/docs on {B1} → HTTP {s}')
for it in (r.get('value') or []) if isinstance(r, dict) else []:
    p(f'  - `{it.get("path")}` {it.get("gitObjectType")}')

# ------------------------------------------------------------------ 3. publish the code wiki
sec('3. Publish the code wiki and add the second version')
WIKIS = f'{ORG_URL}/{P}/_apis/wiki/wikis'
s, _, r = get(f'{WIKIS}?api-version=7.1')
wl = r.get('value', []) if isinstance(r, dict) else []
p(f'- GET wikis → HTTP {s} count={len(wl)} names={[w.get("name") for w in wl]}')
wiki = next((w for w in wl if w.get('name') == WIKI_NAME), None)
if wiki is None and MODE == 'write':
    body = {'type': 'codeWiki', 'name': WIKI_NAME, 'projectId': PROJECT_ID,
            'repositoryId': REPO_ID, 'mappedPath': '/docs',
            'version': {'version': B1}}
    p(f'- POST wikis body={json.dumps(body)}')
    s, h, r = post(f'{WIKIS}?api-version=7.1', body)
    p(f'- POST wikis (codeWiki, mappedPath="/docs") → HTTP {s}')
    p('```json', short(r, 1000), '```')
    if s not in (200, 201):
        body['mappedPath'] = 'docs'
        p(f'- retry with mappedPath="docs": {json.dumps(body)}')
        s, h, r = post(f'{WIKIS}?api-version=7.1', body)
        p(f'- POST wikis (mappedPath="docs") → HTTP {s}')
        p('```json', short(r, 1000), '```')
    wiki = r if s in (200, 201) else None
if wiki is None:
    sys.exit('no code wiki')
WID = wiki['id']
p(f'- wiki id `{WID}` type={wiki.get("type")} repositoryId `{wiki.get("repositoryId")}` '
  f'(== repo `{REPO_ID}`: {wiki.get("repositoryId") == REPO_ID}) mappedPath `{wiki.get("mappedPath")}` '
  f'versions {[v.get("version") for v in wiki.get("versions") or []]}')
p(f'- remoteUrl `{wiki.get("remoteUrl")}`')
p(f'- keys {sorted(wiki.keys())}')

have = [v.get('version') for v in wiki.get('versions') or []]
if B2 not in have and MODE == 'write':
    for label, body in (
        ('versions: [{version: B1}, {version: B2}]', {'versions': [{'version': B1}, {'version': B2}]}),
        ('versions: [{version: B2}]', {'versions': [{'version': B2}]}),
        ('version: {version: B2}', {'version': {'version': B2}}),
    ):
        s, h, r = call('PATCH', f'{WIKIS}/{WID}?api-version=7.1', body)
        p(f'- PATCH wikis/{{id}} {label} → HTTP {s} versions='
          f'{[v.get("version") for v in (r.get("versions") or [])] if isinstance(r, dict) else short(r, 300)}')
        if s == 200 and isinstance(r, dict) and B2 in [v.get('version') for v in r.get('versions') or []]:
            p(f'  **accepted shape:** `PATCH wikis/{{id}}` with `{json.dumps(body)}`')
            break
        if isinstance(r, dict) and r.get('typeKey'):
            p(f'  typeKey={r.get("typeKey")} message={short(r.get("message", ""), 240)}')
s, _, r = get(f'{WIKIS}/{WID}?api-version=7.1')
wiki = r if isinstance(r, dict) else wiki
p(f'- GET wikis/{{id}} → HTTP {s} versions {[v.get("version") for v in wiki.get("versions") or []]} '
  f'mappedPath `{wiki.get("mappedPath")}` repositoryId `{wiki.get("repositoryId")}`')
s, _, r = get(f'{WIKIS}?api-version=7.1')
for w in (r.get('value') or []) if isinstance(r, dict) else []:
    p(f'  - list row: name `{w.get("name")}` type={w.get("type")} mappedPath `{w.get("mappedPath")}` '
      f'versions {[v.get("version") for v in w.get("versions") or []]} repositoryId `{w.get("repositoryId")}`')
# by name as well as by id
s, _, r = get(f'{ORG_URL}/{P}/_apis/wiki/wikis/{q(WIKI_NAME)}?api-version=7.1')
p(f'- GET wikis/{{name}} ("{WIKI_NAME}", a name with a space) → HTTP {s} id={r.get("id") if isinstance(r, dict) else short(r, 200)}')
s, _, r = get(f'{ORG_URL}/{P}/_apis/wiki/wikis/{q(WIKI_NAME.replace(" ", "-"))}?api-version=7.1')
p(f'- GET wikis/{{name}} ("{WIKI_NAME.replace(" ", "-")}") → HTTP {s} id={r.get("id") if isinstance(r, dict) else short(r, 200)}')

W = f'{WIKIS}/{WID}'

# ------------------------------------------------------------------ 4. tree and pages per version
sec('4. Tree, pages and ids per version')


def walk(pg, depth):
    for sp in pg.get('subPages') or []:
        p(f'  {"  " * depth}- path=`{sp.get("path")}` gitItemPath=`{sp.get("gitItemPath")}` order={sp.get("order")} '
          f'isParentPage={sp.get("isParentPage")} isNonConformant={sp.get("isNonConformant")} id={sp.get("id")}')
        walk(sp, depth + 1)


ids = {}
for branch in (B1, B2):
    p('')
    p(f'### version `{branch}`')
    s, h, tree = get(f'{W}/pages?path=/&recursionLevel=full&versionDescriptor.version={q(branch)}&api-version=7.1')
    p(f'- GET pages?path=/&recursionLevel=full&versionDescriptor.version={branch} → HTTP {s} '
      f'root path=`{tree.get("path") if isinstance(tree, dict) else "-"}` '
      f'gitItemPath=`{tree.get("gitItemPath") if isinstance(tree, dict) else "-"}` ETag={h.get("ETag")!r}')
    if isinstance(tree, dict):
        walk(tree, 0)
    s, h, r = post(f'{W}/pagesbatch?versionDescriptor.version={q(branch)}&api-version=7.1', {'top': 50, 'pageViewsForDays': 30})
    rows = r.get('value', []) if isinstance(r, dict) else []
    ids[branch] = {x.get('path'): x.get('id') for x in rows}
    p(f'- POST pagesbatch?versionDescriptor.version={branch} → HTTP {s} rows={len(rows)} '
      f'ids={json.dumps(ids[branch], sort_keys=True)}')
    if rows:
        p('```json', short(rows[0], 500), '```')
    for path in ('/Home', '/Guide', '/Guide/Deep', '/docs/Home'):
        s, h, r = get(f'{W}/pages?path={q(path)}&includeContent=true&versionDescriptor.version={q(branch)}&api-version=7.1')
        if s != 200 or not isinstance(r, dict):
            p(f'- GET pages?path={path} ({branch}) → HTTP {s} typeKey={r.get("typeKey") if isinstance(r, dict) else short(r, 200)}')
            continue
        content = r.get('content') or ''
        p(f'- GET pages?path={path}&includeContent=true ({branch}) → HTTP {s} id={r.get("id")} ETag={h.get("ETag")!r} '
          f'order={r.get("order")} gitItemPath=`{r.get("gitItemPath")}` isParentPage={r.get("isParentPage")} '
          f'chars={len(content)} has"Version 2"={"Version 2" in content}')
        p(f'    remoteUrl=`{r.get("remoteUrl")}`')
    # by id, without a version
    pid = ids[branch].get('/Home')
    if pid:
        s, h, r = get(f'{W}/pages/{pid}?includeContent=true&api-version=7.1')
        p(f'- GET pages/{pid} (no version) → HTTP {s} path=`{r.get("path") if isinstance(r, dict) else "-"}` '
          f'has"Version 2"={"Version 2" in (r.get("content") or "") if isinstance(r, dict) else "-"}')
        s, h, r = get(f'{W}/pages/{pid}?includeContent=true&versionDescriptor.version={q(B2)}&api-version=7.1')
        p(f'- GET pages/{pid}?versionDescriptor.version={B2} → HTTP {s} path=`{r.get("path") if isinstance(r, dict) else "-"}` '
          f'has"Version 2"={"Version 2" in (r.get("content") or "") if isinstance(r, dict) else "-"}')
p('')
p(f'- ids identical across the two versions: {ids.get(B1) == ids.get(B2)} '
  f'({json.dumps(ids.get(B1), sort_keys=True)} vs {json.dumps(ids.get(B2), sort_keys=True)})')
# no version at all
s, h, tree = get(f'{W}/pages?path=/&recursionLevel=full&api-version=7.1')
p(f'- GET pages?path=/&recursionLevel=full **without** a version → HTTP {s} '
  f'top-level={[x.get("path") for x in (tree.get("subPages") or [])] if isinstance(tree, dict) else short(tree, 200)}')
s, h, r = get(f'{W}/pages?path=/Home&includeContent=true&versionDescriptor.version=nope&api-version=7.1')
p(f'- GET pages?path=/Home with a bad version → HTTP {s} typeKey={r.get("typeKey") if isinstance(r, dict) else short(r, 200)}')

# ------------------------------------------------------------------ 5. attachment through git items
sec('5. The attachment under mappedPath')
for path in ('/docs/.attachments/w38.png', '/.attachments/w38.png'):
    for branch in (B1,):
        st, h, data = call('GET', f'{GIT}/items?path={q(path)}&versionDescriptor.version={q(branch)}&api-version=7.1',
                           headers={'Accept': 'application/octet-stream'}, raw=True)
        p(f'- GET git items?path={path}&version={branch} → HTTP {st} Content-Type={h.get("Content-Type")} bytes={len(data)}')
s, h, r = get(f'{GIT}/items?path={q("/docs/.order")}&includeContent=true&versionDescriptor.version={q(B1)}&api-version=7.1')
p(f'- GET git items /docs/.order → HTTP {s} content={((r.get("content") or "") if isinstance(r, dict) else short(r, 200))!r}')
s, h, r = get(f'{GIT}/commits?searchCriteria.itemPath={q("/docs/Home.md")}&searchCriteria.itemVersion.version={q(B1)}'
              f'&searchCriteria.$top=1&api-version=7.1')
p(f'- GET git commits itemPath=/docs/Home.md itemVersion={B1} → HTTP {s} count={r.get("count") if isinstance(r, dict) else "-"} '
  f'comment={((r.get("value") or [{}])[0].get("comment") if isinstance(r, dict) and r.get("value") else "-")!r}')
s, h, r = get(f'{GIT}/commits?searchCriteria.itemPath={q("/Home.md")}&searchCriteria.itemVersion.version={q(B1)}'
              f'&searchCriteria.$top=1&api-version=7.1')
p(f'- GET git commits itemPath=/Home.md (without mappedPath) → HTTP {s} count={r.get("count") if isinstance(r, dict) else "-"}')

# ------------------------------------------------------------------ 6. search
sec('6. Wiki search for the unique word (index lag expected)')
SEARCH = ORG_URL.replace('https://dev.azure.com', 'https://almsearch.dev.azure.com')
for attempt in range(int(os.environ.get('W38_SEARCH_TRIES', '1'))):
    s, h, r = post(f'{SEARCH}/{P}/_apis/search/wikisearchresults?api-version=7.1',
                   {'searchText': UNIQUE, '$top': 5, 'includeFacets': True})
    n = r.get('count') if isinstance(r, dict) else None
    p(f'- POST wikisearchresults "{UNIQUE}" (try {attempt + 1}) → HTTP {s} count={n} '
      f'infoCode={r.get("infoCode") if isinstance(r, dict) else "-"}')
    if n:
        p('```json', short(r['results'][0], 1400), '```')
        break
    if attempt + 1 < int(os.environ.get('W38_SEARCH_TRIES', '1')):
        time.sleep(60)

write_result('w38_code_wiki/w38.md', '\n'.join(OUT) + dump_costs())
