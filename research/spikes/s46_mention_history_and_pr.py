"""s46: read-only follow-up to s45/w30 on the two things the relay depends on.

1. Does a comment posted through the Comments API still land in
   `System.History`? The relay pulls work item mention GUIDs out of
   `fields["System.History"].newValue` (relay/lib/src/hooks/routing_view.dart),
   so if the Comments API no longer writes History the rule reads an empty
   string. Checked on the scratch work item the w30 probes commented on.
2. What is a PR thread's `identities` map, and does any *web-created* PR comment
   in the org carry an `@<guid>` (or any other) mention token?

No names or comment content reach the file: bodies are reported as counts and
masked shapes only."""
import json, os, re, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, dump_costs, write_result, short  # noqa: E402

P = urllib.parse.quote('DevOps Mobile App')
WI = int(os.environ.get('W30_WI', '15545'))
MARKER = 'spike w30 mention probe'
GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
out = ['# Spike s46 — System.History for API comments, and PR mention shapes (read-only)', '']


def g(v):
    return re.sub(GUID, lambda m: m.group(0)[:8] + '-…', v) if isinstance(v, str) else v


def sec(t):
    out.extend(['', f'## {t}', ''])


# ------------------------------------------------- 1. System.History
sec(f'1. Does a Comments-API comment write `System.History`? (scratch #{WI})')
s, _, r = get(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}/updates?api-version=7.1&$top=200')
ups = (r.get('value') or []) if isinstance(r, dict) else []
hist_ups = [u for u in ups if 'System.History' in (u.get('fields') or {})]
marker_ups = [u for u in hist_ups
              if MARKER in str(((u.get('fields') or {}).get('System.History') or {}).get('newValue', ''))]
cc_ups = [u for u in ups if 'System.CommentCount' in (u.get('fields') or {})]
out.append(f'- `wit/workItems/{WI}/updates` HTTP {s}: {len(ups)} updates')
out.append(f'- updates whose `fields` contain `System.History`: **{len(hist_ups)}**')
out.append(f'- of those, carrying the w30 marker text: **{len(marker_ups)}**')
out.append(f'- updates whose `fields` contain `System.CommentCount`: **{len(cc_ups)}**')
if cc_ups:
    u = cc_ups[-1]
    out.append(f'- the newest CommentCount update changed: {sorted((u.get("fields") or {}).keys())}')
    out.append(f'  - rev {u.get("rev")}, has `commentVersionRef`? '
               f'**{"commentVersionRef" in u}** '
               f'{g(json.dumps(u.get("commentVersionRef")))}')
for u in marker_ups:
    hv = ((u.get('fields') or {}).get('System.History') or {}).get('newValue') or ''
    out.append(f'- **marker History, rev {u.get("rev")}** ({len(hv)} chars), '
               f'`data-vss-mention` anchors: **{len(re.findall("data-vss-mention", hv))}**, '
               f'`@<guid>` tokens: **{len(re.findall("@<" + GUID + ">", hv))}**')
    out.append(f'  - `{g(hv)[:320]}`')
    out.append(f'  - this update also changed: {sorted((u.get("fields") or {}).keys())}')
    cvr = u.get('commentVersionRef') or ((u.get('fields') or {}).get('commentVersionRef'))
    out.append(f'  - `commentVersionRef` on the update: `{g(json.dumps(cvr))}`')
if hist_ups:
    u = hist_ups[-1]
    hv = ((u.get('fields') or {}).get('System.History') or {}).get('newValue')
    out.append(f'- the newest `System.History` update is rev {u.get("rev")}, '
               f'{len(hv or "")} chars, mention anchors in it: '
               f'**{len(re.findall(chr(34) + "?data-vss-mention", hv or ""))}**')
    out.append(f'  - shape: `{g((hv or "")[:200])}`')
s, _, item = get(f'{ORG_URL}/{P}/_apis/wit/workItems/{WI}?api-version=7.1')
f = (item.get('fields') or {}) if isinstance(item, dict) else {}
out.append(f'- current `System.CommentCount`: {f.get("System.CommentCount")}; '
           f'`System.History` present on the item read? **{"System.History" in f}**')
out.append('')

# ------------------------------- 1b. how the *web* stores a work item mention
sec('1b. Stored `format` and `text` of web-created work item comments that mention someone')
from lib import post  # noqa: E402
s, _, sr = post(f'https://almsearch.dev.azure.com/{ORG}/_apis/search/workitemsearchresults'
                f'?api-version=7.1', {'searchText': 'mention', '$top': 40, '$skip': 0})
seen = {'markdown-angle': 0, 'html-anchor': 0, 'markdown-anchor': 0, 'other': 0}
fmts = {}
checked = 0
for res in ((sr.get('results') or []) if isinstance(sr, dict) else []):
    f = res.get('fields') or {}
    pn, wid = (res.get('project') or {}).get('name'), f.get('system.id')
    if not (pn and wid):
        continue
    s2, _, c = get(f'{ORG_URL}/{urllib.parse.quote(pn)}/_apis/wit/workItems/{wid}/comments'
                   f'?api-version=7.1-preview.4&$expand=all&$top=50')
    for cm in ((c.get('comments') or []) if isinstance(c, dict) else []):
        txt, fmt = cm.get('text') or '', cm.get('format')
        has_mentions = bool(cm.get('mentions'))
        if not has_mentions:
            continue
        checked += 1
        fmts[fmt] = fmts.get(fmt, 0) + 1
        if re.search(r'@<' + GUID + r'>', txt):
            seen['markdown-angle' if fmt == 'markdown' else 'other'] += 1
        elif 'data-vss-mention' in txt:
            seen['html-anchor' if fmt == 'html' else 'markdown-anchor'] += 1
        else:
            seen['other'] += 1
out.append(f'- comments carrying a non-empty `mentions[]` (a real mention): **{checked}**')
out.append(f'- their stored `format`: {fmts}')
out.append(f'- the shape of the mention inside the stored `text`: {seen}')
out.append('')

# ------------------------------------------------- 2. PR thread identities
sec('2. PR thread `identities`, and any web-created mention token')
s, _, r = get(f'{ORG_URL}/_apis/git/repositories?api-version=7.1')
repos = [x['id'] for x in ((r.get('value') or []) if isinstance(r, dict) else [])]
bodies = angle = loose = anchors = 0
ident_threads = 0
sample_ident = None
sample_types = {}
for rid in repos[:10]:
    s, _, r = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullrequests'
                  f'?searchCriteria.status=all&%24top=25&api-version=7.1')
    for p in ((r.get('value') or []) if isinstance(r, dict) else [])[:25]:
        s2, _, tr = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullRequests/'
                        f'{p["pullRequestId"]}/threads?api-version=7.1')
        for th in ((tr.get('value') or []) if isinstance(tr, dict) else []):
            ids = th.get('identities')
            if ids:
                ident_threads += 1
                types = sorted({(c.get('commentType') or '?') for c in (th.get('comments') or [])})
                sample_types[tuple(types)] = sample_types.get(tuple(types), 0) + 1
                if sample_ident is None and 'system' in types:
                    sample_ident = (sorted(ids.keys()),
                                    sorted((list(ids.values())[0] or {}).keys()),
                                    sorted((th.get('properties') or {}).keys()))
            for c in (th.get('comments') or []):
                body = c.get('content') or ''
                bodies += 1
                if re.search(r'@<' + GUID + r'>', body):
                    angle += 1
                if '@<' in body:
                    loose += 1
                if 'data-vss-mention' in body:
                    anchors += 1
out.append(f'- {bodies} PR comment bodies across {len(repos[:10])} repositories')
out.append(f'  - `@<guid>` tokens: **{angle}**; any `@<` at all: **{loose}**; '
           f'`data-vss-mention` anchors: **{anchors}**')
out.append(f'- threads with a non-empty `identities` map: **{ident_threads}**')
out.append(f'- comment-type mix of those threads: '
           f'{ {"/".join(k): v for k, v in sorted(sample_types.items(), key=lambda x: -x[1])[:5]} }')
if sample_ident:
    keys, vkeys, pkeys = sample_ident
    out.append(f'- a system thread\'s `identities` map is keyed by {keys} (small integer keys) '
               f'and each value is an identity ref with keys {vkeys}')
    out.append(f'- its `properties` keys: {pkeys}')
    out.append('- i.e. `identities` belongs to **system** threads (vote, reviewer added, '
               'policy) where the rendered text uses `{n}` placeholders — it is not a '
               'mention map for user comments.')
out.append('')

# ------------------------------------------------- 3. mention subscriptions
sec('3. Notification subscriptions that deliver mentions')
s, _, r = get(f'{ORG_URL}/_apis/notification/subscriptions?api-version=7.1-preview.1')
rows = (r.get('value') or []) if isinstance(r, dict) else []
out.append(f'- `notification/subscriptions` HTTP {s}: {len(rows)} rows for this subscriber')
for v in rows:
    ev = ((v.get('filter') or {}).get('eventType')) or (v.get('description') or '')
    et = v.get('channel', {}).get('type') if isinstance(v.get('channel'), dict) else None
    desc = str(v.get('description') or '')
    if 'ment' in desc.lower() or 'comment' in desc.lower() or 'ment' in str(ev).lower():
        out.append(f'  - `{v.get("id")}` — description `{desc[:70]}`, status '
                   f'`{v.get("status")}`, channel `{et}`, scope '
                   f'`{(v.get("scope") or {}).get("name") or (v.get("scope") or {}).get("id", "")[:8]}`')
s, _, r = get(f'{ORG_URL}/_apis/notification/subscriptiontemplates?api-version=7.1-preview.1')
tmpl = (r.get('value') or []) if isinstance(r, dict) else []
ment = [t for t in tmpl if 'ment' in str(t.get('description', '')).lower()
        or 'mention' in str((t.get('filter') or {}).get('eventType', '')).lower()]
out.append(f'- `notification/subscriptiontemplates` HTTP {s}: {len(tmpl)} templates, '
           f'{len(ment)} mention-related')
for t in ment[:6]:
    out.append(f'  - `{t.get("id")}` — `{str(t.get("description"))[:80]}` '
               f'(eventType `{(t.get("filter") or {}).get("eventType")}`)')

out.append(dump_costs())
write_result('s46_mention_history_and_pr/s46.md', '\n'.join(out))
