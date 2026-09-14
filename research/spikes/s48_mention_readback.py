"""s48: read-only. The last comments on scratch work item #15545, as the
service stored them — `format`, the `mentions[]` the service attached, and
whether the text still carries the `@<guid>` the app posted.

Phase M-D's acceptance (research/16 §5 item 2) needs the proof that a comment
the *app* posted is a real mention, not a hand-typed `@Name`; this is the
read-back for every comment the walkthrough writes.

    python _run_with_mcp_creds.py s48_mention_readback.py
    S48_TOP=10 python _run_with_mcp_creds.py s48_mention_readback.py

No writes. Every GUID is masked; the signed-in identity reads `<me-guid>`.
"""
import os, re, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result  # noqa: E402

PROJECT = os.environ.get('S48_PROJECT', 'DevOps Mobile App')
P = urllib.parse.quote(PROJECT)
WI = int(os.environ.get('S48_WI', '15545'))
TOP = int(os.environ.get('S48_TOP', '5'))
REPO = os.environ.get('S48_REPO', 'DevOps Mobile App')
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
ME = {}


def mask(v):
    if not isinstance(v, str):
        return v
    return re.sub(GUID, lambda m: '<me-guid>' if ME.get('id', '').lower() == m.group(0).lower()
                  else m.group(0)[:8] + '-…', v)


out = [f'# Spike s48 — mention read-back on #{WI} (read-only)', '']

s, _, r = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
ME['id'] = (r.get('authenticatedUser') or {}).get('id', '') if isinstance(r, dict) else ''
out.append(f'- connectionData HTTP {s}; the signed-in identity is masked as `<me-guid>`.')

s, _, r = get(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}/comments'
              f'?api-version=7.1-preview.4&$expand=all&order=desc&$top={TOP}')
comments = (r.get('comments') or []) if isinstance(r, dict) else []
out += ['', f'HTTP {s}, {len(comments)} comments, newest first.', '',
        '| id | created | format | mentions[] | `@<guid>` in text? | text |',
        '|---|---|---|---|---|---|']
for c in comments:
    text = (c.get('text') or '').replace('|', r'\|').replace('\n', ' ')
    mentions = c.get('mentions') or []
    kinds = ', '.join(sorted({m.get('artifactType', '?') for m in mentions})) or '—'
    angle = 'yes' if re.search(r'@<' + GUID + '>', c.get('text') or '') else 'no'
    out.append(f'| {c.get("id")} | {(c.get("createdDate") or "")[:19]} '
               f'| {c.get("format")} | {len(mentions)} ({kinds}) | {angle} '
               f'| {mask(text)[:160]} |')

out += ['', '## The mention rows themselves', '']
for c in comments:
    for m in c.get('mentions') or []:
        out.append(f'- comment {c.get("id")}: artifactType `{m.get("artifactType")}`, '
                   f'targetId `{mask(m.get("targetId") or "")}`')
    if c.get('renderedText') and 'data-vss-mention' in (c.get('renderedText') or ''):
        for anchor in re.findall(r'<a[^>]*data-vss-mention="([^"]*)"[^>]*>([^<]*)</a>',
                                 c['renderedText']):
            out.append(f'- comment {c.get("id")}: renderedText anchor '
                       f'`{mask(anchor[0])}` → `{anchor[1]}`')

# ----------------------------------------------------- 2. pull request threads
PR = int(os.environ.get('S48_PR', '8334'))
out += ['', f'## Pull request !{PR} — the newest threads', '']
s, _, r = get(f'{ORG_URL}/{P}/_apis/git/repositories/{urllib.parse.quote(REPO)}'
              f'/pullRequests/{PR}/threads?api-version=7.1')
threads = (r.get('value') or []) if isinstance(r, dict) else []
out.append(f'HTTP {s}, {len(threads)} threads. A PR comment has no `mentions[]` and no '
           'rendered form: `@<guid>` is stored verbatim and the client resolves it.')
out += ['', '| thread | comment | published | file:line | `@<guid>`? | content |',
        '|---|---|---|---|---|---|']
for t in threads[-6:]:
    ctx = t.get('threadContext') or {}
    where = ctx.get('filePath') or 'conversation'
    line = (ctx.get('rightFileStart') or {}).get('line')
    for c in t.get('comments') or []:
        text = (c.get('content') or '').replace('|', r'\|').replace('\n', ' ')
        angle = 'yes' if re.search(r'@<' + GUID + '>', c.get('content') or '') else 'no'
        out.append(f'| {t.get("id")} | {c.get("id")} | {(c.get("publishedDate") or "")[:19]} '
                   f'| {where}{":" + str(line) if line else ""} | {angle} | {mask(text)[:120]} |')

out += ['', dump_costs()]
write_result('s48_mention_readback', '\n'.join(out) + '\n')
