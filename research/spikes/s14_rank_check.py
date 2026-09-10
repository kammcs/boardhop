"""s14: read-only check of board rank fields on the scratch stories (used while
verifying the app's reorder write). Prints StackRank / BacklogPriority and the WIQL
order the app relies on."""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, post  # noqa: E402

P = urllib.parse.quote('DevOps Mobile App')
API = 'api-version=7.1'
ids = [15506, 15507]
s, h, r = get(f'{ORG_URL}/{P}/_apis/wit/workitems?ids={",".join(map(str, ids))}&{API}')
for w in r['value']:
    f = w['fields']
    print(w['id'], 'StackRank=', f.get('Microsoft.VSTS.Common.StackRank'),
          'BacklogPriority=', f.get('Microsoft.VSTS.Common.BacklogPriority'),
          'Changed=', f.get('System.ChangedDate'), 'State=', f.get('System.State'))
for order in ['[Microsoft.VSTS.Common.StackRank] ASC', '[Microsoft.VSTS.Common.BacklogPriority] ASC']:
    q = f"SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.WorkItemType] = 'User Story' ORDER BY {order}"
    s, h, r = post(f'{ORG_URL}/{P}/_apis/wit/wiql?{API}', {'query': q})
    print(order, '->', s, [w['id'] for w in r.get('workItems', [])] if s < 300 else str(r)[:200])
