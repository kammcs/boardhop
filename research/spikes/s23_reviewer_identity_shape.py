"""s23: why do reviewer and approver avatars fall back to initials? Read-
only: dumps the identity fields on a pull request's reviewers, its thread
comment authors (which do render a photo) and a pipeline approval, so the
difference can be seen."""
import json, os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get  # noqa: E402

PROJECT = 'CloudCover 2.0'
P = urllib.parse.quote(PROJECT)
PRID = 8261


def dump(label, ident):
    if not isinstance(ident, dict):
        print(f'  {label}: {ident!r}')
        return
    links = (ident.get('_links') or {}).get('avatar') or {}
    print(f"  {label}: {ident.get('displayName')}")
    print(f"     keys        : {sorted(ident.keys())}")
    print(f"     descriptor  : {ident.get('descriptor')}")
    print(f"     imageUrl    : {ident.get('imageUrl')}")
    print(f"     _links.avatar: {links.get('href')}")


s, h, pr = get(f'{ORG_URL}/{P}/_apis/git/pullrequests/{PRID}?api-version=7.1')
print(f"PR !{PRID} {pr.get('title')}")
dump('createdBy', pr.get('createdBy'))
for r in (pr.get('reviewers') or [])[:3]:
    dump('reviewer', r)

RID = pr['repository']['id']
s, h, threads = get(f'{ORG_URL}/{P}/_apis/git/repositories/{RID}/pullRequests/{PRID}/threads?api-version=7.1')
for t in threads.get('value', []):
    for c in (t.get('comments') or []):
        if c.get('commentType') != 'system' and c.get('author'):
            dump('comment author', c['author'])
            break
    else:
        continue
    break

print('\npipeline approval identities (scratch project):')
s, h, appr = get(f'{ORG_URL}/DevOps%20Mobile%20App/_apis/pipelines/approvals?state=pending&$expand=steps&api-version=7.1-preview.1')
for a in (appr.get('value') or [])[:1]:
    for step in (a.get('steps') or []):
        dump('approver', step.get('assignedApprover') or step.get('actualApprover'))
    for approver in (a.get('approvers') or []):
        dump('approvers[]', approver)
