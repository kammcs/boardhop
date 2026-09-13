"""w21: does the spike PAT carry vso.hooks_write? Scratch project only:
create one webhook subscription (build.complete, scoped to the scratch
project, pointing at a kammcs URL that just answers 404), read it back,
then delete it. Leaves nothing behind."""
import json, os, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, call, dump_costs, write_result, short  # noqa: E402
from scratch import SCRATCH, P  # noqa: E402

out = ['# Spike w21 — hooks write scope (scratch project)', '']
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
assert proj['name'] == SCRATCH, proj
pid = proj['id']

body = {
    'publisherId': 'tfs',
    'eventType': 'build.complete',
    'resourceVersion': '1.0',
    'consumerId': 'webHooks',
    'consumerActionId': 'httpRequest',
    'publisherInputs': {'projectId': pid, 'definitionName': '', 'buildStatus': ''},
    'consumerInputs': {'url': 'https://kammcs.com/boardhop-hook-probe', 'resourceDetailsToSend': 'minimal',
                       'messagesToSend': 'none', 'detailedMessagesToSend': 'none'},
}
s, h, sub = post(f'{ORG_URL}/_apis/hooks/subscriptions?api-version=7.1', body)
print('create subscription:', s, sub.get('id') if isinstance(sub, dict) else str(sub)[:300])
out += [f'## POST hooks/subscriptions — HTTP {s}', '```json', short(sub if isinstance(sub, dict) else {'body': sub}, 800), '```', '']
if s not in (200, 201):
    write_result('w21_hook_scope_probe.md', '\n'.join(out + [dump_costs()]))
    sys.exit(1)
sid = sub['id']
s, h, back = get(f'{ORG_URL}/_apis/hooks/subscriptions/{sid}?api-version=7.1')
print('read back:', s, back.get('status') if isinstance(back, dict) else '', back.get('eventType') if isinstance(back, dict) else '')
out += [f'read back — HTTP {s}: status {back.get("status")!r}, event {back.get("eventType")!r}, project scope {back.get("publisherInputs", {}).get("projectId") == pid}', '']
s, h, gone = call('DELETE', f'{ORG_URL}/_apis/hooks/subscriptions/{sid}?api-version=7.1')
print('delete:', s)
out += [f'DELETE — HTTP {s}', '']
s, h, check = get(f'{ORG_URL}/_apis/hooks/subscriptions/{sid}?api-version=7.1')
print('after delete:', s)
out += [f'GET after delete — HTTP {s} (404 expected)', '', dump_costs()]
write_result('w21_hook_scope_probe.md', '\n'.join(out))
