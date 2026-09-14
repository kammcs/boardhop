"""s50: read-only. How images and files actually appear in *existing* comments in
this org, so the read side of Boardhop's comment renderer is built against real data.

1. The exact `renderedText` the service returns for the three w32 probe comments on
   the scratch item — checked here because w32's own report normalised the org URL
   away and the html probe looked rewritten.
2. Work item comments across a corpus of recent client items: how many carry an
   `<img>`, what URL shapes those images use, and whether the item also carries an
   `AttachedFile` relation for each of them (i.e. does the web's comment editor
   register the attachment on the work item, or only inside the comment body?).
3. Pull request comments across the most recent PRs in the org: how many carry a
   markdown image or an attachment URL, and whether the PR attachment store is used.

No titles, no comment text and no identities reach the file — counts, masked GUIDs
and URL *shapes* only.
"""
import json, os, re, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, post, call, dump_costs, write_result, short  # noqa: E402

SCRATCH_P = urllib.parse.quote('DevOps Mobile App')
WI = int(os.environ.get('W32_WI', '15545'))
CLIENT = os.environ.get('S50_PROJECT', 'CloudCover 2.0')
CP = urllib.parse.quote(CLIENT)
N_ITEMS = int(os.environ.get('S50_ITEMS', '150'))
N_PRS = int(os.environ.get('S50_PRS', '40'))
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
out = ['# Spike s50 — how images and files appear in existing comments (read-only)', '']


def sec(t):
    out.extend(['', f'## {t}', ''])


def mask(s):
    return re.sub(GUID, lambda m: m.group(0)[:8] + '-…', s) if isinstance(s, str) else s


def shape(url):
    """Collapse one URL to a path template: guids and ids become placeholders."""
    u = re.sub(GUID, '{guid}', url)
    u = re.sub(r'(?<=/)\d{2,}(?=[/?]|$)', '{id}', u)
    u = re.sub(r'\?.*$', lambda m: '?' + '&'.join(
        p.split('=')[0] + '=…' for p in m.group(0)[1:].split('&') if p), u)
    u = u.replace(ORG_URL, '{org}')
    u = re.sub(r'https://([a-z.]*dev\.azure\.com)/[^/]+', r'https://\1/{org}', u)
    return u


IMG_SRC = re.compile(r'<img[^>]+src="([^"]+)"', re.I)
A_HREF = re.compile(r'<a[^>]+href="([^"]+)"', re.I)
MD_IMG = re.compile(r'!\[[^\]]*\]\(([^)]+)\)')
MD_LINK = re.compile(r'(?<!!)\[[^\]]*\]\(([^)]+)\)')

# ==========================================================  1. the w32 probes, verbatim
sec(f'1. `renderedText` of the w32 probes on scratch #{WI}, verbatim (no substitutions)')
s, _, r = get(f'{ORG_URL}/{SCRATCH_P}/_apis/wit/workItems/{WI}/comments'
              f'?api-version=7.1-preview.4&$expand=renderedText&order=desc&$top=20')
cs = (r.get('comments') or []) if isinstance(r, dict) else []
for key in ('A', 'B', 'C'):
    c = next((c for c in cs if f'spike w32 attachment probe {key} ' in (c.get('text') or '')), None)
    if not c:
        continue
    rt = c.get('renderedText') or ''
    out.append(f'- **{key}** (`format={c.get("format")}`), `renderedText` srcs/hrefs: '
               f'{[mask(x) for x in IMG_SRC.findall(rt) + A_HREF.findall(rt)]}')
    out.append(f'  - stored `text` srcs/hrefs: '
               f'{[mask(x) for x in IMG_SRC.findall(c.get("text") or "") + MD_IMG.findall(c.get("text") or "") + MD_LINK.findall(c.get("text") or "")]}')
    out.append(f'  - `repr(renderedText)`: `{mask(repr(rt))}`')
out.append('')


# ----------------------------------------------- 1b. does the fetch need `?fileName=`?
import urllib.request, urllib.error  # noqa: E402
import lib as _lib  # noqa: E402

sec('1b. Does fetching a work item attachment need the `?fileName=` query?')
_state_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results',
                           'w32_attachment_probe', 'state.json')
if os.path.exists(_state_path):
    _st = json.load(open(_state_path, encoding='utf-8'))
    for _k, _n in (('png', 'w32-probe.png'), ('txt', 'w32-probe.txt')):
        _a = _st.get(_k)
        if not _a:
            continue
        _bare = _a['url'].split('?')[0]
        for _label, _url in (('bare guid, no query', _bare),
                             ('with `?fileName=`', _a['url']),
                             ('with `?fileName=` + `&api-version=7.1`',
                              _a['url'] + '&api-version=7.1')):
            _req = urllib.request.Request(_url, headers={'Authorization': _lib._AUTH})
            try:
                _r = urllib.request.urlopen(_req)
                _s, _ct, _n2 = _r.status, _r.headers.get('Content-Type'), len(_r.read())
                _cd = _r.headers.get('Content-Disposition')
            except urllib.error.HTTPError as _e:
                _s, _ct, _n2, _cd = _e.code, _e.headers.get('Content-Type'), len(_e.read()), None
            out.append(f'- `{_k}` {_label} → HTTP {_s}, `{_ct}`, {_n2} bytes'
                       + (f', `Content-Disposition: {_cd}`' if _cd else ''))
out.append('')

if os.environ.get('S50_ONLY'):
    out.append(dump_costs())
    write_result('s50_attachment_corpus/s50-1b.md', '\n'.join(out))
    sys.exit(0)

# ==========================================================  2. client work item comments
sec(f'2. Work item comments in "{CLIENT}" — {N_ITEMS} most recently changed items')
wiql = {'query': f"SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = '{CLIENT}' "
                 'ORDER BY [System.ChangedDate] DESC'}
s, _, q = post(f'{ORG_URL}/{CP}/_apis/wit/wiql?api-version=7.1&$top={N_ITEMS}', wiql)
ids = [w['id'] for w in ((q.get('workItems') or []) if isinstance(q, dict) else [])][:N_ITEMS]
out.append(f'- WIQL HTTP {s}: {len(ids)} work items')

wi_comments = wi_with_img = wi_with_link = items_with_img = 0
img_shapes, link_shapes, fmt_mix, img_fmt, md_img_fmt = {}, {}, {}, {}, {}
rel_check = []  # (item, images in comments, AttachedFile relations, matched guids)
odd_srcs = []  # non-absolute image srcs the service produced, verbatim
for wid in ids:
    s, _, c = get(f'{ORG_URL}/{CP}/_apis/wit/workItems/{wid}/comments'
                  f'?api-version=7.1-preview.4&$expand=renderedText&$top=100')
    cms = (c.get('comments') or []) if isinstance(c, dict) else []
    item_imgs = []
    for cm in cms:
        wi_comments += 1
        txt, rt = cm.get('text') or '', cm.get('renderedText') or ''
        fmt_mix[cm.get('format')] = fmt_mix.get(cm.get('format'), 0) + 1
        srcs = IMG_SRC.findall(rt) + IMG_SRC.findall(txt) + MD_IMG.findall(txt)
        hrefs = [h for h in A_HREF.findall(rt) + MD_LINK.findall(txt)
                 if '/_apis/wit/attachments/' in h or '/attachments/' in h]
        if srcs:
            wi_with_img += 1
            img_fmt[cm.get('format')] = img_fmt.get(cm.get('format'), 0) + 1
            if MD_IMG.findall(txt):
                md_img_fmt[cm.get('format')] = md_img_fmt.get(cm.get('format'), 0) + 1
            item_imgs += srcs
            for x in set(srcs):
                img_shapes[shape(x)] = img_shapes.get(shape(x), 0) + 1
            for x in srcs:
                if not x.startswith('http') and len(odd_srcs) < 6:
                    odd_srcs.append((cm.get('format'), mask(repr(x)),
                                     mask(repr((cm.get('text') or '')[:0]))))
        if hrefs:
            wi_with_link += 1
            for x in set(hrefs):
                link_shapes[shape(x)] = link_shapes.get(shape(x), 0) + 1
    if item_imgs:
        items_with_img += 1
        if len(rel_check) < 12:
            s, _, it = get(f'{ORG_URL}/{CP}/_apis/wit/workItems/{wid}'
                           f'?api-version=7.1&$expand=relations')
            rels = [r0 for r0 in ((it.get('relations') or []) if isinstance(it, dict) else [])
                    if r0.get('rel') == 'AttachedFile']
            rel_guids = set()
            for r0 in rels:
                m = re.findall(GUID, r0.get('url') or '')
                if m:
                    rel_guids.add(m[-1].lower())
            img_guids = set()
            for x in item_imgs:
                m = re.findall(GUID, x)
                if m:
                    img_guids.add(m[-1].lower())
            rel_check.append((len(item_imgs), len(rels), len(img_guids),
                              len(img_guids & rel_guids)))

out.append(f'- {wi_comments} comments read; stored `format` mix: {fmt_mix}')
out.append(f'- comments carrying an image: **{wi_with_img}** '
           f'(on **{items_with_img}** of {len(ids)} items)')
out.append(f'- stored `format` of the comments carrying an image: {img_fmt}')
out.append(f'- of those, the ones whose stored `text` uses markdown `![](…)`: {md_img_fmt}')
out.append(f'- comments carrying a link into an attachment store: **{wi_with_link}**')
out.append('- image URL shapes (count):')
for k, v in sorted(img_shapes.items(), key=lambda x: -x[1])[:12]:
    out.append(f'  - `{k}` × {v}')
out.append('- non-absolute image `src` values the service returned, verbatim (`repr`):')
for f, r_, _x in odd_srcs:
    out.append(f'  - stored `format={f}` → `{r_}`')
out.append('- attachment-link shapes (count):')
for k, v in sorted(link_shapes.items(), key=lambda x: -x[1])[:8]:
    out.append(f'  - `{k}` × {v}')
out.append('')
out.append('- does an item whose comments contain images also carry `AttachedFile` relations '
           'for them? (per item: images in comments / AttachedFile relations / distinct image '
           'guids / of those, matched by a relation)')
for a, b, cgu, d in rel_check:
    out.append(f'  - {a} / {b} / {cgu} / **{d}**')
matched = sum(d for _, _, _, d in rel_check)
distinct = sum(cgu for _, _, cgu, _ in rel_check)
out.append(f'  - totals: {distinct} distinct comment-image attachment guids, '
           f'**{matched}** of them also present as an `AttachedFile` relation')

# ==========================================================  3. PR comments
sec(f'3. Pull request comments — {N_PRS} most recent PRs in the org')
s, _, r = get(f'{ORG_URL}/_apis/git/pullrequests?searchCriteria.status=all'
              f'&%24top={N_PRS}&api-version=7.1')
prs = (r.get('value') or []) if isinstance(r, dict) else []
out.append(f'- org-level PR list HTTP {s}: {len(prs)} PRs')
bodies = md_img = att_url = html_img = 0
pr_shapes, att_lists, prs_with_att = {}, 0, 0
repos_seen = set()
for p in prs:
    rid = (p.get('repository') or {}).get('id')
    proj = ((p.get('repository') or {}).get('project') or {}).get('name')
    pid = p.get('pullRequestId')
    if not (rid and pid):
        continue
    repos_seen.add(rid)
    s, _, tr = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullRequests/{pid}'
                   f'/threads?api-version=7.1')
    for th in ((tr.get('value') or []) if isinstance(tr, dict) else []):
        for c in (th.get('comments') or []):
            body = c.get('content') or ''
            bodies += 1
            if '![' in body:
                md_img += 1
                for x in MD_IMG.findall(body):
                    pr_shapes[shape(x)] = pr_shapes.get(shape(x), 0) + 1
            if '<img' in body.lower():
                html_img += 1
            if '/attachments/' in body:
                att_url += 1
                for x in re.findall(r'https?://[^\s)\]"]+/attachments/[^\s)\]"]*', body):
                    pr_shapes[shape(x)] = pr_shapes.get(shape(x), 0) + 1
    s, _, al = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullRequests/{pid}'
                   f'/attachments?api-version=7.1')
    n = len((al.get('value') or []) if isinstance(al, dict) else [])
    att_lists += n
    if n:
        prs_with_att += 1
out.append(f'- {bodies} PR comment bodies across {len(repos_seen)} repositories')
out.append(f'  - bodies with a markdown image `![`: **{md_img}**; with an `<img` tag: '
           f'**{html_img}**; with an `/attachments/` URL: **{att_url}**')
out.append(f'- PRs whose attachment store is non-empty: **{prs_with_att}** of {len(prs)} '
           f'({att_lists} attachments in total)')
out.append('- URL shapes found in PR comment bodies:')
for k, v in sorted(pr_shapes.items(), key=lambda x: -x[1])[:12]:
    out.append(f'  - `{k}` × {v}')

# ==========================================================  4. description-side comparison
sec('4. For comparison: image URL shapes in HTML *fields* of the same corpus')
field_shapes = {}
s, _, b = post(f'{ORG_URL}/_apis/wit/workitemsbatch?api-version=7.1',
               {'ids': ids[:200], '$expand': 'none',
                'fields': ['System.Description', 'Microsoft.VSTS.TCM.ReproSteps',
                           'Microsoft.VSTS.Common.AcceptanceCriteria']})
rows = (b.get('value') or []) if isinstance(b, dict) else []
n_with = 0
for w in rows:
    for v in (w.get('fields') or {}).values():
        if not isinstance(v, str):
            continue
        srcs = IMG_SRC.findall(v)
        if srcs:
            n_with += 1
        for x in set(srcs):
            field_shapes[shape(x)] = field_shapes.get(shape(x), 0) + 1
out.append(f'- {len(rows)} items read in one batch; fields containing an `<img>`: **{n_with}**')
for k, v in sorted(field_shapes.items(), key=lambda x: -x[1])[:12]:
    out.append(f'  - `{k}` × {v}')

out.append(dump_costs())
write_result('s50_attachment_corpus/s50.md', '\n'.join(out))
