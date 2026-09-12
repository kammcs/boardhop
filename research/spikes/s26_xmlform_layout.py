"""s26: the Processes layout API refuses locked (stock) types (spike s24,
VS403115), so can the project-scoped `wit/workitemtypes/{type}` xmlForm
carry the same layout for every type? Read-only: parse the WebLayout XML
for a stock type in the scratch project and a customized type in
CloudCover 2.0 and print pages, sections, groups and controls."""
import os, sys, urllib.parse
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result  # noqa: E402

CASES = [('DevOps Mobile App', 'Bug'), ('DevOps Mobile App', 'User Story'), ('DevOps Mobile App', 'Epic'),
         ('CloudCover 2.0', 'User Story'), ('CloudCover 2.0', 'Epic'), ('CloudCover 2.0', 'QA Task')]
out = ['# Spike s26 — xmlForm as the layout source', '']

for project, tname in CASES:
    P = urllib.parse.quote(project)
    s, h, wt = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/{urllib.parse.quote(tname)}?api-version=7.1')
    xml = wt.get('xmlForm') if isinstance(wt, dict) else None
    out += [f'## {project} / {tname} — HTTP {s}, xmlForm {len(xml or "")} bytes', '']
    print(f'\n{project} / {tname}: {s} xmlForm {len(xml or "")} bytes')
    if not xml:
        continue
    root = ET.fromstring(xml)
    out += [f'root tag: `{root.tag}`; children: {[c.tag for c in root]}', '']
    layout = root.find('.//WebLayout') or root.find('Layout')
    if layout is None:
        out += ['no layout element; first 600 chars:', '```xml', xml[:600], '```', '']
        continue
    out += [f'layout element: `{layout.tag}` attrs {dict(layout.attrib)}', '']

    def walk(el, depth):
        for child in el:
            a = {k: v for k, v in child.attrib.items() if k not in ('Label', 'FieldName', 'Type', 'Margin', 'Padding')}
            if child.tag == 'Control':
                out.append('  ' * depth + f"- `{child.get('FieldName') or child.get('Type')}` \"{child.get('Label')}\" Type={child.get('Type')} {a}")
            else:
                out.append('  ' * depth + f"- {child.tag} \"{child.get('Label') or ''}\" {a}")
                walk(child, depth + 1)

    walk(layout, 0)
    out.append('')
    tabs = [t.get('Label') for t in layout.iter('Tab')]
    print('  tabs:', tabs, '| groups:', len(list(layout.iter('Group'))), '| controls:', len(list(layout.iter('Control'))),
          '| types:', sorted({c.get('Type') for c in layout.iter('Control')}))
    if (project, tname) == ('DevOps Mobile App', 'Bug'):
        out += ['raw (first 3000 chars):', '```xml', xml[:3000], '```', '']
    print('  pages:', [p.get('Label') for p in layout.findall('Page')],
          '| groups:', sum(len(s.findall('Group')) for p in layout.findall('Page') for s in p.findall('Section')),
          '| controls:', len(list(layout.iter('Control'))))

out.append(dump_costs())
write_result('s26_xmlform_layout.md', '\n'.join(out))
