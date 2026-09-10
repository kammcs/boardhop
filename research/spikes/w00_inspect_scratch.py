"""Read-only look at the scratch project before any write spike runs."""
from lib import *
SCRATCH = 'DevOps Mobile App'
P = urllib.parse.quote(SCRATCH)
out = [f'# Scratch project inspection — {SCRATCH}', f'Org: {ORG_URL}', '']
s, h, proj = get(f'{ORG_URL}/_apis/projects/{P}?includeCapabilities=true&api-version=7.1')
out += [f'## project — HTTP {s}', '```json', short({k: proj.get(k) for k in ['id','name','state','visibility','capabilities','lastUpdateTime']} if isinstance(proj, dict) else proj, 900), '```']
s, h, props = get(f'{ORG_URL}/_apis/projects/{proj["id"]}/properties?api-version=7.1-preview.1') if isinstance(proj, dict) else (0, {}, None)
out += [f'## project properties — HTTP {s}', '```json', short(props, 900), '```']
s, h, teams = get(f'{ORG_URL}/_apis/projects/{P}/teams?api-version=7.1')
out += [f'## teams — HTTP {s}: {[t["name"] for t in teams.get("value", [])] if isinstance(teams, dict) else teams}']
team = teams['value'][0]['name'] if isinstance(teams, dict) and teams.get('value') else None
T = urllib.parse.quote(team) if team else ''
s, h, types = get(f'{ORG_URL}/{P}/_apis/wit/workitemtypes?api-version=7.1')
out += [f'## work item types — HTTP {s}', ', '.join(f'{t["name"]} {[x["name"] for x in t.get("states", [])]}' for t in types.get('value', [])) if isinstance(types, dict) else str(types)]
s, h, bc = get(f'{ORG_URL}/{P}/{T}/_apis/work/backlogconfiguration?api-version=7.1')
out += [f'## backlogconfiguration — HTTP {s}', f'bugsBehavior: {bc.get("bugsBehavior") if isinstance(bc, dict) else bc}', f'requirement backlog types: {[t["name"] for t in bc.get("requirementBacklog", {}).get("workItemTypes", [])] if isinstance(bc, dict) else ""}']
s, h, boards = get(f'{ORG_URL}/{P}/{T}/_apis/work/boards?api-version=7.1')
out += [f'## boards — HTTP {s}: {[b["name"] for b in boards.get("value", [])] if isinstance(boards, dict) else boards}']
for b in boards.get('value', [])[:1] if isinstance(boards, dict) else []:
    s, h, board = get(f'{ORG_URL}/{P}/{T}/_apis/work/boards/{b["id"]}?api-version=7.1')
    out += [f'### board {b["name"]} — canEdit={board.get("canEdit")} isValid={board.get("isValid")}', f'fields: `{ {k: v["referenceName"] for k, v in board.get("fields", {}).items()} }`',
            'columns: ' + ', '.join(f'{c["name"]}({c["columnType"]}, split={c.get("isSplit")}, {c.get("stateMappings")})' for c in board.get('columns', [])),
            f'rows: {[(r["name"]) for r in board.get("rows", [])]}']
s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1')
out += [f'## repos — HTTP {s}: {[(r["name"], r.get("size"), r.get("defaultBranch")) for r in repos.get("value", [])] if isinstance(repos, dict) else repos}']
s, h, q = post(f'{ORG_URL}/{P}/_apis/wit/wiql?api-version=7.1', {'query': 'SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject]=@project'})
out += [f'## existing work items — HTTP {s}: {len(q.get("workItems", [])) if isinstance(q, dict) else q}']
s, h, iters = get(f'{ORG_URL}/{P}/{T}/_apis/work/teamsettings/iterations?api-version=7.1')
out += [f'## iterations — HTTP {s}: {[(i["name"], i.get("attributes", {}).get("timeFrame")) for i in iters.get("value", [])] if isinstance(iters, dict) else iters}']
s, h, hooks = get(f'{ORG_URL}/_apis/hooks/subscriptions?api-version=7.1')
out += [f'## service hook subscriptions visible — HTTP {s}: {hooks.get("count") if isinstance(hooks, dict) else hooks}']
out.append(dump_costs())
write_result('w00_inspect_scratch.md', '\n'.join(out))
