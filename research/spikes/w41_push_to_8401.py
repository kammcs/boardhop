"""w41: one commit onto PR 8401's source branch, scratch project only.

P-D acceptance item 5 needs a *new iteration* on scratch PR 8401 so the viewed
marks (R8: keyed by path with the iteration seen) can be watched clearing for
the file the commit touched. This pushes a single edit to the PR's own source
branch — one line appended to a file that is already part of the PR's changes,
so the file keeps its place in the file list and only its iteration moves — and
reads the iteration list back before and after.

Nothing else is written: no vote, no thread, no completion, no policy. The PR
stays active, the target stays `scratch/policy-target`, and the source branch
gains exactly one commit.

    python _run_with_mcp_creds.py w41_push_to_8401.py
"""
import json, os, re, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from scratch import *  # noqa: E402,F403
from lib import ORG_URL, get, post, dump_costs, write_result, short  # noqa: E402

PR_ID = 8401
TS = time.strftime('%Y%m%d-%H%M%S')
OUT = [f'# Spike w41 — one push onto PR {PR_ID} (scratch, {TS})', '']


def p(*a):
    line = ' '.join(str(x) if isinstance(x, str) else short(x, 900) for x in a)
    print(line)
    OUT.append(line)


def sec(t):
    OUT.extend(['', f'## {t}', ''])
    print(f'\n## {t}')


# ------------------------------------------------------------------ 0. the PR
sec('The pull request')
s, h, pr = get(f'{ORG_URL}/_apis/git/pullrequests/{PR_ID}?api-version=7.1')
assert s < 300, f'read of PR {PR_ID} failed: {short(pr, 400)}'
project = (pr.get('repository') or {}).get('project') or {}
assert project.get('name') == SCRATCH, (
    f'PR {PR_ID} is in "{project.get("name")}", not the scratch project — refusing to write'
)
REPO = pr['repository']['id']
R = f'{ORG_URL}/{P}/_apis/git/repositories/{REPO}'
SRC = pr['sourceRefName']
p(f'- PR {PR_ID} `{pr["title"]}` status={pr["status"]} draft={pr.get("isDraft")}')
p(f'- source `{SRC}` → target `{pr["targetRefName"]}`, repo {REPO}')

s, h, refs = get(f'{R}/refs?filter={urllib.parse.quote(SRC[len("refs/"):])}&api-version=7.1')
tip = next(r['objectId'] for r in refs['value'] if r['name'] == SRC)
p(f'- source tip {tip[:8]}')

sec('Iterations and changes before the push')
s, h, its = get(f'{R}/pullRequests/{PR_ID}/iterations?api-version=7.1')
before = [i['id'] for i in its['value']]
p(f'- iterations {before}')
s, h, ch = get(
    f'{R}/pullRequests/{PR_ID}/iterations/{before[-1]}/changes?api-version=7.1'
)
# The iteration changes route answers `changeEntries`, not `value`.
entries = ch.get('changeEntries') or ch.get('value') or []
paths = [
    c['item']['path']
    for c in entries
    if c.get('item', {}).get('path') and not c['item'].get('isFolder')
]
p(f'- iteration {before[-1]} touches {len(paths)} files: {paths}')

# The file to touch: prefer a plain text/source file already in the PR so the
# viewed mark being cleared is one the walkthrough has already ticked.
target = next((x for x in paths if x.endswith(('.ts', '.txt', '.md'))), paths[0])
p(f'- touching `{target}`')

# ------------------------------------------------------------------ 1. push
sec('The push')
s, h, text = get(
    f'{R}/items?path={urllib.parse.quote(target)}&versionDescriptor.version='
    f'{urllib.parse.quote(SRC[len("refs/heads/"):])}&versionDescriptor.versionType=branch'
    f'&api-version=7.1',
    headers={'Accept': 'text/plain'},
    raw=True,
)
assert s < 300, f'read of {target} failed: {short(text, 300)}'
content = text if text.endswith('\n') else text + '\n'
content += f'// w41 viewed-mark reset, {TS}\n'

s, h, r = post(
    f'{R}/pushes?api-version=7.1',
    {
        'refUpdates': [{'name': SRC, 'oldObjectId': tip}],
        'commits': [
            {
                'comment': f'spike w41: one line onto {target} to move the iteration ({TS})',
                'changes': [
                    {
                        'changeType': 'edit',
                        'item': {'path': target},
                        'newContent': {'content': content, 'contentType': 'rawtext'},
                    }
                ],
            }
        ],
    },
)
sha = r['commits'][0]['commitId'] if s < 300 else None
p(f'- push → {s} {sha[:8] if sha else short(r, 400)}')
assert sha, 'push failed'

# ------------------------------------------------------------------ 2. read back
sec('Iterations after the push')
# The service builds the new iteration asynchronously; poll briefly.
after = before
for attempt in range(10):
    time.sleep(2)
    s, h, its = get(f'{R}/pullRequests/{PR_ID}/iterations?api-version=7.1')
    after = [i['id'] for i in its['value']]
    if after != before:
        break
p(f'- iterations {after} (was {before}) after {attempt + 1} polls')
if after != before:
    s, h, ch2 = get(
        f'{R}/pullRequests/{PR_ID}/iterations/{after[-1]}/changes?api-version=7.1'
    )
    p(
        f'- iteration {after[-1]} touches: '
        f'{[c["item"]["path"] for c in (ch2.get("changeEntries") or ch2.get("value") or []) if c.get("item", {}).get("path")]}'
    )
    last = its['value'][-1]
    p(
        f'- iteration {after[-1]} sourceRefCommit '
        f'{(last.get("sourceRefCommit") or {}).get("commitId", "")[:8]}, '
        f'reason={last.get("reason")}'
    )
else:
    p('- **no new iteration yet** — re-read the PR in the app in a moment')

s, h, pr2 = get(f'{ORG_URL}/_apis/git/pullrequests/{PR_ID}?api-version=7.1')
p(
    f'- PR now status={pr2["status"]} draft={pr2.get("isDraft")} '
    f'target={pr2["targetRefName"]} mergeStatus={pr2.get("mergeStatus")} '
    f'autoComplete={"set" if pr2.get("autoCompleteSetBy") else "no"}'
)

dump_costs()
write_result('w41_push_to_8401', '\n'.join(OUT))
