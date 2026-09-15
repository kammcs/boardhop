"""s62 (read-only): the Wiki REST API catalog for the Home hub's Wiki segment
(NEXT-STEPS item 24, research/20 to come).

Questions:

  A  wikis per project: `{project}/_apis/wiki/wikis` at 7.1 — types, versions,
     mappedPath, repositoryId; and the org-wide `_apis/wiki/wikis` route.
  B  page trees: `pages?path=/&recursionLevel=full` (metadata only) — counts,
     depth, nonconformant pages, order, gitItemPath vs path (hyphens, %2D).
  C  one page: JSON with content, ETag, `pages/{id}`, Accept: text/plain,
     `pages/{id}/stats`, `pagesbatch` with pageViewsForDays; content lengths only
     for client pages.
  D  the git items route on the wiki repository (is the wiki repo listed under
     git/repositories; items?recursionLevel=full; one .md item; .attachments).
  E  wiki search shape (`almsearch …/wikisearchresults`).
  F  work item artifact link types (`_apis/wit/artifactlinktypes`) and a
     relations survey over a small sample of items with external links: rel
     names and the `vstfs:///Tool/ArtifactType/` prefix only.
  G  rate-limit costs.

GETs (and search POSTs) only; nothing is written anywhere. Client wiki names,
page titles and text never reach the result file: only counts and shapes.
"""
import json, os, re, sys, urllib.parse
from collections import Counter

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402

OUT = []
SCRATCH = 'DevOps Mobile App'
SEARCH = ORG_URL.replace('https://dev.azure.com', 'https://almsearch.dev.azure.com')
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def q(s):
    return urllib.parse.quote(str(s), safe='')


def mask_guid(s):
    return re.sub(GUID, lambda m: m.group(0)[:8] + '-…', s)


# ---------------------------------------------------------------- A  wikis
st, _, body = get(f'{ORG_URL}/_apis/projects?api-version=7.1')
projects = [(pr['id'], pr['name']) for pr in body.get('value', [])] if st == 200 else []
p('projects:', st, len(projects))

p('\n=== A  wikis per project ===')
wikis = {}  # project name -> list of wikis
for pid, pname in projects:
    is_scratch = pname == SCRATCH
    label = pname if is_scratch else f'<project {pid[:8]}>'
    st, _, body = get(f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis?api-version=7.1')
    wl = body.get('value', []) if isinstance(body, dict) else []
    wikis[pname] = wl
    p(f'\n{label}: HTTP {st} wikis={len(wl)}')
    for w in wl:
        name = w.get('name') if is_scratch else '<wiki>'
        p(f'  type={w.get("type")} name={name} id={w.get("id")[:8]}… repositoryId={str(w.get("repositoryId"))[:8]}… '
          f'mappedPath={w.get("mappedPath")!r} versions={[v.get("version") for v in w.get("versions") or []]} '
          f'isDisabled={w.get("isDisabled")} keys={sorted(w.keys())}')
        if is_scratch:
            p('   raw:', short(w, 900))
st, _, body = get(f'{ORG_URL}/_apis/wiki/wikis?api-version=7.1')
p(f'\norg-wide _apis/wiki/wikis: HTTP {st} count={body.get("count") if isinstance(body, dict) else short(body, 200)}')
st, _, body = get(f'{ORG_URL}/{q(SCRATCH)}/_apis/wiki/wikis?api-version=7.1-preview.2')
p(f'scratch at 7.1-preview.2: HTTP {st}')

# pick the client wiki with the most pages as the "big" sample, read-only
p('\n=== B  page trees (recursionLevel=full, no content) ===')


def walk(page, depth, acc):
    acc['n'] += 1
    acc['maxdepth'] = max(acc['maxdepth'], depth)
    if page.get('isNonConformant'):
        acc['nonconf'] += 1
    if page.get('isParentPage'):
        acc['parents'] += 1
    gp = page.get('gitItemPath') or ''
    if '%2D' in gp:
        acc['pct2d'] += 1
    if ' ' in (page.get('path') or ''):
        acc['space_titles'] += 1
    if page.get('id') is None:
        acc['no_id'] += 1
    for s in page.get('subPages') or []:
        walk(s, depth + 1, acc)


trees = {}
for pid, pname in projects:
    is_scratch = pname == SCRATCH
    label = pname if is_scratch else f'<project {pid[:8]}>'
    for w in wikis.get(pname, []):
        wid = w['id']
        for ver in (w.get('versions') or [{}])[:2]:
            vq = f'&versionDescriptor.version={q(ver["version"])}' if ver.get('version') and w.get('type') == 'codeWiki' else ''
            url = f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pages?path=/&recursionLevel=full{vq}&api-version=7.1'
            st, h, body = get(url)
            if st != 200 or not isinstance(body, dict):
                p(f'{label} wiki {wid[:8]}… ver={ver.get("version")}: HTTP {st} {short(body, 300)}')
                continue
            acc = Counter(n=0, maxdepth=0, nonconf=0, parents=0, pct2d=0, space_titles=0, no_id=0)
            walk(body, 0, acc)
            acc['n'] -= 1  # root
            trees[(pname, wid, ver.get('version'))] = body
            p(f'{label} wiki {w.get("type")} {wid[:8]}… ver={ver.get("version")}: HTTP {st} ETag={h.get("ETag")!r} '
              f'pages={acc["n"]} maxDepth={acc["maxdepth"]} parents={acc["parents"]} nonConformant={acc["nonconf"]} '
              f'gitItemPath-with-%2D={acc["pct2d"]} titles-with-space={acc["space_titles"]} no-id={acc["no_id"]} '
              f'root keys={sorted(body.keys())} root order={body.get("order")} isParentPage={body.get("isParentPage")}')
            if is_scratch:
                p('  scratch tree raw:', short(body, 4000))
            elif body.get('subPages'):
                s0 = body['subPages'][0]
                p('  first child keys=', sorted(s0.keys()), 'order=', s0.get('order'),
                  'path/gitItemPath shape:', mask_guid(re.sub(r'[^/%.\-]', 'x', s0.get('path', ''))),
                  mask_guid(re.sub(r'[^/%.\-]', 'x', s0.get('gitItemPath', ''))))
    # recursion levels compared on the first wiki
    if wikis.get(pname):
        wid = wikis[pname][0]['id']
        for lvl in ('none', 'oneLevel', 'oneLevelPlusNestedEmptyFolders'):
            st, h, body = get(f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pages?path=/&recursionLevel={lvl}&api-version=7.1')
            n = len(body.get('subPages') or []) if isinstance(body, dict) else '-'
            p(f'  {label} recursionLevel={lvl}: HTTP {st} direct children={n}')

# ---------------------------------------------------------------- C  one page
p('\n=== C  one page: content, ETag, by id, text/plain, stats, pagesbatch ===')
# prefer a scratch page; else the biggest client wiki's first leaf page (lengths only)
def first_leaf(page):
    for s in page.get('subPages') or []:
        if not s.get('subPages'):
            return s
        r = first_leaf(s)
        if r:
            return r
    return None


sample = None
for (pname, wid, ver), tree in trees.items():
    if pname == SCRATCH and tree.get('subPages'):
        sample = (pname, wid, ver, first_leaf(tree) or tree['subPages'][0])
        break
if sample is None:
    best = None
    for (pname, wid, ver), tree in trees.items():
        n = len(tree.get('subPages') or [])
        if n and (best is None or n > best[0]):
            best = (n, pname, wid, ver, first_leaf(tree) or tree['subPages'][0])
    if best:
        sample = best[1:]
if sample:
    pname, wid, ver, pg = sample
    is_scratch = pname == SCRATCH
    label = pname if is_scratch else f'<project>'
    vq = f'&versionDescriptor.version={q(ver)}' if ver and any(w['id'] == wid and w['type'] == 'codeWiki' for w in wikis[pname]) else ''
    path = pg['path']
    p(f'sample from {label}: tree node id={pg.get("id")} (tree nodes carry no id) path depth={path.count("/")} path length={len(path)}')
    st, h, body = get(f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pages?path={q(path)}&includeContent=true{vq}&api-version=7.1')
    content = body.get('content') if isinstance(body, dict) else None
    if isinstance(body, dict):
        pg = body
    p(f'  GET pages?path=…&includeContent=true: HTTP {st} ETag={h.get("ETag")!r} keys={sorted(body.keys()) if isinstance(body, dict) else "-"} '
      f'content chars={len(content) if isinstance(content, str) else None} Content-Type={h.get("Content-Type")}')
    if is_scratch:
        p('  content:', short(content or '', 1500))
    pid_ = pg.get('id')
    if pid_ is not None:
        st, h, body = get(f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pages/{pid_}?includeContent=true&api-version=7.1')
        p(f'  GET pages/{{id}}?includeContent=true: HTTP {st} ETag={h.get("ETag")!r} same content={body.get("content") == content if isinstance(body, dict) else "-"} '
          f'remoteUrl shape={mask_guid(re.sub(r"pagePath=.*", "pagePath=…", body.get("remoteUrl", ""))) if isinstance(body, dict) else "-"}')
        st, h, text = call('GET', f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pages/{pid_}?api-version=7.1',
                           headers={'Accept': 'text/plain'}, raw=True)
        p(f'  GET pages/{{id}} Accept: text/plain: HTTP {st} Content-Type={h.get("Content-Type")} ETag={h.get("ETag")!r} '
          f'chars={len(text)} equals JSON content={text == content}')
        st, h, body = get(f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pages/{pid_}/stats?pageViewsForDays=30&api-version=7.1')
        p(f'  GET pages/{{id}}/stats?pageViewsForDays=30: HTTP {st} {short({k: (v if k != "path" else "<path>") for k, v in body.items()} if isinstance(body, dict) else body, 600)}')
        # If-None-Match with the ETag
        st, h, body = call('GET', f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pages/{pid_}?includeContent=true&api-version=7.1',
                           headers={'If-None-Match': h.get('ETag') or ''}, raw=True)
        p(f'  GET pages/{{id}} with If-None-Match=<ETag>: HTTP {st} bytes={len(body)}')
    # pages batch
    st, h, body = post(f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pagesbatch?api-version=7.1{vq}', {'top': 5, 'pageViewsForDays': 30})
    vals = body.get('value', []) if isinstance(body, dict) else []
    p(f'  POST pagesbatch top=5 pageViewsForDays=30: HTTP {st} count={len(vals)} x-ms-continuationtoken={h.get("x-ms-continuationtoken") or h.get("X-MS-ContinuationToken")!r} '
      f'row keys={sorted(vals[0].keys()) if vals else "-"} viewStats rows={[len(v.get("viewStats") or []) for v in vals]}')
    tok = h.get('x-ms-continuationtoken') or h.get('X-MS-ContinuationToken')
    if tok:
        st, h, body = post(f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pagesbatch?api-version=7.1{vq}', {'top': 5, 'continuationToken': tok})
        p(f'  POST pagesbatch continuation: HTTP {st} count={body.get("count") if isinstance(body, dict) else "-"} next={h.get("x-ms-continuationtoken") or h.get("X-MS-ContinuationToken")!r}')
    # a path that does not exist
    st, h, body = get(f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis/{wid}/pages?path=/Boardhop-no-such-page-s62&api-version=7.1')
    p(f'  GET missing path: HTTP {st} typeKey={body.get("typeKey") if isinstance(body, dict) else short(body, 200)}')

# ---------------------------------------------------------------- D  git route
p('\n=== D  git items route on the wiki repository ===')
for pid, pname in projects:
    is_scratch = pname == SCRATCH
    label = pname if is_scratch else f'<project {pid[:8]}>'
    if not wikis.get(pname):
        continue
    st, _, body = get(f'{ORG_URL}/{q(pname)}/_apis/git/repositories?api-version=7.1')
    repos = body.get('value', []) if isinstance(body, dict) else []
    repo_ids = {r['id'] for r in repos}
    for w in wikis[pname]:
        rid = w.get('repositoryId')
        listed = rid in repo_ids
        p(f'{label} wiki {w["type"]} repo {str(rid)[:8]}…: listed in git/repositories={listed} '
          f'(repo isDisabled={next((r.get("isDisabled") for r in repos if r["id"] == rid), None)})')
        st, _, r = get(f'{ORG_URL}/{q(pname)}/_apis/git/repositories/{rid}?api-version=7.1')
        p(f'  GET git/repositories/{{wikiRepoId}}: HTTP {st} name={r.get("name") if is_scratch and isinstance(r, dict) else ("<name>" if st == 200 else short(r, 200))} '
          f'defaultBranch={r.get("defaultBranch") if isinstance(r, dict) else "-"} size={r.get("size") if isinstance(r, dict) else "-"}')
        ver = (w.get('versions') or [{}])[0].get('version')
        vq = f'&versionDescriptor.version={q(ver)}&versionDescriptor.versionType=branch' if ver else ''
        mp = w.get('mappedPath') or '/'
        st, h, r = get(f'{ORG_URL}/{q(pname)}/_apis/git/repositories/{rid}/items?scopePath={q(mp)}&recursionLevel=full{vq}&api-version=7.1')
        items = r.get('value', []) if isinstance(r, dict) else []
        kinds = Counter((it.get('gitObjectType'), os.path.splitext(it.get('path', ''))[1].lower() or ('<dir>' if it.get('isFolder') else '<none>')) for it in items)
        att = [it for it in items if '/.attachments/' in it.get('path', '')]
        orders = [it for it in items if it.get('path', '').endswith('/.order')]
        p(f'  GET items?scopePath={mp}&recursionLevel=full: HTTP {st} items={len(items)} kinds={dict(kinds)} '
          f'.attachments files={len(att)} .order files={len(orders)}')
        if is_scratch:
            p('   paths:', [it.get('path') for it in items][:60])
        md = next((it for it in items if it.get('path', '').endswith('.md')), None)
        if md:
            st, h, text = call('GET', f'{ORG_URL}/{q(pname)}/_apis/git/repositories/{rid}/items?path={q(md["path"])}{vq}&api-version=7.1',
                               headers={'Accept': 'text/plain'}, raw=True)
            p(f'  GET items?path=<one .md> Accept text/plain: HTTP {st} Content-Type={h.get("Content-Type")} chars={len(text)}')
            st, h, r = get(f'{ORG_URL}/{q(pname)}/_apis/git/repositories/{rid}/items?path={q(md["path"])}&includeContent=true{vq}&api-version=7.1')
            p(f'  GET items?path=<one .md>&includeContent=true (json): HTTP {st} keys={sorted(r.keys()) if isinstance(r, dict) else "-"} content chars={len(r.get("content") or "") if isinstance(r, dict) else "-"}')
        if att:
            a = att[0]
            st, h, data = call('GET', f'{ORG_URL}/{q(pname)}/_apis/git/repositories/{rid}/items?path={q(a["path"])}{vq}&api-version=7.1',
                               headers={'Accept': 'application/octet-stream'}, raw=True)
            p(f'  GET items?path=<one attachment> Accept octet-stream: HTTP {st} Content-Type={h.get("Content-Type")} bytes={len(data.encode("utf-8", "replace"))} '
              f'ext={os.path.splitext(a["path"])[1]}')
        if orders:
            st, h, text = call('GET', f'{ORG_URL}/{q(pname)}/_apis/git/repositories/{rid}/items?path={q(orders[0]["path"])}{vq}&api-version=7.1',
                               headers={'Accept': 'text/plain'}, raw=True)
            p(f'  GET root .order Accept text/plain: HTTP {st} lines={len(text.splitlines())}' + (f' text={text.splitlines()!r}' if is_scratch else ''))
        # zip download of the whole wiki
        st, h, data = call('GET', f'{ORG_URL}/{q(pname)}/_apis/git/repositories/{rid}/items?scopePath={q(mp)}&download=true&$format=zip{vq}&api-version=7.1',
                           headers={'Accept': 'application/zip'}, raw=True)
        p(f'  GET items?scopePath=…&download=true&$format=zip: HTTP {st} Content-Type={h.get("Content-Type")} bytes={len(data.encode("latin-1", "replace"))}')
        break  # one wiki per project is enough for D

# ---------------------------------------------------------------- E  search
p('\n=== E  wiki search ===')
for scope, url in (('project', f'{SEARCH}/{q(SCRATCH)}/_apis/search/wikisearchresults?api-version=7.1'),
                   ('org', f'{SEARCH}/_apis/search/wikisearchresults?api-version=7.1')):
    st, h, r = post(url, {'searchText': 'the', '$skip': 0, '$top': 3, 'includeFacets': True})
    res = r.get('results', []) if isinstance(r, dict) else []
    p(f'{scope}: HTTP {st} count={r.get("count") if isinstance(r, dict) else short(r, 300)} infoCode={r.get("infoCode") if isinstance(r, dict) else "-"} '
      f'facets={ {k: len(v) for k, v in (r.get("facets") or {}).items()} if isinstance(r, dict) else "-"} '
      f'result keys={sorted(res[0].keys()) if res else "-"} wiki keys={sorted(res[0]["wiki"].keys()) if res else "-"} '
      f'hits fields={[hh.get("fieldReferenceName") for hh in res[0].get("hits", [])] if res else "-"}')
    if res:
        p(f'  path/fileName shape: {re.sub(r"[^/.%-]", "x", res[0].get("path", ""))} / {re.sub(r"[^/.%-]", "x", res[0].get("fileName", ""))} '
          f'wiki.version={res[0]["wiki"].get("version")} wiki.mappedPath={res[0]["wiki"].get("mappedPath")} '
          f'highlight markup={"<highlighthit>" in json.dumps(res[0].get("hits"))}')
st, h, r = post(f'{SEARCH}/_apis/search/wikisearchresults?api-version=7.1',
                {'searchText': 'the', '$top': 2, 'filters': {'Project': [SCRATCH]}})
p(f'org with filters.Project=[scratch]: HTTP {st} count={r.get("count") if isinstance(r, dict) else short(r, 200)}')

# ---------------------------------------------------------------- F  link types + relations survey
p('\n=== F  artifact link types and relations survey ===')
st, _, r = get(f'{ORG_URL}/_apis/wit/artifactlinktypes?api-version=7.1')
vals = r.get('value', []) if isinstance(r, dict) else []
p(f'artifactlinktypes: HTTP {st} count={len(vals)}')
for v in vals:
    p(f'  toolType={v.get("toolType")!r:22} artifactType={v.get("artifactType")!r:24} linkType={v.get("linkType")!r}')
st, _, r = get(f'{ORG_URL}/_apis/wit/workitemrelationtypes?api-version=7.1')
vals = r.get('value', []) if isinstance(r, dict) else []
p(f'workitemrelationtypes: HTTP {st} count={len(vals)} resourceLinks={[v["referenceName"] for v in vals if (v.get("attributes") or {}).get("usage") == "resourceLink"]}')

rel_counter = Counter()
prefix_counter = Counter()
name_counter = Counter()
wiki_rel_sample = None
for pid, pname in projects:
    wiql = {'query': "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.ExternalLinkCount] > 0 ORDER BY [System.ChangedDate] DESC"}
    st, _, r = post(f'{ORG_URL}/{q(pname)}/_apis/wit/wiql?$top=40&api-version=7.1', wiql)
    ids = [w['id'] for w in (r.get('workItems') or [])] if isinstance(r, dict) else []
    label = pname if pname == SCRATCH else f'<project {pid[:8]}>'
    p(f'{label}: items with ExternalLinkCount>0 (top 40): HTTP {st} n={len(ids)}')
    if not ids:
        continue
    st, _, r = post(f'{ORG_URL}/_apis/wit/workitemsbatch?api-version=7.1', {'ids': ids[:40], '$expand': 'relations'})
    p(f'  workitemsbatch $expand=relations: HTTP {st} items={len(r.get("value") or []) if isinstance(r, dict) else short(r, 200)}')
    for wi in (r.get('value') or []) if isinstance(r, dict) else []:
        for rel in wi.get('relations') or []:
            rel_counter[rel.get('rel')] += 1
            u = rel.get('url') or ''
            m = re.match(r'(vstfs:///[^/]+/[^/]+/)', u)
            if m:
                prefix_counter[m.group(1)] += 1
                name_counter[(m.group(1), (rel.get('attributes') or {}).get('name'))] += 1
                if 'Wiki' in m.group(1) and wiki_rel_sample is None:
                    wiki_rel_sample = rel
            elif u.startswith('http'):
                prefix_counter['http(s) ' + ('wit/workItems' if '/wit/workItems/' in u else 'other')] += 1
p('rel names:', dict(rel_counter))
p('artifact URI prefixes:', dict(prefix_counter))
p('(prefix, attributes.name):', {f'{k[0]} name={k[1]!r}': v for k, v in name_counter.items()})
if wiki_rel_sample:
    u = wiki_rel_sample.get('url', '')
    # mask every guid and the page segment; keep the structure
    shape = mask_guid(u)
    shape = re.sub(r'(vstfs:///Wiki/WikiPage/[^/]*?/[^/]*?/).*', r'\1<page-path…>', shape) if '/Wiki/WikiPage/' in u else shape
    p('wiki relation sample shape:', shape, 'attributes keys:', sorted((wiki_rel_sample.get('attributes') or {}).keys()),
      'name:', (wiki_rel_sample.get('attributes') or {}).get('name'),
      'encoded slashes (%2F) in id part:', '%2F' in u, 'id segments:', u.count('/') - 3)
else:
    p('no vstfs:///Wiki/… relation found in the sample')

# ---------------------------------------------------------------- H  bulk content and index lag (scratch)
p('\n=== H  bulk content, git metadata, search index (scratch) ===')
sw = next((w for w in wikis.get(SCRATCH, []) if w['type'] == 'projectWiki'), None)
if sw:
    wid, rid = sw['id'], sw['repositoryId']
    st, h, body = get(f'{ORG_URL}/{q(SCRATCH)}/_apis/wiki/wikis/{wid}/pages?path=/&recursionLevel=full&includeContent=true&api-version=7.1')
    def cc(pg, acc):
        acc.append(len(pg.get('content') or '') if 'content' in pg else None)
        for s_ in pg.get('subPages') or []:
            cc(s_, acc)
    acc = []
    if isinstance(body, dict):
        cc(body, acc)
    p(f'  pages?path=/&recursionLevel=full&includeContent=true: HTTP {st} content chars per node (root first)={acc}')
    st, h, body = get(f'{ORG_URL}/{q(SCRATCH)}/_apis/wiki/wikis/{wid}/pages?path={q("/Boardhop/Links")}&recursionLevel=full&includeContent=true&api-version=7.1')
    acc = []
    if isinstance(body, dict):
        cc(body, acc)
    p(f'  pages?path=/Boardhop/Links&recursionLevel=full&includeContent=true: HTTP {st} content chars per node={acc}')
    st, h, text = call('GET', f'{ORG_URL}/{q(SCRATCH)}/_apis/wiki/wikis/{wid}/pages?path={q("/Boardhop/Links")}&api-version=7.1',
                       headers={'Accept': 'text/plain'}, raw=True)
    p(f'  pages?path=/Boardhop/Links Accept text/plain: HTTP {st} Content-Type={h.get("Content-Type")} chars={len(text)} ETag={h.get("ETag")!r}')
    st, h, body = get(f'{ORG_URL}/{q(SCRATCH)}/_apis/git/repositories/{rid}/items?scopePath=/&recursionLevel=full&includeContentMetadata=true&latestProcessedChange=true&versionDescriptor.version=wikiMaster&api-version=7.1')
    items = body.get('value', []) if isinstance(body, dict) else []
    md = next((it for it in items if it.get('path', '').endswith('Constructs.md')), {})
    p(f'  git items?recursionLevel=full&includeContentMetadata=true&latestProcessedChange=true: HTTP {st} items={len(items)} one .md keys={sorted(md.keys())} '
      f'contentMetadata={md.get("contentMetadata")} latestProcessedChange keys={sorted((md.get("latestProcessedChange") or {}).keys())}')
    st, h, body = get(f'{ORG_URL}/{q(SCRATCH)}/_apis/git/repositories/{rid}/itemsbatch?api-version=7.1')
    st, h, body = post(f'{ORG_URL}/{q(SCRATCH)}/_apis/git/repositories/{rid}/itemsbatch?api-version=7.1',
                       {'itemDescriptors': [{'path': '/Boardhop.md', 'version': 'wikiMaster', 'versionType': 'branch'},
                                            {'path': '/Boardhop/Links.md', 'version': 'wikiMaster', 'versionType': 'branch'}],
                        'includeContentMetadata': True, 'latestProcessedChange': True})
    p(f'  git itemsbatch (2 paths): HTTP {st} shape={type(body).__name__} rows={len(body.get("value", [])) if isinstance(body, dict) else "-"} '
      f'inner keys={sorted(body["value"][0][0].keys()) if isinstance(body, dict) and body.get("value") and body["value"][0] else "-"} has content={"content" in (body["value"][0][0] if isinstance(body, dict) and body.get("value") and body["value"][0] else {})}')
    st, h, r = post(f'{SEARCH}/{q(SCRATCH)}/_apis/search/wikisearchresults?api-version=7.1', {'searchText': 'Boardhop', '$top': 5, 'includeFacets': True})
    p(f'  wiki search "Boardhop" on scratch (index lag check): HTTP {st} count={r.get("count") if isinstance(r, dict) else "-"} infoCode={r.get("infoCode") if isinstance(r, dict) else "-"}')
    if isinstance(r, dict) and r.get('results'):
        p('   first result:', short(r['results'][0], 1200))
    # 7.2-preview on the pages route, and the wiki-name route with a space in the project
    st, h, r = get(f'{ORG_URL}/{q(SCRATCH)}/_apis/wiki/wikis/{wid}/pages?path=/Boardhop&api-version=7.2-preview.1')
    p(f'  pages at api-version=7.2-preview.1: HTTP {st}')

write_result('s62_wiki_catalog/s62_wiki_catalog.md', '\n'.join(OUT) + dump_costs())
