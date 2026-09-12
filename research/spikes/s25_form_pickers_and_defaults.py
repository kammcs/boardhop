"""s25: everything the create form's pickers and defaults need. Read-only,
for CloudCover 2.0 and the scratch project: classification nodes (areas,
iterations), the default team's field values and current iteration, tags,
team templates, backlog configuration (type roles, bugs behavior, backlog
field names), hidden type categories, each type's initial transitions and
the Assigned To allowed values. Prints shapes and counts only."""
import json, os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402

PROJECTS = ['CloudCover 2.0', 'DevOps Mobile App']
out = ['# Spike s25 — form pickers and defaults', '']


def count_nodes(node):
    return 1 + sum(count_nodes(c) for c in (node.get('children') or []))


def depth(node, d=1):
    return max([d] + [depth(c, d + 1) for c in (node.get('children') or [])])


for project in PROJECTS:
    P = urllib.parse.quote(project)
    out += [f'# Project: {project}', '']
    s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?api-version=7.1')
    team = (proj.get('defaultTeam') or {}).get('name')
    T = urllib.parse.quote(team or '')
    print(f'\n{project}: default team {team!r}')
    out += [f'default team: **{team}**', '']

    for kind in ('areas', 'iterations'):
        s, h, tree = get(f'{ORG_URL}/{P}/_apis/wit/classificationnodes/{kind}?$depth=10&api-version=7.1')
        if isinstance(tree, dict) and 'name' in tree:
            n, d = count_nodes(tree), depth(tree)
            keys = sorted(tree.keys())
            first_child = (tree.get('children') or [None])[0]
            print(f'  {kind}: {s} nodes={n} depth={d}')
            out += [f'## classificationnodes/{kind}?$depth=10 — HTTP {s}: {n} nodes, depth {d}', '',
                    'node keys: ' + ', '.join(keys), '',
                    'first child: ' + json.dumps({k: v for k, v in (first_child or {}).items() if k != 'children'}, default=str)[:500], '']
        else:
            print(f'  {kind}: {s}', str(tree)[:200])
            out += [f'## classificationnodes/{kind} — HTTP {s}', '```', short(tree, 500), '```', '']

    s, h, tfv = get(f'{ORG_URL}/{P}/{T}/_apis/work/teamsettings/teamfieldvalues?api-version=7.1')
    print('  teamfieldvalues:', s, tfv.get('defaultValue') if isinstance(tfv, dict) else str(tfv)[:120])
    out += [f'## teamsettings/teamfieldvalues — HTTP {s}', '```json', short(tfv, 600), '```', '']

    s, h, its = get(f'{ORG_URL}/{P}/{T}/_apis/work/teamsettings/iterations?$timeframe=current&api-version=7.1')
    cur = (its.get('value') or [None])[0] if isinstance(its, dict) else None
    print('  current iteration:', s, cur and cur.get('path'), cur and cur.get('attributes'))
    out += [f'## teamsettings/iterations?$timeframe=current — HTTP {s}, count {its.get("count") if isinstance(its, dict) else "?"}', '```json', short(cur or its, 500), '```', '']
    s, h, ts = get(f'{ORG_URL}/{P}/{T}/_apis/work/teamsettings?api-version=7.1')
    print('  teamsettings:', s, {k: ts.get(k) for k in ('backlogIteration', 'defaultIteration', 'defaultIterationMacro', 'bugsBehavior')} if isinstance(ts, dict) else '')
    out += [f'## teamsettings — HTTP {s}', '```json', short({k: ts.get(k) for k in ('backlogIteration', 'defaultIteration', 'defaultIterationMacro', 'bugsBehavior', 'workingDays')} if isinstance(ts, dict) else ts, 700), '```', '']

    s, h, tags = get(f'{ORG_URL}/{P}/_apis/wit/tags?api-version=7.1-preview.1')
    print('  tags:', s, tags.get('count') if isinstance(tags, dict) else str(tags)[:120])
    out += [f'## wit/tags (7.1-preview.1) — HTTP {s}, count {tags.get("count") if isinstance(tags, dict) else "?"}', '',
            'first: ' + json.dumps((tags.get('value') or [None])[0] if isinstance(tags, dict) else None)[:300], '']

    s, h, tpl = get(f'{ORG_URL}/{P}/{T}/_apis/wit/templates?api-version=7.1')
    print('  templates:', s, tpl.get('count') if isinstance(tpl, dict) else str(tpl)[:120])
    out += [f'## {{team}}/wit/templates — HTTP {s}, count {tpl.get("count") if isinstance(tpl, dict) else "?"}', '']
    for t in (tpl.get('value') or []) if isinstance(tpl, dict) else []:
        out.append(f"- {t.get('name')} ({t.get('workItemTypeName')}): fields {json.dumps(t.get('fields'))[:300]}")
    out.append('')

    s, h, bc = get(f'{ORG_URL}/{P}/{T}/_apis/work/backlogconfiguration?api-version=7.1')
    if isinstance(bc, dict):
        levels = [(b.get('name'), b.get('id'), [w.get('name') for w in b.get('workItemTypes') or []], b.get('isHidden')) for b in (bc.get('portfolioBacklogs') or []) + [bc.get('requirementBacklog') or {}, bc.get('taskBacklog') or {}]]
        print('  backlogconfiguration:', s, levels, 'bugs', bc.get('bugsBehavior'))
        out += [f'## backlogconfiguration — HTTP {s}', '', f'bugsBehavior: `{bc.get("bugsBehavior")}`', '',
                'levels (top-down): ' + json.dumps(levels), '',
                'hiddenBacklogs: ' + json.dumps(bc.get('hiddenBacklogs'))[:400], '',
                'backlogFields.typeFields: ' + json.dumps(bc.get('backlogFields', {}).get('typeFields')), '',
                'workItemTypeMappedStates: ' + json.dumps(bc.get('workItemTypeMappedStates'))[:900], '']
    else:
        out += [f'## backlogconfiguration — HTTP {s}', '```', short(bc, 400), '```', '']

    s, h, cats = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypecategories?api-version=7.1')
    if isinstance(cats, dict):
        cat = {c['referenceName']: [w.get('name') for w in c.get('workItemTypes') or []] for c in cats.get('value', [])}
        print('  categories:', s, {k: v for k, v in cat.items() if 'Hidden' in k})
        out += [f'## workitemtypecategories — HTTP {s}', '```json', json.dumps(cat, indent=1), '```', '']

    s, h, wits = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes?api-version=7.1')
    names = [w['name'] for w in wits.get('value', []) if not w.get('isDisabled')] if isinstance(wits, dict) else []
    out += [f'## initial transitions per type (`transitions[""]`) — {len(names)} types', '', '| type | states a new item may start in | keys |', '|---|---|---|']
    for w in (wits.get('value') or []) if isinstance(wits, dict) else []:
        tr = (w.get('transitions') or {}).get('')
        out.append(f"| {w['name']} | {json.dumps([t.get('to') for t in tr or []])} | {sorted(w.keys())} |" if w is wits['value'][0] else f"| {w['name']} | {json.dumps([t.get('to') for t in tr or []])} | |")
    out.append('')
    print('  types:', s, len(names))

    for tname in ('Task', 'User Story', 'Bug'):
        if tname not in names:
            continue
        s, h, f = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/{urllib.parse.quote(tname)}/fields/System.AssignedTo?$expand=All&api-version=7.1')
        av = f.get('allowedValues') if isinstance(f, dict) else None
        print(f'  {tname} AssignedTo allowedValues:', s, len(av) if isinstance(av, list) else av, sorted(f.keys()) if isinstance(f, dict) else '')
        out += [f'## workitemtypes/{tname}/fields/System.AssignedTo?$expand=All — HTTP {s}', '',
                'keys: ' + ', '.join(sorted(f.keys())) if isinstance(f, dict) else str(f)[:200], '',
                f'allowedValues: {len(av) if isinstance(av, list) else av}; first: ' + json.dumps((av or [None])[0] if isinstance(av, list) else None)[:400], '',
                'isLimitedToAllowedValues: ' + str(f.get('isLimitedToAllowedValues') if isinstance(f, dict) else None), '']
        # people picker alternatives when allowedValues is empty
        pid = proj['id']
        s2, h2, teams = get(f'{ORG_URL}/_apis/projects/{pid}/teams?api-version=7.1')
        tcount = teams.get('count') if isinstance(teams, dict) else None
        tid = (teams.get('value') or [{}])[0].get('id') if isinstance(teams, dict) else None
        s3, h3, members = get(f'{ORG_URL}/_apis/projects/{pid}/teams/{tid}/members?api-version=7.1') if tid else (None, None, None)
        m0 = ((members.get('value') or [None])[0] if isinstance(members, dict) else None)
        print(f'  teams: {s2} {tcount}; first team members: {s3} {members.get("count") if isinstance(members, dict) else members}')
        out += [f'## people picker alternatives', '', f'- projects/{{id}}/teams — HTTP {s2}, {tcount} teams',
                f'- teams/{{id}}/members — HTTP {s3}, count {members.get("count") if isinstance(members, dict) else "?"}; first: ' + json.dumps(m0)[:400]]
        s4, h4, ids = get(f'{ORG_URL.replace("dev.azure.com", "vssps.dev.azure.com")}/_apis/identities?searchFilter=General&filterValue=kelly&queryMembership=None&api-version=7.1')
        i0 = ((ids.get('value') or [None])[0] if isinstance(ids, dict) else None)
        print('  identities search:', s4, ids.get('count') if isinstance(ids, dict) else str(ids)[:120])
        out += [f'- vssps identities?searchFilter=General&filterValue=kelly — HTTP {s4}, count {ids.get("count") if isinstance(ids, dict) else "?"}; first keys: ' + str(sorted(i0.keys()) if isinstance(i0, dict) else i0)[:300]
                + '; properties: ' + str(sorted((i0.get('properties') or {}).keys()) if isinstance(i0, dict) else '')[:300]]
        from lib import post
        s5, h5, sq = post(f'{ORG_URL.replace("dev.azure.com", "vssps.dev.azure.com")}/_apis/graph/subjectquery?api-version=7.1-preview.1',
                          {'query': 'kelly', 'subjectKind': ['User']})
        q0 = ((sq.get('value') or [None])[0] if isinstance(sq, dict) else None)
        print('  graph subjectquery:', s5, sq.get('count') if isinstance(sq, dict) else str(sq)[:120])
        out += [f'- vssps graph/subjectquery "kelly" — HTTP {s5}, count {sq.get("count") if isinstance(sq, dict) else "?"}; first keys: ' + str(sorted(q0.keys()) if isinstance(q0, dict) else q0)[:300], '']
        # project-scoped subject query (scopeDescriptor = the project's descriptor)
        s6, h6, pd = get(f'{ORG_URL.replace("dev.azure.com", "vssps.dev.azure.com")}/_apis/graph/descriptors/{pid}?api-version=7.1')
        scope = pd.get('value') if isinstance(pd, dict) else None
        s7, h7, sq2 = post(f'{ORG_URL.replace("dev.azure.com", "vssps.dev.azure.com")}/_apis/graph/subjectquery?api-version=7.1-preview.1',
                           {'query': 'a', 'subjectKind': ['User'], 'scopeDescriptor': scope}) if scope else (None, None, None)
        print('  project-scoped subjectquery:', s6, s7, sq2.get('count') if isinstance(sq2, dict) else str(sq2)[:120])
        out += [f'- project descriptor — HTTP {s6}; scoped subjectquery "a" — HTTP {s7}, count {sq2.get("count") if isinstance(sq2, dict) else "?"}', '']
        # one picklist and one field with dependents, for the control mapping
        s, h, pf = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes/{urllib.parse.quote(tname)}/fields?$expand=All&api-version=7.1')
        if isinstance(pf, dict):
            rows = pf.get('value', [])
            picks = [(r['referenceName'], r.get('allowedValues'), r.get('isLimitedToAllowedValues'), r.get('defaultValue')) for r in rows if r.get('allowedValues')]
            req = [r['referenceName'] for r in rows if r.get('alwaysRequired')]
            out += [f'### {tname} fields?$expand=All — HTTP {s}, {len(rows)} fields; keys {sorted(rows[0].keys()) if rows else []}', '',
                    'alwaysRequired: ' + json.dumps(req), '',
                    'picklists: ' + json.dumps(picks, default=str)[:1500], '']
        break

out.append(dump_costs())
write_result('s25_form_pickers_and_defaults.md', '\n'.join(out))
