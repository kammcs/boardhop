"""s36 (read-only): single-item reads of the phase 5 walkthrough items, to
compare a per-id read with the batch read (rev, ChangedDate, relations and
System.AttachedFileCount).
"""
import os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs  # noqa: E402

P = urllib.parse.quote('DevOps Mobile App')
for wid in [int(a) for a in sys.argv[1:] if a.isdigit()] or [15540, 15550]:
    s, h, w = get(f'{ORG_URL}/{P}/_apis/wit/workitems/{wid}?$expand=all&api-version=7.1')
    f = (w.get('fields') or {}) if isinstance(w, dict) else {}
    print(f'#{wid} HTTP {s} rev {w.get("rev")} changed {f.get("System.ChangedDate")}')
    print('   AttachedFileCount', f.get('System.AttachedFileCount'),
          '| RelatedLinkCount', f.get('System.RelatedLinkCount'),
          '| ExternalLinkCount', f.get('System.ExternalLinkCount'))
    for i, r in enumerate(w.get('relations') or []):
        print(f'   [{i}] {r.get("rel")} -> {(r.get("url") or "").rsplit("/", 1)[-1]} {r.get("attributes")}')
dump_costs()
