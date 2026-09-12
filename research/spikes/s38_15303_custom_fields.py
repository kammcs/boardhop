"""s38 (read-only): which fields work item #15303 (CloudCover 2.0) actually
carries, for the layout-driven detail page. Prints field reference names,
whether each is set, and a 40-character preview only — no full client text,
and nothing is written to the results folder.
"""
import os, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs  # noqa: E402

WID = int(sys.argv[1]) if len(sys.argv) > 1 else 15303

s, h, w = get(f'{ORG_URL}/_apis/wit/workitems/{WID}?$expand=all&api-version=7.1')
if s != 200 or not isinstance(w, dict):
    print(f'HTTP {s}: {str(w)[:200]}')
    dump_costs()
    sys.exit(1)
f = w.get('fields') or {}
print(f'#{WID} HTTP {s} rev {w.get("rev")} type {f.get("System.WorkItemType")!r} '
      f'project {f.get("System.TeamProject")!r} fields {len(f)}')
print('multilineFieldsFormat:', w.get('multilineFieldsFormat'))
print()
for name in sorted(f):
    v = f[name]
    if isinstance(v, dict):
        preview = str(v.get('displayName') or sorted(v)[:3])
    else:
        preview = str(v)
    preview = ' '.join(preview.split())[:40]
    filled = bool(preview) and preview.lower() not in ('none', '')
    print(f'{"SET  " if filled else "empty"} {name:60s} {preview}')

print()
print('--- custom fields only ---')
for name in sorted(f):
    if name.startswith('Custom.'):
        print(f'  {name}: set')

# The type's layout: which group each custom field sits in (read-only).
t = f.get('System.WorkItemType')
p = f.get('System.TeamProject')
if t and p:
    import urllib.parse
    s2, _, ty = get(f'{ORG_URL}/{urllib.parse.quote(p)}/_apis/wit/workitemtypes/'
                    f'{urllib.parse.quote(t)}?api-version=7.1')
    xml = (ty or {}).get('xmlForm') if isinstance(ty, dict) else None
    print(f'\nxmlForm HTTP {s2} length {len(xml or "")}')
    if xml:
        import re
        # Group label -> the field names its controls name.
        for m in re.finditer(r'<Group(?:\s[^>]*)?>(.*?)</Group>', xml, re.S):
            label = re.search(r'Label="([^"]*)"', m.group(0)[:200])
            fields = re.findall(r'FieldName="([^"]+)"', m.group(1))
            if fields:
                print(f'  group {label.group(1) if label else "(none)":24s} '
                      f'{[x for x in fields]}')
dump_costs()

# Which CloudCover User Stories do carry the QA custom fields (read-only WIQL,
# ids only): #15303 has neither, so a device check of an identity/number
# custom field needs another item.
if p:
    import urllib.parse
    q = ("SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project "
         "AND [Custom.QAAssignee] <> '' ORDER BY [System.ChangedDate] DESC")
    s3, _, r3 = get(f'{ORG_URL}/{urllib.parse.quote(p)}/_apis/wit/wiql?'
                    '$top=8&api-version=7.1', ) if False else (None, None, None)
    from lib import post
    s3, _, r3 = post(f'{ORG_URL}/{urllib.parse.quote(p)}/_apis/wit/wiql?$top=8&api-version=7.1',
                     {'query': q})
    ids = [w['id'] for w in ((r3 or {}).get('workItems') or [])] if isinstance(r3, dict) else []
    print(f'\nQAAssignee set on (HTTP {s3}): {ids}')
    q2 = q.replace('Custom.QAAssignee', 'Custom.QAStoryPoints').replace("<> ''", '<> 0')
    s4, _, r4 = post(f'{ORG_URL}/{urllib.parse.quote(p)}/_apis/wit/wiql?$top=8&api-version=7.1',
                     {'query': q2})
    ids2 = [w['id'] for w in ((r4 or {}).get('workItems') or [])] if isinstance(r4, dict) else []
    print(f'QAStoryPoints set on (HTTP {s4}): {ids2}')
