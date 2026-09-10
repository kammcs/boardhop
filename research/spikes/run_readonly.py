"""Run every read-only spike in order and print a one-line status per script."""
import os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
scripts = ['s02_pat_profile_accounts.py', 's04_org_level_pr_list.py', 's05_multiline_format.py',
           's06_suggestion_wire_format.py', 's09_activity_poll_cost.py', 's10_board_schema_and_wef.py',
           's11_workitem_type_fields.py']
for name in scripts:
    r = subprocess.run([sys.executable, os.path.join(here, name)], capture_output=True, text=True)
    status = 'ok' if r.returncode == 0 else f'FAILED ({r.returncode})'
    print(f'{name:36s} {status}')
    if r.returncode != 0:
        print(r.stdout[-800:], r.stderr[-800:])
