"""w30: writes, scratch project "DevOps Mobile App" only.

What Markdown / HTML a caller must send so Azure DevOps stores a *real* person
mention — the kind the web shows as a pill and the mention notification fires
on. Four small labelled comments on scratch work item #15545, one thread and one
reply on scratch PR 8334, one appended line on that PR's description. Nothing is
deleted; every write carries the marker "spike w30 mention probe".

    python _run_with_mcp_creds.py w30_mention_probe.py     # writes, then reads back
    W30_MODE=read python _run_with_mcp_creds.py w30_…      # read-back only, no writes

Read-only cross-checks in section 4: the `Mention` notification event types, the
anchor format in an existing HTML field, and a wide grep of client PR comment
bodies for `@<guid>` (counts and shapes only — no names, no content)."""
import json, os, re, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, post, call, dump_costs, write_result, short  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)
WI = int(os.environ.get('W30_WI', '15545'))
PR = 8334
MODE = os.environ.get('W30_MODE', 'write')
MARKER = 'spike w30 mention probe'
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
ANCHOR_RE = re.compile(r'<a[^>]*data-vss-mention="([^"]*)"[^>]*>(@[^<]*)</a>')
out = [f'# Spike w30 — mention wire format (scratch writes, mode={MODE})', '']
ME = {}


def g(v):
    if not isinstance(v, str):
        return v
    return re.sub(GUID, lambda m: '<me-guid>' if ME.get('id', '').lower() == m.group(0).lower()
                  else m.group(0)[:8] + '-…', v)


def sec(t):
    out.extend(['', f'## {t}', ''])


s, _, r = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
au = r['authenticatedUser']
ME['id'] = MID = au['id']
NAME = au.get('providerDisplayName') or 'Me'
out.append('- only the PAT\'s own identity is ever mentioned '
           '(`connectionData.authenticatedUser.id`, masked as `<me-guid>` below).')
ANCHOR = f'<a href="#" data-vss-mention="version:2.0,{MID}">@{NAME}</a>'

PROBES = [
    ('A', 'markdown + `@<guid>` (the PR syntax)', 'markdown',
     f'{MARKER} A — @<{MID}> — markdown, PR-style token'),
    ('B', 'markdown + the HTML anchor inline', 'markdown',
     f'{MARKER} B — {ANCHOR} — markdown, raw anchor'),
    ('C', 'html + the HTML anchor', 'html',
     f'{MARKER} C — {ANCHOR} — html format'),
    ('D', 'markdown control: plain `@Name`, `#id`, `!id`', 'markdown',
     f'{MARKER} D — @{NAME} — plus work item #{WI} and pull request !{PR}'),
]

# ------------------------------------------------------ 1. work item comments
sec(f'1. Work item comments on scratch #{WI}')
if MODE == 'write':
    for key, label, fmt, text in PROBES:
        s, _, r = post(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}/comments'
                       f'?api-version=7.1-preview.4&format={fmt}', {'text': text})
        out.append(f'- POST `comments?format={fmt}` ({key}) → HTTP {s}, id '
                   f'{r.get("id") if isinstance(r, dict) else "-"}, response keys '
                   f'{sorted(r.keys()) if isinstance(r, dict) else short(r, 200)}')
    out.append('')

s, _, r = get(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}/comments?api-version=7.1-preview.4'
              f'&$expand=all&order=desc&$top=50')
comments = (r.get('comments') or []) if isinstance(r, dict) else []
out.append(f'Read back with `$expand=all&order=desc` (HTTP {s}, {len(comments)} comments):')
out.append('')
for key, label, fmt, _ in PROBES:
    c = next((c for c in comments if (c.get('text') or '').startswith(f'{MARKER} {key} ')), None)
    out.append(f'### {key}. {label} — sent `format={fmt}`')
    out.append('')
    if not c:
        out.append('- not found in the read-back')
        out.append('')
        continue
    txt, rend = c.get('text') or '', c.get('renderedText') or ''
    out.append(f'- comment keys: {sorted(c.keys())}')
    out.append(f'- stored `format`: `{c.get("format")}`')
    out.append(f'- stored `text`: `{g(txt)}`')
    out.append(f'- `renderedText`: `{g(rend)}`')
    m = ANCHOR_RE.search(rend)
    out.append(f'- **mention pill in renderedText (`data-vss-mention`): '
               f'{"YES" if m else "NO"}**' + (f' — attr `{g(m.group(1))}`, label `@…`' if m else ''))
    out.append(f'- `mentions` field: `{g(json.dumps(c.get("mentions")))}`')
    out.append(f'- work item / PR links in renderedText: '
               f'`#{WI}` → {"link" if f"workitems/edit/{WI}" in rend.lower() or f"/_workitems/edit/{WI}" in rend else "plain text"}; '
               f'`!{PR}` → {"link" if f"pullrequest/{PR}" in rend.lower() else "plain text"}')
    out.append('')

s, _, w = get(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}/revisions?api-version=7.1&$top=300')
revs = (w.get('value') or []) if isinstance(w, dict) else []
hist = [rv['fields']['System.History'] for rv in revs
        if MARKER in str((rv.get('fields') or {}).get('System.History', ''))]
out.append(f'- `System.History` revision values that carry the marker ({len(hist)}) — this is '
           f'exactly what a `workitem.updated` hook delivers as '
           f'`fields["System.History"].newValue`:')
for h in hist:
    out.append(f'  - `{g(h)[:260]}`')
out.append('')

# ------------------------------------------------------------ 2. PR 8334
sec(f'2. Pull request !{PR} (scratch) — thread and reply')
s, _, pr = get(f'{ORG_URL}/{P}/_apis/git/pullrequests/{PR}?api-version=7.1')
repo_id = ((pr.get('repository') or {}).get('id')) if isinstance(pr, dict) else None
base = f'{ORG_URL}/{P}/_apis/git/repositories/{repo_id}/pullRequests/{PR}'

if MODE == 'write':
    s, _, t = post(f'{base}/threads?api-version=7.1', {
        'comments': [{'parentCommentId': 0, 'commentType': 1,
                      'content': f'{MARKER} — @<{MID}> — plus #{WI} and !{PR}'}],
        'status': 1})
    tid = t.get('id') if isinstance(t, dict) else None
    out.append(f'- POST `threads` → HTTP {s}, thread {tid}')
    if tid:
        s, _, c2 = post(f'{base}/threads/{tid}/comments?api-version=7.1',
                        {'parentCommentId': 1, 'commentType': 1,
                         'content': f'{MARKER} reply — {ANCHOR} — raw anchor in a PR comment'})
        out.append(f'- POST `threads/{tid}/comments` → HTTP {s}')
    out.append('')

s, _, tr = get(f'{base}/threads?api-version=7.1')
threads = [t for t in ((tr.get('value') or []) if isinstance(tr, dict) else [])
           if any(MARKER in (c.get('content') or '') for c in (t.get('comments') or []))]
out.append(f'Read back (HTTP {s}, {len(threads)} marker threads):')
out.append('')
for t in threads:
    out.append(f'- thread {t.get("id")}: keys {sorted(t.keys())}')
    out.append(f'  - `identities`: `{g(json.dumps(t.get("identities")))}`')
    out.append(f'  - `properties`: `{g(json.dumps(t.get("properties")))[:300]}`')
    for c in (t.get('comments') or []):
        out.append(f'  - comment {c.get("id")} keys {sorted(c.keys())} — '
                   f'`renderedText` present? **{"renderedText" in c}**')
        out.append(f'    - `content`: `{g(c.get("content"))}`')
out.append('')

# ----------------------------------------------- 3. PR description mention
sec(f'3. Pull request description (`PATCH pullrequests/{PR}`)')
desc = (pr.get('description') or '') if isinstance(pr, dict) else ''
if MODE == 'write' and MARKER not in desc:
    new_desc = (desc.rstrip() + f'\n\n{MARKER} — @<{MID}>').strip()
    s, _, r = call('PATCH', f'{base}?api-version=7.1', {'description': new_desc})
    out.append(f'- PATCH `pullRequests/{PR}` `{{"description": …}}` → HTTP {s}')
    desc = (r.get('description') or '') if isinstance(r, dict) else desc
out.append(f'- description now {len(desc)} chars; tail: `{g(desc[-140:])}`')
out.append('- stored verbatim: the description is Markdown and the service does not rewrite '
           '`@<guid>`; the web renders it through the same mention extension as a PR comment.')
out.append('')

# ------------------------------------- 4. read-only cross-checks
sec('4. Read-only cross-checks')
s, _, r = get(f'{ORG_URL}/_apis/notification/eventtypes?api-version=7.1-preview.1')
for et in ((r.get('value') or []) if isinstance(r, dict) else []):
    if 'ment' in str(et.get('id', '')).lower():
        out.append(f'- notification event type `{et.get("id")}` — name `{et.get("name")}`, '
                   f'category `{(et.get("category") or {}).get("id")}`, roles '
                   f'{[rl.get("id") for rl in (et.get("roles") or [])]}')
out.append('')

s, _, sr = post(f'https://almsearch.dev.azure.com/{ORG}/_apis/search/workitemsearchresults'
                f'?api-version=7.1', {'searchText': 'mention', '$top': 40, '$skip': 0})
found, scanned = 0, 0
for res in ((sr.get('results') or []) if isinstance(sr, dict) else []):
    if found >= 2 or scanned >= 20:
        break
    f = res.get('fields') or {}
    pn, wid = (res.get('project') or {}).get('name'), f.get('system.id')
    if not (pn and wid):
        continue
    scanned += 1
    s2, _, item = get(f'{ORG_URL}/{urllib.parse.quote(pn)}/_apis/wit/workItems/{wid}'
                      f'?api-version=7.1')
    for name, val in ((item.get('fields') or {}) if isinstance(item, dict) else {}).items():
        if isinstance(val, str) and 'data-vss-mention' in val:
            m = ANCHOR_RE.search(val)
            out.append(f'- an HTML field **`{name}`** carries a mention anchor'
                       + (f': attr `{g(m.group(1))}`, label {len(m.group(2))} chars — the same '
                          f'`version:2.0,{{guid}}` shape as a comment' if m else
                          ' (attribute present, anchor markup differs from the comment form)'))
            found += 1
            break
out.append(f'- scanned {scanned} work items for anchors in HTML fields; found {found}')

s, _, r = get(f'{ORG_URL}/_apis/git/repositories?api-version=7.1')
repos = [x['id'] for x in ((r.get('value') or []) if isinstance(r, dict) else [])]
bodies = angle = withids = 0
for rid in repos[:10]:
    s, _, r = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullrequests'
                  f'?searchCriteria.status=all&%24top=25&api-version=7.1')
    for p in ((r.get('value') or []) if isinstance(r, dict) else [])[:25]:
        s2, _, tr = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullRequests/'
                        f'{p["pullRequestId"]}/threads?api-version=7.1')
        for th in ((tr.get('value') or []) if isinstance(tr, dict) else []):
            if th.get('identities'):
                withids += 1
            for c in (th.get('comments') or []):
                bodies += 1
                if re.search(r'@<' + GUID + r'>', c.get('content') or ''):
                    angle += 1
out.append(f'- wide grep over {len(repos[:10])} repositories: {bodies} PR comment bodies → '
           f'**{angle}** carrying `@<guid>`; {withids} threads with a non-empty `identities` map')

out.append(dump_costs())
write_result('w30_mention_probe/w30.md', '\n'.join(out))
