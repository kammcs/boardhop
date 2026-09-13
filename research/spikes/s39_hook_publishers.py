"""s39 (read-only): list the `tfs` service-hook publisher's event types, their
resourceVersions and their input filters, so spike w22 can subscribe with the
exact ids. Also lists the consumers so the webHooks/httpRequest action inputs
are on record. Nothing is created."""
import os, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402

WANTED = [
    'git.pullrequest.created', 'git.pullrequest.updated',
    'ms.vss-code.git-pullrequest-comment-event',
    'workitem.created', 'workitem.updated',
    'ms.vss-work.work-item-comment-event',
    'build.complete', 'ms.vss-pipelines.run-state-changed-event',
    'ms.vss-pipelinechecks-events.approval-pending',
]

out = ['# Spike s39 — service hook publishers and event types (read-only)', '',
       'Source: `GET {org}/_apis/hooks/publishers/tfs?api-version=7.1` and',
       '`GET {org}/_apis/hooks/consumers/webHooks?api-version=7.1`.', '']

s, h, pub = get(f'{ORG_URL}/_apis/hooks/publishers/tfs?api-version=7.1')
print('publishers/tfs:', s)
out += [f'## publisher `tfs` — HTTP {s}', '']
events = []
if isinstance(pub, dict):
    events = pub.get('supportedEvents') or []
    out += [f'name: `{pub.get("name")}`, {len(events)} supported events', '']

by_id = {e.get('id'): e for e in events if isinstance(e, dict)}


def versions(e):
    v = e.get('supportedResourceVersions') or []
    if isinstance(v, dict):
        v = list(v.keys())
    return ', '.join(str(x) for x in sorted(v)) or '(none listed)'


def inputs(e):
    """Event-level publisher inputs. The API spells them `inputDescriptors`
    on the event; the publisher itself carries a shared set under the same key."""
    ids = []
    for key in ('inputDescriptors', 'publisherInputDescriptors'):
        for i in (e.get(key) or []):
            if isinstance(i, dict) and i.get('id') not in ids:
                req = (i.get('validation') or {}).get('isRequired')
                ids.append(i['id'] + ('*' if req else ''))
    return ', '.join(f'`{i}`' for i in ids) or '(none)'


out += ['## Events wanted by spike w22', '',
        '| requested id | present | resourceVersions | publisher inputs |', '|---|---|---|---|']
missing = []
for w in WANTED:
    e = by_id.get(w)
    if e:
        out.append(f'| `{w}` | yes | {versions(e)} | {inputs(e)} |')
    else:
        missing.append(w)
        out.append(f'| `{w}` | **NO** | — | — |')
out.append('')
if missing:
    out += ['Not found on the `tfs` publisher; look for them on another publisher:', '']
    for m in missing:
        out.append(f'- `{m}`')
    out.append('')

pub_inputs = [i.get('id') for i in (pub.get('inputDescriptors') or []) if isinstance(i, dict)] if isinstance(pub, dict) else []
out += [f'Publisher-level inputs shared by every `tfs` event: ' +
        (', '.join(f'`{i}`' for i in pub_inputs) or '(none)'), '',
        '(A `*` marks a required input. `projectId` is how a subscription is scoped to one project.)', '']

out += ['## All `tfs` event types', '', '| id | name | resourceVersions | publisher inputs |', '|---|---|---|---|']
for e in sorted(events, key=lambda x: x.get('id') or ''):
    out.append(f'| `{e.get("id")}` | {e.get("name")} | {versions(e)} | {inputs(e)} |')
out.append('')

s, h, pubs = get(f'{ORG_URL}/_apis/hooks/publishers?api-version=7.1')
out += [f'## All publishers — HTTP {s}', '']
if isinstance(pubs, dict):
    for p in pubs.get('value', []):
        ev = [e.get('id') for e in (p.get('supportedEvents') or []) if isinstance(e, dict)]
        out.append(f'- `{p.get("id")}` — {p.get("name")}: {len(ev)} events')
        for w in list(missing):
            if w in ev:
                e = next(x for x in p['supportedEvents'] if x.get('id') == w)
                out.append(f'  - **`{w}`** here: versions {versions(e)}, inputs {inputs(e)}')
    out.append('')

s, h, pl = get(f'{ORG_URL}/_apis/hooks/publishers/pipelines?api-version=7.1')
out += [f'## publisher `pipelines` — HTTP {s}', '']
if isinstance(pl, dict):
    pl_inputs = [i.get('id') for i in (pl.get('inputDescriptors') or []) if isinstance(i, dict)]
    out += ['Publisher-level inputs: ' + (', '.join(f'`{i}`' for i in pl_inputs) or '(none)'), '',
            '| id | name | resourceVersions | publisher inputs |', '|---|---|---|---|']
    for e in sorted(pl.get('supportedEvents') or [], key=lambda x: x.get('id') or ''):
        out.append(f'| `{e.get("id")}` | {e.get("name")} | {versions(e)} | {inputs(e)} |')
    out.append('')

s, h, cons = get(f'{ORG_URL}/_apis/hooks/consumers/webHooks?api-version=7.1')
out += [f'## consumer `webHooks` — HTTP {s}', '']
if isinstance(cons, dict):
    for a in cons.get('actions', []):
        ids = [i.get('id') for i in (a.get('inputDescriptors') or []) if isinstance(i, dict)]
        out.append(f'- action `{a.get("id")}`: inputs {", ".join(f"`{i}`" for i in ids)}')
    out.append('')
    out += ['<details><summary>raw httpRequest action</summary>', '', '```json',
            short(next((a for a in cons.get('actions', []) if a.get('id') == 'httpRequest'), {}), 4000), '```', '</details>', '']

out.append(dump_costs())
write_result('s39_hook_publishers.md', '\n'.join(out))
print('events:', len(events), 'missing:', missing)
