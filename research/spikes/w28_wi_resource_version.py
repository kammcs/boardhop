"""w28: scratch write. The live relay showed a resourceVersion 1.0
`workitem.updated` body with System.AssignedTo but no identity id
(research/14 §1.1 assumed identity objects). Capture the same event at
3.1-preview.3 and 5.1-preview.3 into /capture/scratch-wi and print the
TYPE of System.AssignedTo / System.CreatedBy / System.ChangedBy in
`resource.revision.fields` and `resource.fields.*.newValue` (keys and
types only, never values).

Modes (W28_MODE): create | shapes | delete
"""
import json, os, subprocess, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P  # noqa: E402

RELAY_HOST = 'deploy@boardhop.relay.kammcs.com'
CAPTURE_URL = 'https://boardhop.relay.kammcs.com/capture/scratch-wi'
MODE = os.environ.get('W28_MODE', 'create')
VERSIONS = ['3.1-preview.3', '5.1-preview.3']


def capture_secret():
    r = subprocess.run(['ssh', RELAY_HOST, 'grep ^RELAY_CAPTURE_SECRET= /srv/relay/relay.env'], capture_output=True, text=True)
    assert r.returncode == 0 and r.stdout.startswith('RELAY_CAPTURE_SECRET='), 'no capture secret'
    return r.stdout.strip().split('=', 1)[1]


out = [f'# Spike w28 — workitem.updated resourceVersion probe (mode `{MODE}`)', '']
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == SCRATCH
pid = proj['id']

if MODE == 'create':
    secret = capture_secret()
    for v in VERSIONS:
        body = {'publisherId': 'tfs', 'eventType': 'workitem.updated', 'resourceVersion': v,
                'consumerId': 'webHooks', 'consumerActionId': 'httpRequest',
                'publisherInputs': {'projectId': pid, 'areaPath': '', 'workItemType': '', 'changedFields': ''},
                'consumerInputs': {'url': CAPTURE_URL, 'basicAuthUsername': 'hook', 'basicAuthPassword': secret,
                                   'resourceDetailsToSend': 'all', 'messagesToSend': 'text', 'detailedMessagesToSend': 'text'}}
        st, h, sub = post(f'{ORG_URL}/_apis/hooks/subscriptions?api-version=7.1', body)
        print(v, st, sub.get('id') if isinstance(sub, dict) else str(sub)[:200])
        out.append(f'- `{v}` — HTTP {st} `{sub.get("id") if isinstance(sub, dict) else ""}` {sub.get("status") if isinstance(sub, dict) else str(sub)[:120]}')
elif MODE == 'shapes':
    r = subprocess.run(['ssh', RELAY_HOST, 'cd /srv/relay/data/capture/scratch-wi && for f in *.json; do echo "=== $f"; cat "$f"; echo; done'],
                       capture_output=True, text=True, encoding='utf-8')
    for chunk in r.stdout.split('=== ')[1:]:
        name, _, body = chunk.partition('\n')
        try:
            cap = json.loads(body)
        except json.JSONDecodeError:
            continue
        payload = cap.get('body') if isinstance(cap.get('body'), dict) else cap
        res = payload.get('resource') or {}
        rv = payload.get('resourceVersion')
        fields = (res.get('revision') or {}).get('fields') or {}
        changes = res.get('fields') or {}

        def t(v):
            return 'null' if v is None else ('object(' + ','.join(sorted(v.keys())) + ')' if isinstance(v, dict) else type(v).__name__)

        out += [f'## `{name.strip()}` — resourceVersion `{rv}`', '',
                f'- revision.fields keys: {sorted(fields.keys())}',
                *[f'- revision.fields[{k}]: {t(fields.get(k))}' for k in ('System.AssignedTo', 'System.CreatedBy', 'System.ChangedBy') if k in fields],
                *[f'- fields[{k}].newValue: {t((changes.get(k) or {}).get("newValue"))}, oldValue: {t((changes.get(k) or {}).get("oldValue"))}'
                  for k in ('System.AssignedTo', 'System.ChangedBy') if k in changes],
                f'- revisedBy: {t(res.get("revisedBy"))}', '']
        print(name.strip(), rv, {k: t(fields.get(k)) for k in ('System.AssignedTo', 'System.CreatedBy') if k in fields})
elif MODE == 'delete':
    s, h, body = get(f'{ORG_URL}/_apis/hooks/subscriptions?api-version=7.1')
    for x in body.get('value', []):
        if (x.get('consumerInputs') or {}).get('url') == CAPTURE_URL and (x.get('publisherInputs') or {}).get('projectId') == pid:
            st, h, _ = call('DELETE', f'{ORG_URL}/_apis/hooks/subscriptions/{x["id"]}?api-version=7.1')
            print('delete', x.get('resourceVersion'), st)
            out.append(f'- deleted `{x.get("resourceVersion")}` `{x["id"]}` — HTTP {st}')
out.append(dump_costs())
write_result(f'w28_wi_resource_version_{MODE}.md', '\n'.join(out))
