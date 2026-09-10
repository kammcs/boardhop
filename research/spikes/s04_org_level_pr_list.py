"""Spike 4: is there an org-level pull request list endpoint (undocumented)?

If it works, the "PRs awaiting my review" inbox drops from one call per project to one call.
"""
from lib import *

P = urllib.parse.quote(DEFAULT_PROJECT)
out = ['# Spike 4 — Org-level PR list', f'Org: {ORG_URL}', '']

for label, url in [
    ('org-level (undocumented)', f'{ORG_URL}/_apis/git/pullrequests?searchCriteria.status=all&$top=5&api-version=7.1'),
    ('project-level (documented)', f'{ORG_URL}/{P}/_apis/git/pullrequests?searchCriteria.status=all&$top=5&api-version=7.1'),
]:
    s, h, b = get(url)
    out += [f'## {label}', f'`{url.replace(ORG_URL, "{org}")}`', f'HTTP {s}']
    if isinstance(b, dict) and 'value' in b:
        out.append(f'count: {b.get("count")}')
        for p in b['value']:
            out.append(f'- PR {p["pullRequestId"]} · {p["repository"]["project"]["name"]} / {p["repository"]["name"]} · {p["status"]} · {p["title"][:60]}')
    else:
        out += ['```', short(b, 600), '```']
    out.append('')

s, h, cd = get(f'{ORG_URL}/_apis/connectionData')
me = cd['authenticatedUser']['id'] if isinstance(cd, dict) else None
if me:
    url = f'{ORG_URL}/_apis/git/pullrequests?searchCriteria.reviewerId={me}&searchCriteria.status=active&$top=5&api-version=7.1'
    s, h, b = get(url)
    out += ['## org-level filtered by reviewerId=me', f'HTTP {s}',
            f'count: {b.get("count") if isinstance(b, dict) else "n/a"}', '']
out.append(dump_costs())
write_result('s04_org_level_pr_list.md', '\n'.join(out))
