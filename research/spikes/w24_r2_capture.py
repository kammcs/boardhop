"""w24: research/14 §7 — capture the All-details payload shapes R2 routes on.
Scratch project only. Approved by Kelly 2026-09-13 (D8).

Modes (W24_MODE):
  hooks   create the R2 capture set (16 subscriptions, All + text) pointing at
          https://boardhop.relay.kammcs.com/capture/scratch-r2 — the twelve of
          research/14 §1 plus one unfiltered git.pullrequest.updated (so each
          update arrives twice and the filtered copy's subscriptionId proves
          which notificationType matched) and stage-state-changed.
  pr      fire the PR events: branch, push, create PR, add reviewer, vote,
          second push, thread comment with an @mention, retitle, abandon.
  shapes  read the captures off the box over ssh and write results/w24_shapes.md
          with the KEY TREE of every payload (keys only, never values).
  delete  remove only the scratch-r2 subscriptions (the Minimal set stays).

The capture secret is read over ssh at run time and never printed or written.
"""
import json, os, subprocess, sys, time, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, patch, call, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P  # noqa: E402

RELAY_HOST = os.environ.get('RELAY_HOST', 'deploy@boardhop.relay.kammcs.com')
CAPTURE_PREFIX = 'https://boardhop.relay.kammcs.com/capture/'
CAPTURE_NAME = 'scratch-r2'
CAPTURE_URL = CAPTURE_PREFIX + CAPTURE_NAME
MODE = os.environ.get('W24_MODE', 'hooks')
PAUSE = float(os.environ.get('W24_PAUSE', '4'))

# (publisherId, eventType, resourceVersion, extra publisher inputs, label)
EVENTS = [
    ('tfs', 'git.pullrequest.created', '1.0', {}, 'created'),
    ('tfs', 'git.pullrequest.updated', '1.0', {}, 'updated:any'),
    ('tfs', 'git.pullrequest.updated', '1.0', {'notificationType': 'PushNotification'}, 'updated:push'),
    ('tfs', 'git.pullrequest.updated', '1.0', {'notificationType': 'ReviewersUpdateNotification'}, 'updated:reviewers'),
    ('tfs', 'git.pullrequest.updated', '1.0', {'notificationType': 'StatusUpdateNotification'}, 'updated:status'),
    ('tfs', 'git.pullrequest.updated', '1.0', {'notificationType': 'ReviewerVoteNotification'}, 'updated:vote'),
    ('tfs', 'ms.vss-code.git-pullrequest-comment-event', '2.0', {}, 'comment'),
    ('tfs', 'git.pullrequest.merged', '1.0', {}, 'merged'),
    ('tfs', 'workitem.created', '1.0', {}, 'wi.created'),
    ('tfs', 'workitem.updated', '1.0', {}, 'wi.updated'),
    ('tfs', 'workitem.commented', '1.0', {}, 'wi.commented'),
    ('tfs', 'build.complete', '2.0', {}, 'build'),
    ('pipelines', 'ms.vss-pipelines.run-state-changed-event', '5.1-preview.1', {}, 'run-state'),
    ('pipelines', 'ms.vss-pipelines.stage-state-changed-event', '5.1-preview.1', {}, 'stage-state'),
    ('pipelines', 'ms.vss-pipelinechecks-events.approval-pending', '5.1-preview.1', {}, 'approval-pending'),
    ('pipelines', 'ms.vss-pipelinechecks-events.approval-completed', '5.1-preview.1', {}, 'approval-completed'),
]


def capture_secret():
    r = subprocess.run(['ssh', RELAY_HOST, 'grep ^RELAY_CAPTURE_SECRET= /srv/relay/relay.env'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('could not read the capture secret over ssh; is the deploy key loaded?')
    line = r.stdout.strip()
    assert line.startswith('RELAY_CAPTURE_SECRET='), 'unexpected relay.env content'
    return line.split('=', 1)[1].strip()


def scratch_project():
    s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
    assert isinstance(proj, dict) and proj.get('name') == SCRATCH, f'not the scratch project: {short(proj, 200)}'
    return proj


def r2_subscriptions(pid):
    s, h, body = get(f'{ORG_URL}/_apis/hooks/subscriptions?api-version=7.1')
    subs = body.get('value', []) if isinstance(body, dict) else []
    return [x for x in subs
            if (x.get('publisherInputs') or {}).get('projectId') == pid
            and (x.get('consumerInputs') or {}).get('url') == CAPTURE_URL]


def me_id():
    s, h, cd = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview')
    return cd['authenticatedUser']['id']


out = [f'# Spike w24 — R2 payload capture (scratch project, mode `{MODE}`)', '']
proj = scratch_project()
pid = proj['id']

if MODE == 'hooks':
    secret = capture_secret()
    existing = {((x.get('publisherInputs') or {}).get('notificationType') or '', x.get('eventType')): x
                for x in r2_subscriptions(pid)}
    out += ['## Subscriptions (All + text) on `' + CAPTURE_URL + '`', '',
            '| label | publisher | event | version | HTTP | id | status |', '|---|---|---|---|---|---|---|']
    for publisher, event, version, inputs, label in EVENTS:
        key = (inputs.get('notificationType', ''), event)
        if key in existing:
            x = existing[key]
            print(f'{label:20s} exists {x.get("id")} {x.get("status")}')
            out.append(f'| {label} | {publisher} | `{event}` | {version} | exists | `{x.get("id")}` | {x.get("status")} |')
            continue
        body = {
            'publisherId': publisher, 'eventType': event, 'resourceVersion': version,
            'consumerId': 'webHooks', 'consumerActionId': 'httpRequest',
            'publisherInputs': {'projectId': pid, **inputs},
            'consumerInputs': {'url': CAPTURE_URL, 'basicAuthUsername': 'hook', 'basicAuthPassword': secret,
                               'resourceDetailsToSend': 'all', 'messagesToSend': 'text', 'detailedMessagesToSend': 'text'},
        }
        st, h, sub = post(f'{ORG_URL}/_apis/hooks/subscriptions?api-version=7.1', body)
        ok = isinstance(sub, dict) and st in (200, 201)
        sid = sub.get('id') if ok else ''
        status = sub.get('status') if ok else str(sub)[:180].replace('|', '/').replace('\n', ' ')
        print(f'{label:20s} {st} {sid} {status}')
        out.append(f'| {label} | {publisher} | `{event}` | {version} | {st} | `{sid}` | {status} |')
    out.append('')

elif MODE == 'pr':
    stamp = time.strftime('%Y%m%d-%H%M%S')
    me = me_id()
    s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
    repo = next(r for r in repos['value'] if r['name'] == SCRATCH)
    assert repo['project']['id'] == pid
    R = f'{ORG_URL}/{P}/_apis/git/repositories/{repo["id"]}'
    s, h, refs = get(f'{R}/refs?filter=heads/main&api-version=7.1')
    main_sha = refs['value'][0]['objectId']
    branch = f'refs/heads/spike/w24-{stamp}'
    path = f'/spikes/w24-{stamp}.md'

    def step(label, fn):
        r = fn()
        s, body = r[0], r[-1]
        print(f'{label:32s} HTTP {s}')
        out.append(f'- {label} — HTTP {s}')
        time.sleep(PAUSE)
        return body

    def push(old, text, msg, change='edit'):
        s, h, p = post(f'{R}/pushes?api-version=7.1', {
            'refUpdates': [{'name': branch, 'oldObjectId': old}],
            'commits': [{'comment': msg, 'changes': [{
                'changeType': change, 'item': {'path': path},
                'newContent': {'content': text, 'contentType': 'rawtext'}}]}]})
        return s, p

    # Branch + first commit (git.push is not subscribed; this is the PR's source).
    s, h, mk = post(f'{R}/refs?api-version=7.1', [{'name': branch, 'oldObjectId': '0' * 40, 'newObjectId': main_sha}])
    print('branch:', s)
    p1 = step('push 1 (new file)', lambda: push(main_sha, f'# w24 {stamp}\n\nfirst\n', 'w24: first commit', change='add'))
    sha1 = p1['commits'][0]['commitId']

    pr = step('create PR (no reviewers, not draft)', lambda: post(f'{R}/pullrequests?api-version=7.1', {
        'sourceRefName': branch, 'targetRefName': 'refs/heads/main', 'isDraft': False,
        'title': f'w24 hook capture {stamp}', 'description': 'Spike w24: fires PR events into the R2 capture set. Will be abandoned.'}))
    prid = pr['pullRequestId']
    PR = f'{R}/pullRequests/{prid}'
    out.append(f'  PR **{prid}** on `{branch}`')

    step('add reviewer (me, vote 0)', lambda: call('PUT', f'{PR}/reviewers/{me}?api-version=7.1', {'vote': 0}))
    step('vote 5 (approve with suggestions)', lambda: call('PUT', f'{PR}/reviewers/{me}?api-version=7.1', {'vote': 5}))
    step('push 2 (new iteration)', lambda: push(sha1, f'# w24 {stamp}\n\nsecond\n', 'w24: second commit'))
    step('thread comment with @mention', lambda: post(f'{PR}/threads?api-version=7.1', {
        'comments': [{'parentCommentId': 0, 'commentType': 1,
                      'content': f'w24 capture: mentioning @<{me}> in a conversation thread.'}],
        'status': 1}))
    step('retitle', lambda: call('PATCH', f'{PR}?api-version=7.1', {'title': f'w24 hook capture {stamp} (retitled)'}))
    step('abandon', lambda: call('PATCH', f'{PR}?api-version=7.1', {'status': 'abandoned'}))
    out += ['', f'Branch `{branch}` left in place (the abandoned PR references it).', '']

elif MODE == 'shapes':
    r = subprocess.run(['ssh', RELAY_HOST,
                        f'cd /srv/relay/data/capture/{CAPTURE_NAME} 2>/dev/null && for f in *.json; do echo "=== $f"; cat "$f"; echo; done'],
                       capture_output=True, text=True, encoding='utf-8')
    if r.returncode != 0:
        sys.exit(f'ssh failed: {r.stderr[:200]}')
    chunks = r.stdout.split('=== ')[1:]
    print(f'{len(chunks)} capture files')

    def tree(node, depth=0, lines=None, prefix=''):
        lines = [] if lines is None else lines
        if isinstance(node, dict):
            for k in sorted(node):
                v = node[k]
                kind = ('{}' if isinstance(v, dict) else f'[{len(v)}]' if isinstance(v, list)
                        else 'null' if v is None else type(v).__name__)
                lines.append(f'{"  " * depth}{k}: {kind}')
                if isinstance(v, (dict, list)) and depth < 6:
                    tree(v, depth + 1, lines)
        elif isinstance(node, list) and node:
            tree(node[0], depth, lines)
        return lines

    for chunk in chunks:
        name, _, body = chunk.partition('\n')
        try:
            cap = json.loads(body)
        except json.JSONDecodeError:
            out += [f'## {name}: not JSON', '']
            continue
        payload = cap.get('body') if isinstance(cap.get('body'), dict) else cap
        ev = payload.get('eventType')
        sub = payload.get('subscriptionId')
        rv = payload.get('resourceVersion')
        res = payload.get('resource') or {}
        out += [f'## `{name.strip()}`', '',
                f'eventType `{ev}` · resourceVersion `{rv}` · subscriptionId `{sub}` · body {len(body)} bytes', '',
                '```', *tree({'resource': res, 'resourceContainers': payload.get('resourceContainers'),
                              'message': {k: type(v).__name__ for k, v in (payload.get('message') or {}).items()}}), '```', '']
        print(name.strip(), ev, sub)
    out.append('Values are never copied here: keys and types only.')

elif MODE == 'delete':
    mine = r2_subscriptions(pid)
    out += [f'## Deleting {len(mine)} scratch-r2 subscription(s)', '']
    for x in mine:
        assert (x.get('publisherInputs') or {}).get('projectId') == pid
        assert (x.get('consumerInputs') or {}).get('url') == CAPTURE_URL
        st, h, _ = call('DELETE', f'{ORG_URL}/_apis/hooks/subscriptions/{x["id"]}?api-version=7.1')
        print('delete', x.get('eventType'), (x.get('publisherInputs') or {}).get('notificationType', ''), st)
        out.append(f'- `{x.get("eventType")}` {(x.get("publisherInputs") or {}).get("notificationType", "")} (`{x.get("id")}`) — HTTP {st}')
    out.append('')
else:
    sys.exit(f'unknown W24_MODE {MODE!r}; use hooks, pr, shapes or delete')

out.append(dump_costs())
write_result(f'w24_r2_capture_{MODE}.md', '\n'.join(out))
