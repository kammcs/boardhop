"""s31 (read-only): read back the items the phase 2 walkthrough created in
the scratch project and print each one's `multilineFieldsFormat`, to confirm
the HTML item stayed `html` and the Markdown one is `markdown` (spike w01).

Matches on the `[phase2]` title prefix, newest first.
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post, dump_costs  # noqa: E402

PROJECT = 'DevOps Mobile App'
P = urllib.parse.quote(PROJECT)

wiql = ("SELECT [System.Id] FROM WorkItems "
        "WHERE [System.TeamProject] = @project "
        "AND [System.Title] CONTAINS '[phase2]' "
        "ORDER BY [System.Id] DESC")
s, h, body = post(f'{ORG_URL}/{P}/_apis/wit/wiql?api-version=7.1', {'query': wiql})
ids = [str(r['id']) for r in (body.get('workItems') or [])][:10]
print('HTTP', s, 'matching ids:', ids)
if not ids:
    dump_costs()
    sys.exit(0)

s, h, items = get(f'{ORG_URL}/{P}/_apis/wit/workitems?ids={",".join(ids)}'
                  '&$expand=all&api-version=7.1')
for it in (items.get('value') or []):
    f = it.get('fields') or {}
    desc = f.get('System.Description') or ''
    print()
    print(f"#{it['id']} {f.get('System.WorkItemType')} — {f.get('System.Title')}")
    print('  state:', f.get('System.State'), '| iteration:', f.get('System.IterationPath'))
    print('  multilineFieldsFormat:', it.get('multilineFieldsFormat'))
    print('  description:', repr(desc[:400]))

dump_costs()
