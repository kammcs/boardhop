"""w27: scratch write. Assigns #15545 to the PAT identity (then, with
W27_MODE=unassign, clears it) so the live relay's wi.updated routing shows
whether a resourceVersion 1.0 body carries System.AssignedTo as an identity
object with an id (research/14 §1.1) or only as a "Name <mail>" string."""
import os, sys, time

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result  # noqa: E402
from scratch import wi_get, wi_patch  # noqa: E402

MODE = os.environ.get('W27_MODE', 'assign')
WID = 15545
out = [f'# Spike w27 — assignment trigger on #{WID} (mode `{MODE}`)', '']
s, h, cd = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview')
me = cd['authenticatedUser']
s, h, w = wi_get(WID)
if MODE == 'assign':
    value = f"{me['providerDisplayName']} <{me['properties']['Account']['$value']}>"
    ops = [{'op': 'test', 'path': '/rev', 'value': w['rev']},
           {'op': 'add', 'path': '/fields/System.AssignedTo', 'value': value}]
else:
    ops = [{'op': 'test', 'path': '/rev', 'value': w['rev']},
           {'op': 'remove', 'path': '/fields/System.AssignedTo'}]
s, h, upd = wi_patch(WID, ops)
print(MODE, 'HTTP', s, 'rev', upd.get('rev') if isinstance(upd, dict) else str(upd)[:200])
out.append(f'- {MODE} — HTTP {s}, rev {upd.get("rev") if isinstance(upd, dict) else "?"} at {time.strftime("%H:%M:%S")}')
out.append(dump_costs())
write_result('w27_assign_trigger.md', '\n'.join(out))
