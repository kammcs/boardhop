"""s37 (read-only): the exact relation URLs Azure DevOps echoes back, to see
whether they match what the app sent (the phase 5 rebase compares rel+url).
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs  # noqa: E402

P = urllib.parse.quote('DevOps Mobile App')
for wid in [int(a) for a in sys.argv[1:] if a.isdigit()] or [15553]:
    s, h, w = get(f'{ORG_URL}/{P}/_apis/wit/workitems/{wid}?$expand=all&api-version=7.1')
    print(f'#{wid} HTTP {s} rev {w.get("rev")}')
    for i, r in enumerate(w.get('relations') or []):
        print(f'   [{i}] {r.get("rel")}')
        print(f'       {r.get("url")}')
    desc = ((w.get('fields') or {}).get('System.Description') or '')
    print('   description:', desc[:300])
dump_costs()
