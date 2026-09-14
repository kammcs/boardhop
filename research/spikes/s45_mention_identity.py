"""s45: read-only. Everything about person mentions that can be learned without
writing: which GUID the wire format carries, what the web UI actually stores in
existing comments, and which identity endpoint a mention picker should call.

No names, emails or client content reach the result file: every display name and
address is masked, GUIDs are masked to their first 8 characters unless they are
the PAT's own identity, and comment bodies are reported only as counts and the
shape of the mention markup around them."""
import json, os, re, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, DEFAULT_PROJECT, get, post, dump_costs, write_result, short  # noqa: E402

VSSPS = f'https://vssps.dev.azure.com/{ORG}'
SCRATCH = 'DevOps Mobile App'
out = ['# Spike s45 — mention wire format and identity lookup (read-only)', '']
ME = {'id': None, 'descriptor': None, 'subject': None, 'name': None, 'mail': None}

GUID = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'


def g(v):
    """Mask a GUID: keep the prefix, or say <me> when it is the PAT's identity."""
    if not isinstance(v, str):
        return v
    if ME['id'] and v.lower() == ME['id'].lower():
        return '<me>'
    return re.sub(GUID, lambda m: m.group(0)[:8] + '-…', v)


def mask(v):
    """Mask a display name / mail so no client identity reaches the file."""
    if not isinstance(v, str) or not v:
        return v
    if ME['name'] and v == ME['name']:
        return '<me:name>'
    if ME['mail'] and ME['mail'].lower() in v.lower():
        return '<me:mail>'
    return f'<person:{len(v)}c>'


def sec(t):
    out.append('')
    out.append(f'## {t}')
    out.append('')


# ------------------------------------------------------------------ 0. me
sec('0. Who the PAT is')
s, _, r = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
au = (r or {}).get('authenticatedUser') if isinstance(r, dict) else None
if isinstance(au, dict):
    ME['id'] = au.get('id')
    ME['descriptor'] = au.get('descriptor')
    ME['subject'] = au.get('subjectDescriptor')
    ME['name'] = au.get('providerDisplayName') or au.get('customDisplayName')
    props = au.get('properties') or {}
    acct = props.get('Account')
    ME['mail'] = acct.get('$value') if isinstance(acct, dict) else None
out.append(f'- `GET _apis/connectionData` HTTP {s}: authenticatedUser keys '
           f'{sorted(au.keys()) if isinstance(au, dict) else r}')
out.append(f'- id present: {bool(ME["id"])}; descriptor form: '
           f'`{(ME["descriptor"] or "").split(".")[0]}.…`; subjectDescriptor form: '
           f'`{(ME["subject"] or "").split(".")[0]}.…`')

s, _, r = get(f'{VSSPS}/_apis/profile/profiles/me?api-version=7.1')
prof_id = r.get('id') if isinstance(r, dict) else None
out.append(f'- `GET vssps/{{org}}/_apis/profile/profiles/me` HTTP {s}: keys '
           f'{sorted(r.keys()) if isinstance(r, dict) else r}')
out.append(f'- profile `id` == connectionData `authenticatedUser.id`? **'
           f'{str(bool(prof_id and ME["id"] and prof_id.lower() == ME["id"].lower())).lower()}**')

# storage key / graph descriptor round trip for my own identity
if ME['subject']:
    s, _, r = get(f'{VSSPS}/_apis/graph/storagekeys/{ME["subject"]}?api-version=7.1-preview.1')
    sk = r.get('value') if isinstance(r, dict) else None
    out.append(f'- `graph/storagekeys/{{subjectDescriptor}}` HTTP {s} → value == my identity id? **'
               f'{str(bool(sk and ME["id"] and sk.lower() == ME["id"].lower())).lower()}**')
    s, _, r = get(f'{VSSPS}/_apis/graph/users/{ME["subject"]}?api-version=7.1-preview.1')
    out.append(f'- `graph/users/{{subjectDescriptor}}` HTTP {s}: keys '
               f'{sorted(r.keys()) if isinstance(r, dict) else short(r, 200)}')
    if isinstance(r, dict):
        out.append(f'  - `originId` == identity id? **'
                   f'{str(bool(r.get("originId") and ME["id"] and str(r["originId"]).lower() == ME["id"].lower())).lower()}**'
                   f' (originId is the Entra object id, a different GUID from the ADO identity id)')

# ------------------------------------------------- 1. existing web mentions
sec('1. What the web UI stores — existing mentions read back (client projects, read-only)')

HTML_MENTION = re.compile(r'<a[^>]*data-vss-mention="([^"]*)"[^>]*>(@[^<]*)</a>')
ANGLE_MENTION = re.compile(r'@<(' + GUID + r')>')


def report_mentions(label, texts):
    html_hits, angle_hits, samples = 0, 0, []
    for t in texts:
        if not isinstance(t, str):
            continue
        for m in HTML_MENTION.finditer(t):
            html_hits += 1
            if len(samples) < 4:
                samples.append(('html', m.group(1), len(m.group(2))))
        for m in ANGLE_MENTION.finditer(t):
            angle_hits += 1
            if len(samples) < 8:
                samples.append(('angle', m.group(1), 0))
    out.append(f'- {label}: scanned {len(texts)} bodies → '
               f'**{html_hits}** `data-vss-mention` anchors, **{angle_hits}** `@<guid>` tokens')
    for kind, val, n in samples:
        if kind == 'html':
            out.append(f'  - anchor attr `{g(val)}` around a {n}-char `@…` label')
        else:
            out.append(f'  - `@<{g(val)}>`')
    return html_hits, angle_hits


# PR threads in a client project (read-only). s22 found a chatty PR there.
s, _, r = get(f'{ORG_URL}/_apis/git/repositories?api-version=7.1')
repos = [(x['id'], x['project']['name']) for x in (r.get('value') or [])] if isinstance(r, dict) else []
out.append(f'- repositories visible: {len(repos)}')
pr_bodies, pr_scanned = [], 0
for rid, pname in repos:
    if pr_scanned >= 6:
        break
    q = urllib.parse.urlencode({'searchCriteria.status': 'all', '$top': 12})
    s, _, r = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullrequests?{q}&api-version=7.1')
    prs = (r.get('value') or []) if isinstance(r, dict) else []
    for pr in prs:
        if pr_scanned >= 6:
            break
        s2, _, tr = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullRequests/{pr["pullRequestId"]}'
                        f'/threads?api-version=7.1')
        threads = (tr.get('value') or []) if isinstance(tr, dict) else []
        if len(threads) < 5:
            continue
        pr_scanned += 1
        for t in threads:
            for c in (t.get('comments') or []):
                pr_bodies.append(c.get('content'))
        # also record the description of the PR itself
        pr_bodies.append(pr.get('description'))
out.append(f'- pull requests with ≥5 threads scanned: {pr_scanned}')
report_mentions('PR comment `content` + PR `description`', pr_bodies)
out.append('- PR comments: does any comment carry a rendered form? comment keys seen: '
           + str(sorted({k for b in [] for k in b})) )

# one thread read in full, to list the comment keys
if repos:
    rid, _ = repos[0]
    s, _, r = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullrequests?'
                  f'{urllib.parse.urlencode({"searchCriteria.status": "all", "$top": 5})}&api-version=7.1')
    prs = (r.get('value') or []) if isinstance(r, dict) else []
    for pr in prs:
        s2, _, tr = get(f'{ORG_URL}/_apis/git/repositories/{rid}/pullRequests/{pr["pullRequestId"]}'
                        f'/threads?api-version=7.1')
        ts = (tr.get('value') or []) if isinstance(tr, dict) else []
        if ts and ts[0].get('comments'):
            c = ts[0]['comments'][0]
            out.append(f'- a PR comment object has keys {sorted(c.keys())} — '
                       f'`renderedText` present? **{"renderedText" in c}**')
            out.append(f'- the thread object has keys {sorted(ts[0].keys())}')
            break

# Work item comments and History in a client project: HTML mentions.
wi_bodies = []
s, _, r = post(f'https://almsearch.dev.azure.com/{ORG}/_apis/search/workitemsearchresults?api-version=7.1',
               {'searchText': 'mention', '$top': 25, '$skip': 0})
ids = []
if isinstance(r, dict):
    for res in (r.get('results') or []):
        f = res.get('fields') or {}
        pid = f.get('system.id')
        pn = (res.get('project') or {}).get('name')
        if pid:
            ids.append((pn, int(pid)))
out.append(f'- work items found by a text search: {len(ids)}')
for pn, wid in ids[:12]:
    s, _, c = get(f'{ORG_URL}/{urllib.parse.quote(pn)}/_apis/wit/workItems/{wid}/comments'
                  f'?api-version=7.1-preview.4&$expand=renderedText&$top=50')
    for cm in ((c.get('comments') or []) if isinstance(c, dict) else []):
        wi_bodies.append(cm.get('text'))
        wi_bodies.append(cm.get('renderedText'))
report_mentions('work item comment `text` + `renderedText`', wi_bodies)

# ------------------------------------------------------ 2. identity lookup
sec('2. Identity lookup endpoints for a mention picker')

QUERY = (ME['name'] or 'a').split(' ')[0][:4] or 'a'
out.append(f'- probe term: the first {len(QUERY)} characters of the PAT user\'s own first name')


def idp(label, method, url, body=None):
    s, _, r = (post(url, body) if method == 'POST' else get(url))
    out.append(f'### {label} — HTTP {s}')
    out.append('')
    if not isinstance(r, dict):
        out.append('```\n' + short(r, 400) + '\n```')
        out.append('')
        return None
    return r


r = idp('A. `POST {org}/_apis/IdentityPicker/Identities` (undocumented, the web\'s picker)',
        'POST', f'{ORG_URL}/_apis/IdentityPicker/Identities?api-version=7.1-preview.1',
        {'query': QUERY, 'identityTypes': ['user'], 'operationScopes': ['ims', 'source'],
         'options': {'MinResults': 5, 'MaxResults': 20},
         'properties': ['DisplayName', 'IsMru', 'ScopeName', 'SamAccountName', 'Active',
                        'SubjectDescriptor', 'Mail', 'SignInAddress', 'Surname', 'Guest']})
if r:
    results = r.get('results') or []
    out.append(f'- top-level keys {sorted(r.keys())}; results {len(results)}')
    for res in results[:2]:
        ents = res.get('identities') or []
        out.append(f'- queryToken `{mask(res.get("queryToken"))}`, identities {len(ents)}, '
                   f'result keys {sorted(res.keys())}')
        if ents:
            e = ents[0]
            out.append(f'- identity keys: {sorted(e.keys())}')
            out.append('- first row, masked: ' + json.dumps({
                k: (g(v) if isinstance(v, str) and re.search(GUID, v) else
                    mask(v) if k in ('displayName', 'mail', 'signInAddress', 'samAccountName',
                                     'scopeName', 'surname', 'entityId') else v)
                for k, v in e.items() if not isinstance(v, (dict, list))}, sort_keys=True))
            out.append(f'- `localId` == my identity id? **'
                       f'{str(bool(e.get("localId") and ME["id"] and str(e["localId"]).lower() == ME["id"].lower())).lower()}**'
                       f'; `originId` == my identity id? **'
                       f'{str(bool(e.get("originId") and ME["id"] and str(e["originId"]).lower() == ME["id"].lower())).lower()}**')
    out.append('')

# A2: same picker with the project's scope, as the web does inside a project
s, _, d = get(f'{VSSPS}/_apis/graph/descriptors/'
              f'{urllib.parse.quote(DEFAULT_PROJECT)}?api-version=7.1-preview.1')
out.append(f'- (`graph/descriptors/{{project *name*}}` HTTP {s} — s30 recorded that the name is a 400)')
out.append('')

r = idp('B. `GET vssps/{org}/_apis/identities?searchFilter=General`',
        'GET', f'{VSSPS}/_apis/identities?searchFilter=General&filterValue={urllib.parse.quote(QUERY)}'
               f'&queryMembership=None&api-version=7.1')
if r:
    vals = r.get('value') or []
    out.append(f'- count {r.get("count")}, rows {len(vals)}')
    if vals:
        e = vals[0]
        out.append(f'- row keys: {sorted(e.keys())}')
        out.append(f'- `id` is the identity GUID; `providerDisplayName` masked '
                   f'{mask(e.get("providerDisplayName"))}; descriptor form '
                   f'`{str(e.get("descriptor") or "").split(".")[0]}.…`')
        out.append(f'- row `id` == my identity id? **'
                   f'{str(any(str(v.get("id", "")).lower() == (ME["id"] or "").lower() for v in vals)).lower()}**')
    out.append('')

r = idp('C. `GET vssps/{org}/_apis/identities?searchFilter=MailAddress`',
        'GET', f'{VSSPS}/_apis/identities?searchFilter=MailAddress'
               f'&filterValue={urllib.parse.quote(ME["mail"] or "")}&api-version=7.1')
if r:
    out.append(f'- count {r.get("count")} (an exact-address lookup, not a prefix search)')
    out.append('')

r = idp('D. `POST vssps/{org}/_apis/graph/subjectquery` (what the app uses today)',
        'POST', f'{VSSPS}/_apis/graph/subjectquery?api-version=7.1-preview.1',
        {'query': QUERY, 'subjectKind': ['User']})
if r:
    vals = r.get('value') or []
    out.append(f'- count {r.get("count")}, rows {len(vals)}')
    if vals:
        out.append(f'- row keys: {sorted(vals[0].keys())} — note **no identity id**, only '
                   f'`descriptor` / `originId`, so a second call is needed')
    out.append('')

r = idp('E. `GET vssps/{org}/_apis/graph/users` (full list, paged)',
        'GET', f'{VSSPS}/_apis/graph/users?api-version=7.1-preview.1')
if r:
    out.append(f'- count {r.get("count")} rows in the first page; no server-side prefix filter '
               f'parameter is documented, the caller filters')
    out.append('')

# F: scratch team members, what the app already caches
s, _, p = get(f'{ORG_URL}/_apis/projects/{urllib.parse.quote(SCRATCH)}?api-version=7.1')
pid = p.get('id') if isinstance(p, dict) else None
s, _, t = get(f'{ORG_URL}/_apis/projects/{pid}/teams?api-version=7.1')
teams = (t.get('value') or []) if isinstance(t, dict) else []
if teams:
    s, _, m = get(f'{ORG_URL}/_apis/projects/{pid}/teams/{teams[0]["id"]}/members?api-version=7.1')
    rows = (m.get('value') or []) if isinstance(m, dict) else []
    out.append(f'### F. `projects/{{id}}/teams/{{id}}/members` (the app\'s offline list) — HTTP {s}')
    out.append('')
    out.append(f'- {len(rows)} members; identity keys {sorted((rows[0].get("identity") or {}).keys()) if rows else []}')
    ids_ok = [x for x in rows if (x.get('identity') or {}).get('id')]
    out.append(f'- rows carrying an `id`: {len(ids_ok)}/{len(rows)} — **this id is the identity GUID** '
               f'(s29 proved it is *not* accepted as an AssignedTo value, but it is the mention GUID candidate)')
    out.append(f'- my own row present with id == connectionData id? **'
               f'{str(any(str((x.get("identity") or {}).get("id", "")).lower() == (ME["id"] or "").lower() for x in rows)).lower()}**')
    out.append('')

# ------------------------------------------------------- 3. notifications
sec('3. Notification settings, read-only')
for label, url in [
    ('subscriptions (mine)', f'{ORG_URL}/_apis/notification/subscriptions?api-version=7.1-preview.1'),
    ('subscribers/me', f'{ORG_URL}/_apis/notification/subscribers/{ME["id"]}?api-version=7.1-preview.1'),
    ('eventtypes', f'{ORG_URL}/_apis/notification/eventtypes?api-version=7.1-preview.1'),
]:
    s, _, r = get(url)
    if isinstance(r, dict) and 'value' in r:
        names = []
        for v in (r.get('value') or []):
            n = v.get('description') or v.get('name') or v.get('id')
            if isinstance(n, str) and ('ment' in n.lower() or 'comment' in n.lower()):
                names.append(n[:80])
        out.append(f'- `{label}` HTTP {s}: {r.get("count")} rows; '
                   f'mention/comment-ish: {names[:8]}')
    else:
        out.append(f'- `{label}` HTTP {s}: {short(r, 200)}')

out.append(dump_costs())
write_result('s45_mention_identity/s45.md', '\n'.join(out))
