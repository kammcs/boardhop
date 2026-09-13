"""w22: research/06 spike 3 — capture the real "Minimal" service-hook payloads.

Creates one webhook subscription per interesting event against the **scratch
project only**, pointing at the capture endpoint on the relay box
(https://boardhop.relay.kammcs.com/capture/scratch, HTTP basic auth). Then the
scratch project is exercised (edit a work item, comment, update PR 8336, run
pipeline 139 and let the Deploy approval sit) and the payloads land as JSON
files on the box.

Modes:
    python _run_with_mcp_creds.py w22_hook_capture.py            # create
    W22_MODE=list   python _run_with_mcp_creds.py w22_hook_capture.py
    W22_MODE=delete python _run_with_mcp_creds.py w22_hook_capture.py

The capture secret is read over ssh at run time and never printed or written.
`delete` removes only subscriptions whose consumerInputs.url sits under
CAPTURE_PREFIX *and* whose projectId is the scratch project.

Event ids and resourceVersions come from spike s39 (results/s39_hook_publishers.md).
Two ids in the original research/06 list do not exist as written:
  * `ms.vss-work.work-item-comment-event` — the real id is `workitem.commented`
    on the `tfs` publisher;
  * the two pipeline events live on the `pipelines` publisher, not `tfs`, and
    only at resourceVersion 5.1-preview.1.
"""
import os, subprocess, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P  # noqa: E402

RELAY_HOST = os.environ.get('RELAY_HOST', 'deploy@boardhop.relay.kammcs.com')
CAPTURE_PREFIX = 'https://boardhop.relay.kammcs.com/capture/'
CAPTURE_NAME = os.environ.get('W22_CAPTURE_NAME', 'scratch')
CAPTURE_URL = CAPTURE_PREFIX + CAPTURE_NAME
MODE = os.environ.get('W22_MODE', 'create')

# What the production design asks for: pointers, not content. Flip these to
# 'all' / 'text' against a second capture name (W22_CAPTURE_NAME=scratch-all)
# if we ever need to see what the verbose settings would have leaked.
RESOURCE_DETAILS = os.environ.get('W22_RESOURCE_DETAILS', 'minimal')
MESSAGES = os.environ.get('W22_MESSAGES', 'none')

# (publisherId, eventType, resourceVersion, extra publisher inputs)
# Empty strings mean "any", the way the Azure DevOps UI sends them (proven by w21).
EVENTS = [
    ('tfs', 'git.pullrequest.created', '1.0',
     {'repository': '', 'branch': '', 'pullrequestCreatedBy': '', 'pullrequestReviewersContains': ''}),
    ('tfs', 'git.pullrequest.updated', '1.0',
     {'repository': '', 'branch': '', 'notificationType': '', 'pullrequestCreatedBy': '',
      'pullrequestReviewersContains': ''}),
    ('tfs', 'ms.vss-code.git-pullrequest-comment-event', '2.0', {'repository': '', 'branch': ''}),
    ('tfs', 'workitem.created', '1.0', {'areaPath': '', 'workItemType': ''}),
    ('tfs', 'workitem.updated', '1.0', {'areaPath': '', 'workItemType': '', 'changedFields': ''}),
    # research/06 called this ms.vss-work.work-item-comment-event; that id does not exist.
    ('tfs', 'workitem.commented', '1.0', {'areaPath': '', 'workItemType': ''}),
    ('tfs', 'build.complete', '1.0', {'definitionName': '', 'buildStatus': ''}),
    ('pipelines', 'ms.vss-pipelines.run-state-changed-event', '5.1-preview.1',
     {'pipelineId': '', 'runStateId': '', 'runResultId': ''}),
    ('pipelines', 'ms.vss-pipelinechecks-events.approval-pending', '5.1-preview.1',
     {'pipelineId': '', 'stageName': '', 'environmentName': ''}),
]

READ_BACK = [
    '```sh',
    'ssh deploy@boardhop.relay.kammcs.com \\',
    '  \'. /srv/relay/relay.env; curl -fsS -u "hook:$RELAY_CAPTURE_SECRET" \\',
    '   ' + CAPTURE_URL + '\'',
    '```',
]


def capture_secret():
    """Read RELAY_CAPTURE_SECRET off the relay box over ssh. Never printed."""
    r = subprocess.run(['ssh', RELAY_HOST, 'grep ^RELAY_CAPTURE_SECRET= /srv/relay/relay.env'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('could not read the capture secret over ssh; is the deploy key loaded?')
    line = r.stdout.strip()
    if not line.startswith('RELAY_CAPTURE_SECRET='):
        sys.exit('unexpected relay.env content')
    return line.split('=', 1)[1].strip()


def scratch_project_id():
    s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
    assert isinstance(proj, dict) and proj.get('name') == SCRATCH, f'not the scratch project: {short(proj, 200)}'
    return proj['id']


def subscriptions_for(pid):
    """Every subscription whose publisher inputs name the scratch project."""
    s, h, body = get(f'{ORG_URL}/_apis/hooks/subscriptions?api-version=7.1')
    subs = body.get('value', []) if isinstance(body, dict) else []
    return s, [x for x in subs if (x.get('publisherInputs') or {}).get('projectId') == pid]


def is_ours(sub):
    url = (sub.get('consumerInputs') or {}).get('url') or ''
    return url.startswith(CAPTURE_PREFIX)


out = [f'# Spike w22 — Minimal webhook payload capture (scratch project, mode `{MODE}`)', '']
pid = scratch_project_id()
out += [f'Scratch project `{SCRATCH}` id confirmed; capture endpoint `{CAPTURE_URL}`.',
        f'resourceDetailsToSend `{RESOURCE_DETAILS}`, messagesToSend `{MESSAGES}`.', '']

if MODE == 'list':
    s, subs = subscriptions_for(pid)
    out += [f'## Subscriptions on the scratch project — HTTP {s}', '',
            '| id | publisher | event | version | status | consumer url | ours |',
            '|---|---|---|---|---|---|---|']
    for x in subs:
        url = (x.get('consumerInputs') or {}).get('url') or ''
        out.append(f'| `{x.get("id")}` | {x.get("publisherId")} | `{x.get("eventType")}` | '
                   f'{x.get("resourceVersion")} | {x.get("status")} | `{url}` | {"yes" if is_ours(x) else "no"} |')
        print(x.get('id'), x.get('eventType'), x.get('status'))
    out.append('')

elif MODE == 'delete':
    s, subs = subscriptions_for(pid)
    mine = [x for x in subs if is_ours(x)]
    out += [f'## Deleting {len(mine)} subscription(s) created by this spike', '']
    for x in mine:
        # Belt and braces: the scratch project and our capture URL, or it is not touched.
        assert (x.get('publisherInputs') or {}).get('projectId') == pid
        assert is_ours(x)
        st, h, _ = call('DELETE', f'{ORG_URL}/_apis/hooks/subscriptions/{x["id"]}?api-version=7.1')
        print('delete', x.get('eventType'), st)
        out.append(f'- `{x.get("eventType")}` (`{x.get("id")}`) — HTTP {st}')
    out.append('')

elif MODE == 'create':
    secret = capture_secret()
    out += ['## Created subscriptions', '',
            '| publisher | event | version | HTTP | id | status |', '|---|---|---|---|---|---|']
    created = 0
    for publisher, event, version, inputs in EVENTS:
        body = {
            'publisherId': publisher,
            'eventType': event,
            'resourceVersion': version,
            'consumerId': 'webHooks',
            'consumerActionId': 'httpRequest',
            'publisherInputs': {'projectId': pid, **inputs},
            'consumerInputs': {
                'url': CAPTURE_URL,
                'basicAuthUsername': 'hook',
                'basicAuthPassword': secret,
                'resourceDetailsToSend': RESOURCE_DETAILS,
                'messagesToSend': MESSAGES,
                'detailedMessagesToSend': MESSAGES,
            },
        }
        st, h, sub = post(f'{ORG_URL}/_apis/hooks/subscriptions?api-version=7.1', body)
        ok = isinstance(sub, dict) and st in (200, 201)
        sid = sub.get('id') if ok else ''
        status = sub.get('status') if ok else str(sub)[:180].replace('|', '/').replace('\n', ' ')
        created += 1 if ok else 0
        print(f'{event:48s} {st} {sid} {status}')
        out.append(f'| {publisher} | `{event}` | {version} | {st} | `{sid}` | {status} |')
    out += ['', f'{created} of {len(EVENTS)} subscriptions created.', '',
            'Now exercise the scratch project and read the captures with:', ''] + READ_BACK + [
            '', f'The files themselves are in `/srv/relay/data/capture/{CAPTURE_NAME}/` on the box.', '',
            'Clean up with `W22_MODE=delete`.', '']
else:
    sys.exit(f'unknown W22_MODE {MODE!r}; use create, list or delete')

out.append(dump_costs())
write_result(f'w22_hook_capture_{MODE}.md', '\n'.join(out))
