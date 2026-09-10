"""Spike 6 (search half): look through recent PR threads for suggested-change comments to learn
the wire format, and capture one file-anchored thread as a reference for anchoring shape.
"""
from lib import *

P = urllib.parse.quote(DEFAULT_PROJECT)
out = ['# Spike 6 — Suggested-change wire format (search existing threads)', f'Org: {ORG_URL} · Project: {DEFAULT_PROJECT}', '']

s, h, prs = get(f'{ORG_URL}/{P}/_apis/git/pullrequests?searchCriteria.status=all&$top=40&api-version=7.1')
prlist = prs.get('value', []) if isinstance(prs, dict) else []
found, scanned, anchored_ref = [], 0, None
file_anchored = 0
for p in prlist:
    rid, pid = p['repository']['id'], p['pullRequestId']
    s, h, th = get(f'{ORG_URL}/{P}/_apis/git/repositories/{rid}/pullRequests/{pid}/threads?api-version=7.1')
    for t in th.get('value', []) if isinstance(th, dict) else []:
        scanned += 1
        if t.get('threadContext'):
            file_anchored += 1
            anchored_ref = anchored_ref or t
        for c in t.get('comments', []):
            content = c.get('content') or ''
            if '```suggestion' in content or ('suggestion' in content.lower() and '```' in content):
                found.append((pid, t['id'], json.dumps(t.get('threadContext')), json.dumps(t.get('pullRequestThreadContext')), content[:400]))
    if len(found) >= 3:
        break

out += [f'PRs scanned: {len(prlist)}, threads scanned: {scanned}, file-anchored threads: {file_anchored}, suggestion-looking comments: {len(found)}', '']
for pid, tid, tc, ptc, content in found:
    out += [f'## PR {pid} thread {tid}', f'threadContext: `{tc}`', f'pullRequestThreadContext: `{ptc}`', '```', content, '```', '']
if not found:
    out.append('No suggestion-style comments found in recent threads. The write half (create a suggestion in the web UI on a scratch PR, then read the thread back) is still required.')
if anchored_ref:
    t = anchored_ref
    out += ['', '## Reference: one file-anchored thread (shape of threadContext / pullRequestThreadContext)', '```json',
            short({k: t.get(k) for k in ['id', 'status', 'threadContext', 'pullRequestThreadContext']}, 1500), '```']
out.append(dump_costs())
write_result('s06_suggestion_wire_format.md', '\n'.join(out))
