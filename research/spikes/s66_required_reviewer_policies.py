"""s66 (read-only): where a *Required reviewers* branch policy actually exists.

P-D needs one real pull request whose target branch carries the
`fd2167ab-b0be-447a-8ec8-39368250530e` (Required reviewers) policy, to close
NEXT-STEPS item 8's open note that the resolved required-reviewer names in the
merge box have never been seen against the live service. The scratch branch
`scratch/policy-target` carries only minimum-reviewers (192) and
merge-strategy (193), so this looks across every project in the organization.

GETs only. No project is written to and no pull request is opened here.

    python _run_with_mcp_creds.py s66_required_reviewer_policies.py
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402

# The two are easy to confuse: `fa4e907d-…d171dd` is *Minimum number of
# reviewers* (a count, no names), and this one is *Required reviewers* (the
# one that carries `requiredReviewerIds`, which the merge box resolves).
REQUIRED_REVIEWERS = 'fd2167ab-b0be-447a-8ec8-39368250530e'
OUT = ['# Spike s66 — Required reviewers policies in the organization', '']


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


s, h, projects = get(f'{ORG_URL}/_apis/projects?api-version=7.1')
names = [x['name'] for x in projects['value']]
p(f'- {len(names)} projects')

found = []
for name in names:
    q = urllib.parse.quote(name)
    s, h, cfgs = get(
        f'{ORG_URL}/{q}/_apis/policy/configurations'
        f'?policyType={REQUIRED_REVIEWERS}&api-version=7.1'
    )
    if s >= 300:
        p(f'- `{name}`: policy read → {s} {short(cfgs, 200)}')
        continue
    rows = [c for c in cfgs.get('value', []) if c.get('isEnabled')]
    p(f'- `{name}`: {len(rows)} enabled Required-reviewers configurations')
    for c in rows:
        scopes = [
            f'{sc.get("refName")} ({sc.get("matchKind")})'
            for sc in (c.get('settings') or {}).get('scope', [])
        ]
        found.append((name, c['id'], scopes, (c.get('settings') or {}).get('scope', [{}])[0].get('repositoryId')))
        p(
            f'  - id {c["id"]} blocking={c.get("isBlocking")} '
            f'reviewers={len((c.get("settings") or {}).get("requiredReviewerIds", []))} '
            f'scope={scopes}'
        )

p('')
p(f'**{len(found)} enabled Required-reviewers policies in the organization.**')
if not found:
    p(
        'Nothing anywhere carries one, so the resolved-names block in the merge '
        'box cannot be shown on a real pull request without creating a policy; '
        'on the scratch branch that would be a new write, and on a client '
        'project it is out of bounds.'
    )

# ----------------------------------------------------------- candidate PRs
# An active pull request whose target is one of those branches is what P-D
# needs to open (read-only) to see the resolved names in the merge box.
p('')
p('## Active pull requests targeting one of those branches')
for name, cid, scopes, repo_id in found:
    q = urllib.parse.quote(name)
    for ref in scopes:
        branch = ref.split(' ')[0]
        s, h, prs = get(
            f'{ORG_URL}/{q}/_apis/git/repositories/{repo_id}/pullrequests'
            f'?searchCriteria.status=active'
            f'&searchCriteria.targetRefName={urllib.parse.quote(branch)}'
            f'&api-version=7.1'
        )
        if s >= 300:
            continue
        for pr in prs.get('value', []):
            p(
                f'- `{name}` policy {cid} → PR !{pr["pullRequestId"]} '
                f'target {branch}'
            )

dump_costs()
write_result('s66_required_reviewer_policies', '\n'.join(OUT))
