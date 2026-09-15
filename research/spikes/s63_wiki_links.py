"""s63 (read-only): how real wiki pages reference attachments, work items,
people and other pages — a construct census over every page of the one client
wiki in puremedia, so the reader is built for what is actually written.

One call fetches the wiki repository as a zip (`git/items?download=true`); the
archive is parsed in memory and never written to disk. The result file holds
counts and construct kinds only: no page titles, no text, no link targets.
"""
import io, os, re, sys, urllib.parse, urllib.request, urllib.error, zipfile
from collections import Counter

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402


def get_bytes(url):
    req = urllib.request.Request(url, headers={'Authorization': lib._AUTH, 'Accept': 'application/zip'})
    try:
        r = urllib.request.urlopen(req)
        st, h, body = r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        st, h, body = e.code, dict(e.headers), e.read()
    lib.COST_LOG.append(('GET', lib.redact(url), st, h.get('X-RateLimit-Cost'), h.get('X-RateLimit-Delay'), 0))
    return st, h, body


OUT = []
SCRATCH = 'DevOps Mobile App'


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def q(s):
    return urllib.parse.quote(str(s), safe='')


st, _, body = get(f'{ORG_URL}/_apis/projects?api-version=7.1')
projects = [(pr['id'], pr['name']) for pr in body.get('value', [])] if st == 200 else []
targets = []
for pid, pname in projects:
    st, _, body = get(f'{ORG_URL}/{q(pname)}/_apis/wiki/wikis?api-version=7.1')
    for w in (body.get('value', []) if isinstance(body, dict) else []):
        targets.append((pid, pname, w))
p(f'wikis found: {len(targets)}')

PATTERNS = {
    'toc [[_TOC_]]': re.compile(r'\[\[_TOC_\]\]'),
    'tosp [[_TOSP_]]': re.compile(r'\[\[_TOSP_\]\]'),
    'front matter (--- at top)': re.compile(r'\A---\r?\n.*?\r?\n---', re.S),
    'front matter with tags:': re.compile(r'\A---\r?\n(?:.*\r?\n)*?tags:', re.S),
    'mermaid ::: block': re.compile(r'^:::\s*mermaid', re.M),
    'mermaid ``` fence': re.compile(r'^```\s*mermaid', re.M),
    'math $$ block': re.compile(r'\$\$'),
    'math inline $…$': re.compile(r'(?<![\$\\])\$(?!\$)[^\n$]+?\$'),
    'video ::: block': re.compile(r'^:::\s*video', re.M),
    'query-table': re.compile(r'query-table\s+[0-9a-f-]{36}'),
    'work item #id': re.compile(r'(?<![\w/#])#\d{2,7}\b'),
    'pull request !id': re.compile(r'(?<!\w)!\d{2,7}\b'),
    'person @<guid>': re.compile(r'@<[0-9a-fA-F-]{36}>'),
    'plain @word': re.compile(r'(?<![\w.])@[A-Za-z][\w.]*'),
    'emoji :name:': re.compile(r'(?<!\w):[a-z0-9_+-]{2,30}:(?!\w)'),
    'task list - [ ]/[x]': re.compile(r'^\s*(?:[-*+]|\d+\.)\s+\[( |x|X)\]', re.M),
    'table row |…|': re.compile(r'^\s*\|.*\|\s*$', re.M),
    'table header sep |---|': re.compile(r'^\s*\|?\s*:?-{3,}:?\s*\|', re.M),
    'code fence ```': re.compile(r'^```', re.M),
    'footnote [^n]': re.compile(r'\[\^[^\]]+\]'),
    'html <details>': re.compile(r'<details', re.I),
    'html <br>': re.compile(r'<br\s*/?>', re.I),
    'html <img': re.compile(r'<img\b', re.I),
    'html <div': re.compile(r'<div\b', re.I),
    'html <table': re.compile(r'<table\b', re.I),
    'html <font/<span/<center': re.compile(r'<(font|span|center)\b', re.I),
    'html <a href': re.compile(r'<a\s+href', re.I),
    'html <video/<iframe': re.compile(r'<(video|iframe)\b', re.I),
    'image ![…](…)': re.compile(r'!\[[^\]]*\]\([^)]+\)'),
    'image with =WxH': re.compile(r'!\[[^\]]*\]\([^)]*\s=\d*x\d*\)'),
    'attachment /.attachments/': re.compile(r'\(/\.attachments/[^)]+\)'),
    'attachment relative .attachments/': re.compile(r'\((?:\./)?\.attachments/[^)]+\)'),
    'link [..](…) total': re.compile(r'(?<!!)\[[^\]]*\]\(([^)]+)\)'),
    'heading #': re.compile(r'^#{1,6}\s', re.M),
    'blockquote >': re.compile(r'^>\s', re.M),
    'hr ---': re.compile(r'^(?:---|\*\*\*)\s*$', re.M),
    'escaped \\#': re.compile(r'\\#'),
    'CRLF line endings': re.compile(r'\r\n'),
}
LINK = re.compile(r'(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
FENCE_LANG = re.compile(r'^```\s*([A-Za-z0-9_+#.-]+)', re.M)

for pid, pname, w in targets:
    label = pname if pname == SCRATCH else f'<project {pid[:8]}>'
    rid = w['repositoryId']
    ver = (w.get('versions') or [{}])[0].get('version')
    mp = w.get('mappedPath') or '/'
    st, h, raw = get_bytes(f'{ORG_URL}/{q(pname)}/_apis/git/repositories/{rid}/items?scopePath={q(mp)}&download=true&$format=zip'
                           f'&versionDescriptor.version={q(ver)}&versionDescriptor.versionType=branch&api-version=7.1')
    p(f'\n=== {label} wiki {w.get("type")} {w["id"][:8]}… zip: HTTP {st} bytes={len(raw)} ===')
    try:
        zf = zipfile.ZipFile(io.BytesIO(raw))
    except zipfile.BadZipFile as e:
        p('bad zip:', e)
        continue
    names = zf.namelist()
    md = [n for n in names if n.lower().endswith('.md')]
    exts = Counter(os.path.splitext(n)[1].lower() for n in names if not n.endswith('/'))
    p(f'entries={len(names)} md files={len(md)} extensions={dict(exts.most_common(12))}')
    counts = Counter()
    pages_with = Counter()
    link_kinds = Counter()
    link_ext = Counter()
    fence_langs = Counter()
    sizes = []
    depth = Counter()
    for n in md:
        text = zf.read(n).decode('utf-8', 'replace')
        sizes.append(len(text))
        depth[n.count('/')] += 1
        for k, rx in PATTERNS.items():
            m = rx.findall(text)
            if m:
                counts[k] += len(m)
                pages_with[k] += 1
        for tgt in LINK.findall(text):
            t = tgt.strip()
            if t.startswith('http://') or t.startswith('https://'):
                if 'dev.azure.com' in t or 'visualstudio.com' in t:
                    if '/_wiki/' in t:
                        kind = 'absolute URL to an ADO wiki page'
                        if re.search(r'/_wiki/wikis/[^/]+/\d+/', t):
                            kind += ' (id form)'
                        elif 'pagePath=' in t:
                            kind += ' (pagePath form)'
                    elif '/_workitems/' in t:
                        kind = 'absolute URL to an ADO work item'
                    elif '/pullrequest/' in t:
                        kind = 'absolute URL to an ADO pull request'
                    else:
                        kind = 'absolute URL to ADO (other)'
                else:
                    kind = 'external http(s)'
            elif t.startswith('mailto:'):
                kind = 'mailto'
            elif t.startswith('#'):
                kind = 'anchor #heading'
            elif t.startswith('/.attachments/'):
                kind = 'attachment /.attachments/'
            elif t.startswith('/'):
                kind = 'absolute wiki path /Parent/Child' + (' (#anchor)' if '#' in t else '')
                if '%2D' in t:
                    link_kinds['   …of which with %2D'] += 1
                if ' ' in t or '%20' in t:
                    link_kinds['   …of which with a space or %20'] += 1
                if '-' in t:
                    link_kinds['   …of which with a hyphen'] += 1
                if t.lower().endswith('.md'):
                    link_kinds['   …of which ending in .md'] += 1
            elif t.startswith('./'):
                kind = 'relative ./Sibling'
            elif t.startswith('../'):
                kind = 'relative ../Other'
            else:
                kind = 'bare relative (no leading / or ./)'
            link_kinds[kind] += 1
            link_ext[os.path.splitext(t.split('#')[0].split('?')[0])[1].lower() or '<none>'] += 1
        for lang in FENCE_LANG.findall(text):
            fence_langs[lang.lower()] += 1
    p(f'page sizes: min={min(sizes) if sizes else 0} median={sorted(sizes)[len(sizes) // 2] if sizes else 0} max={max(sizes) if sizes else 0} chars; '
      f'folder depth histogram={dict(sorted(depth.items()))}')
    p('\nconstruct | occurrences | pages')
    for k in PATTERNS:
        p(f'  {k:38} {counts[k]:6d} {pages_with[k]:5d}')
    p('\nlink targets by kind:')
    for k, v in sorted(link_kinds.items(), key=lambda kv: -kv[1]):
        p(f'  {v:5d}  {k}')
    p('link target extensions:', dict(link_ext.most_common(10)))
    p('code fence languages:', dict(fence_langs.most_common(15)))
    del zf, raw

write_result('s63_wiki_links/s63_wiki_links.md', '\n'.join(OUT) + dump_costs())
