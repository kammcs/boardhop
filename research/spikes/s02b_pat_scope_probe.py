"""Spike 2b: why did profiles/me return 401 with a PAT? Distinguish "API is Entra-only" from
"this PAT lacks the scope", and map which service areas this PAT can reach.
"""
from lib import *

out = ['# Spike 2b — PAT scope probe', f'Org: {ORG_URL}', '']

# 1. The 401 itself: what challenge headers come back?
s, h, b = get('https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1', raw=True)
out += ['## profiles/me 401 headers', f'HTTP {s}', '```',
        '\n'.join(f'{k}: {v}' for k, v in h.items() if k.lower() in ('www-authenticate', 'x-tfs-fedauthrealm', 'x-vss-e2eid', 'content-type', 'location')), '```', '']

# 2. Alternative hosts for the same identity data
for label, url in [
    ('vssps.dev.azure.com/{org}/_apis/profile/profiles/me', f'https://vssps.dev.azure.com/{ORG}/_apis/profile/profiles/me?api-version=7.1'),
    ('app.vssps accounts by ownerId (no memberId)', f'https://app.vssps.visualstudio.com/_apis/accounts?api-version=7.1'),
    ('vssps.dev.azure.com/{org}/_apis/graph/users?$top=1 (Graph, vso.graph)', f'https://vssps.dev.azure.com/{ORG}/_apis/graph/users?api-version=7.1-preview.1'),
    ('{org}/_apis/identities?ids=me (IMS)', f'{ORG_URL}/_apis/identities?searchFilter=General&filterValue=kelly&api-version=7.1'),
    ('vsaex member entitlement for me', f'https://vsaex.dev.azure.com/{ORG}/_apis/userentitlements?top=1&api-version=7.1-preview.3'),
]:
    s, h, b = get(url, raw=True)
    out += [f'## {label}', f'HTTP {s} · {h.get("Content-Type")}', '```', short(b[:500] if isinstance(b, str) else b, 500), '```', '']

# 3. Service-area reachability with this PAT (401 = scope missing or blocked; 200/203/404 = reachable)
P = urllib.parse.quote(DEFAULT_PROJECT)
checks = [
    ('work', f'{ORG_URL}/{P}/_apis/wit/workitemtypes?api-version=7.1'),
    ('code (repos)', f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1'),
    ('build (definitions)', f'{ORG_URL}/{P}/_apis/build/definitions?$top=1&api-version=7.1'),
    ('pipelines', f'{ORG_URL}/{P}/_apis/pipelines?$top=1&api-version=7.1'),
    ('release (vsrm)', f'https://vsrm.dev.azure.com/{ORG}/{P}/_apis/release/definitions?$top=1&api-version=7.1'),
    ('wiki', f'{ORG_URL}/{P}/_apis/wiki/wikis?api-version=7.1'),
    ('search (almsearch work items)', f'https://almsearch.dev.azure.com/{ORG}/{P}/_apis/search/workitemsearchresults?api-version=7.1'),
    ('notification subscriptions', f'{ORG_URL}/_apis/notification/subscriptions?api-version=7.1'),
    ('service hooks subscriptions', f'{ORG_URL}/_apis/hooks/subscriptions?api-version=7.1'),
    ('extension data (extmgmt)', f'https://extmgmt.dev.azure.com/{ORG}/_apis/extensionmanagement/installedextensions?api-version=7.1-preview.1'),
    ('favorites', f'{ORG_URL}/_apis/favorite/favorites?artifactType=Microsoft.TeamFoundation.Git.Repository&artifactScopeType=Project&api-version=7.1-preview.1'),
    ('my work recent activity', f'{ORG_URL}/_apis/work/accountmyworkrecentactivity?api-version=7.1'),
    ('teams $mine (7.1-preview.3)', f'{ORG_URL}/_apis/teams?$mine=true&api-version=7.1-preview.3'),
]
out += ['## Service-area reachability with this PAT', '| area | HTTP | note |', '|---|---|---|']
for label, url in checks:
    method = 'POST' if 'searchresults' in url else 'GET'
    s, h, b = call(method, url, body={'searchText': 'a', '$top': 1} if method == 'POST' else None, raw=True)
    note = ''
    if isinstance(b, str) and b.startswith('{'):
        try:
            j = json.loads(b); note = (j.get('message') or f'count={j.get("count")}')[:90]
        except Exception: pass
    out.append(f'| {label} | {s} | {redact(note)} |')
out.append(dump_costs())
write_result('s02b_pat_scope_probe.md', '\n'.join(out))
