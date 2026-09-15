"""s56 (read-only): `_apis/projects/{project}/teams`, for the sprint picker's
team switch (research/18 S8, P-C open item 1).

Two questions only:

  A  does the project-level teams route answer at api-version=7.1, and what
     shape (value[] of {id, name, description, …})?
  B  how many teams does each puremedia project have — i.e. does the
     picker's switch row ever appear here?

GETs only; nothing is written anywhere.
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result  # noqa: E402

API = 'api-version=7.1'
OUT = []


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def q(s):
    return urllib.parse.quote(str(s), safe='')


PROJECTS = [
    'DevOps Mobile App',
    'CloudCover 2.0',
    'Product',
    'Special Projects and AI',
]

p('=== A/B  _apis/projects/{project}/teams ===')
for project in PROJECTS:
    url = f'{ORG_URL}/_apis/projects/{q(project)}/teams?{API}'
    status, _hdrs, body = get(url)
    if status != 200 or not isinstance(body, dict):
        p(f'{project}: HTTP {status} {body}')
        continue
    teams = body.get('value') or []
    p(f'{project}: HTTP {status} count={body.get("count")} teams={len(teams)}')
    for t in teams:
        p('   ', t.get('id'), '|', t.get('name'), '| keys:', sorted(t.keys()))

dump_costs()
write_result('s56_project_teams.md', '\n'.join(OUT) + dump_costs())
