"""w01: create HTML and Markdown work items, read the format map back, convert HTML to Markdown,
try to revert (expect refusal), edit a Markdown field without the format op, and exercise the
preview Comments API with markdown plus renderedText.
"""
from scratch import *

out = ['# w01 — Markdown round-trip (scratch project)', f'Project: {SCRATCH}', '']

s, h, a = wi_create('Task', [
    {'op': 'add', 'path': '/fields/System.Title', 'value': '[spike] w01 HTML description'},
    {'op': 'add', 'path': '/fields/System.Description', 'value': '<p>Hello <b>bold</b> and <i>italic</i></p><ul><li>one</li><li>two</li></ul>'}])
out += [f'## A: create Task with HTML description — HTTP {s}', '```json', short(fmt(a)), '```']

s, h, b = wi_create('Task', [
    {'op': 'add', 'path': '/fields/System.Title', 'value': '[spike] w01 Markdown description'},
    {'op': 'add', 'path': '/fields/System.Description', 'value': '# Heading\n\nHello **bold** and _italic_\n\n- one\n- two\n\n```ts\nconst x = 1;\n```'},
    {'op': 'add', 'path': '/multilineFieldsFormat/System.Description', 'value': 'Markdown'}])
out += [f'## B: create Task with Markdown description via /multilineFieldsFormat — HTTP {s}', '```json', short(fmt(b) if isinstance(b, dict) else b), '```']

if isinstance(a, dict) and isinstance(b, dict) and 'id' in a and 'id' in b:
    for label, w in [('A', a), ('B', b)]:
        s, h, r = wi_get(w['id'])
        out += [f'## read back {label} (#{w["id"]}) — HTTP {s}', '```json', short(fmt(r)), '```']

    s, h, r = wi_patch(a['id'], [
        {'op': 'test', 'path': '/rev', 'value': a['rev']},
        {'op': 'add', 'path': '/fields/System.Description', 'value': 'Converted to **Markdown**\n\n- one\n- two'},
        {'op': 'add', 'path': '/multilineFieldsFormat/System.Description', 'value': 'Markdown'}])
    out += [f'## convert A to Markdown — HTTP {s}', '```json', short(fmt(r) if isinstance(r, dict) else r, 600), '```']

    s, h, r2 = wi_patch(a['id'], [
        {'op': 'add', 'path': '/fields/System.Description', 'value': '<p>back to html?</p>'},
        {'op': 'add', 'path': '/multilineFieldsFormat/System.Description', 'value': 'Html'}])
    out += [f'## attempt to revert A to HTML — HTTP {s}', '```json', short(fmt(r2) if isinstance(r2, dict) else r2, 600), '```']

    s, h, r3 = wi_patch(b['id'], [
        {'op': 'add', 'path': '/fields/System.Description', 'value': 'Edited without format op\n\n- still markdown?'}])
    out += [f'## edit B description without a format op — HTTP {s}', '```json', short(fmt(r3) if isinstance(r3, dict) else r3, 600), '```']

    s, h, c = post(f'{ORG_URL}/{P}/_apis/wit/workItems/{a["id"]}/comments?format=markdown&api-version=7.1-preview.4',
                   {'text': 'A **markdown** comment from the spike with `code`'})
    out += [f'## add comment (7.1-preview.4, format=markdown) — HTTP {s}', '```json',
            short({k: c.get(k) for k in ['id', 'format', 'text', 'renderedText']} if isinstance(c, dict) else c, 600), '```']
    s, h, cl = get(f'{ORG_URL}/{P}/_apis/wit/workItems/{a["id"]}/comments?$expand=renderedText&api-version=7.1-preview.4')
    out += [f'## list comments with $expand=renderedText — HTTP {s}', '```json',
            short([{k: x.get(k) for k in ['id', 'format', 'text', 'renderedText']} for x in cl.get('comments', [])] if isinstance(cl, dict) else cl, 800), '```']
    out.append(f'\nWork items left in place for inspection: #{a["id"]}, #{b["id"]}')

out.append(dump_costs())
write_result('w01_markdown_roundtrip.md', '\n'.join(out))
