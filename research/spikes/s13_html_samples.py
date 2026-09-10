"""Spike F3 input: collect real HTML descriptions from the project.

Read-only. Takes recent work items, keeps the ones whose Description /
ReproSteps / AcceptanceCriteria contain HTML, tags each sample with the
constructs it exercises (table, nested list, image, mention, heading, code,
link, inline style) and writes them to results/f3-samples.json (gitignored;
client data) plus a Markdown summary.
"""
import json, os, re, sys
from urllib.parse import quote
sys.path.insert(0, os.path.dirname(__file__))
from lib import ORG_URL, DEFAULT_PROJECT, get, post, write_result, dump_costs

P = quote(DEFAULT_PROJECT)
FIELDS = ['System.Description', 'Microsoft.VSTS.TCM.ReproSteps', 'Microsoft.VSTS.Common.AcceptanceCriteria']

wiql = {'query': "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject]=@project ORDER BY [System.ChangedDate] DESC"}
s, h, b = post(f'{ORG_URL}/{P}/_apis/wit/wiql?$top=200&api-version=7.1', wiql)
ids = [w['id'] for w in b.get('workItems', [])] if isinstance(b, dict) else []
print(f'wiql {s}: {len(ids)} ids')

samples = []
for i in range(0, len(ids), 50):
    chunk = ids[i:i + 50]
    s, h, b = get(f'{ORG_URL}/_apis/wit/workitems?ids={",".join(map(str, chunk))}&api-version=7.1')
    if s != 200 or not isinstance(b, dict):
        print('batch', s); continue
    for w in b['value']:
        fmt = w.get('multilineFieldsFormat') or {}
        for f in FIELDS:
            html = (w['fields'].get(f) or '').strip()
            if '<' not in html or len(html) < 40:
                continue
            tags = set()
            if re.search(r'<table', html, re.I): tags.add('table')
            if re.search(r'<(ul|ol)[^>]*>(?:(?!</\1>).)*<(ul|ol)', html, re.I | re.S): tags.add('nested-list')
            elif re.search(r'<(ul|ol)', html, re.I): tags.add('list')
            if re.search(r'<img', html, re.I): tags.add('image')
            if 'data-vss-mention' in html: tags.add('mention')
            if re.search(r'<h[1-6]', html, re.I): tags.add('heading')
            if re.search(r'<(pre|code)', html, re.I): tags.add('code')
            if re.search(r'<a\s', html, re.I): tags.add('link')
            if re.search(r'style="[^"]*(color|background)', html, re.I): tags.add('inline-color')
            if re.search(r'<(b|strong|i|em|u|s|strike)\b', html, re.I): tags.add('inline-format')
            if re.search(r'<div|<br', html, re.I): tags.add('div-br')
            samples.append({
                'id': w['id'], 'type': w['fields'].get('System.WorkItemType'), 'field': f,
                'format': fmt.get(f), 'length': len(html), 'tags': sorted(tags), 'html': html,
            })

# Prefer samples that exercise the most constructs; keep a spread.
samples.sort(key=lambda x: (-len(x['tags']), -x['length']))
by_tag = {}
for x in samples:
    for t in x['tags']:
        by_tag.setdefault(t, 0); by_tag[t] += 1

out_dir = os.path.join(os.path.dirname(__file__), 'results')
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, 'f3-samples.json'), 'w', encoding='utf-8') as fh:
    json.dump(samples, fh, indent=1, ensure_ascii=False)

lines = [f'# s13: HTML samples from {P}', '', f'{len(ids)} recent work items scanned; {len(samples)} HTML fields kept.', '',
         '| construct | fields |', '|---|---|'] + [f'| {t} | {n} |' for t, n in sorted(by_tag.items())] + ['', '## Top samples', '',
         '| id | type | field | length | constructs |', '|---|---|---|---|---|']
for x in samples[:25]:
    lines.append(f"| {x['id']} | {x['type']} | {x['field'].split('.')[-1]} | {x['length']} | {', '.join(x['tags'])} |")
lines += ['', dump_costs()]
write_result('s13_html_samples.md', '\n'.join(lines))
print('\n'.join(lines[:12]))
