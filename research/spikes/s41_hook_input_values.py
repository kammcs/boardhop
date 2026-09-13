"""s41: read-only. Which values do the service-hook filter inputs accept?
research/14 §1.2 wants four `git.pullrequest.updated` subscriptions filtered
by `notificationType`; s39 listed the input's name but not its values. Also
reads `changedFields` (workitem.updated), `buildStatus` (build.complete) and
the pipelines publisher's inputs, so nothing here needs re-probing."""
import json, os, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402

WANT = {
    'tfs': {
        'git.pullrequest.updated': ['notificationType', 'pullrequestReviewersContains', 'pullrequestCreatedBy'],
        'git.pullrequest.merged': ['mergeResult'],
        'workitem.updated': ['changedFields', 'linksChanged'],
        'workitem.commented': ['commentPattern'],
        'build.complete': ['buildStatus', 'definitionName'],
    },
    'pipelines': {
        'ms.vss-pipelines.run-state-changed-event': ['runStateId', 'runResultId', 'pipelineId'],
        'ms.vss-pipelinechecks-events.approval-pending': ['stageName', 'environmentName'],
        'ms.vss-pipelinechecks-events.approval-completed': ['stageName', 'environmentName'],
        'ms.vss-pipelines.stage-state-changed-event': ['stageStateId', 'stageResultId'],
    },
}

out = ['# Spike s41 — service-hook filter input values (read-only)', '']
for publisher, events in WANT.items():
    s, h, pub = get(f'{ORG_URL}/_apis/hooks/publishers/{publisher}?api-version=7.1')
    out += [f'## publisher `{publisher}` — HTTP {s}', '']
    if not isinstance(pub, dict):
        out.append(short(pub, 400))
        continue
    by_id = {e.get('id'): e for e in pub.get('supportedEvents', [])}
    for event, inputs in events.items():
        e = by_id.get(event)
        out += [f'### `{event}`', '']
        if e is None:
            out += ['not found', '']
            continue
        descs = {d.get('id'): d for d in e.get('inputDescriptors', [])}
        for name in inputs:
            d = descs.get(name)
            if d is None:
                out.append(f'- `{name}`: **no descriptor**')
                print(event, name, 'missing')
                continue
            vals = d.get('values') or {}
            pv = vals.get('possibleValues') or []
            mode = d.get('inputMode')
            dep = d.get('dependencyInputIds')
            hasDyn = d.get('hasDynamicValueInformation')
            line = (f'- `{name}` ({d.get("name")}), mode {mode}, dynamic values {hasDyn}, '
                    f'depends on {dep}, default {vals.get("defaultValue")!r}')
            out.append(line)
            print(event, name, mode, 'dynamic' if hasDyn else '', [v.get('value') for v in pv])
            if pv:
                out.append('')
                out.append('  | value | display |')
                out.append('  |---|---|')
                for v in pv:
                    out.append(f'  | `{v.get("value")}` | {v.get("displayValue")} |')
            if d.get('description'):
                out.append(f'  description: {d["description"]}')
        out.append('')
        # keep the raw descriptors for the inputs we care about
        raw = [descs[n] for n in inputs if n in descs]
        out += ['<details><summary>raw descriptors</summary>', '', '```json', short(raw, 6000), '```', '</details>', '']

out.append(dump_costs())
write_result('s41_hook_input_values.md', '\n'.join(out))
