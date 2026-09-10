"""Run one or more spike scripts with credentials loaded from the AzureDevOps MCP server entry
in ~/.claude.json (authorized by Kelly on 2026-09-10). Credentials go only into the child
process environment; nothing is printed or written.

Usage: python _run_with_mcp_creds.py s05_multiline_format.py [more scripts...]
"""
import json, os, subprocess, sys

cfg = json.load(open(os.path.expanduser('~/.claude.json'), encoding='utf-8'))
env = cfg['mcpServers']['AzureDevOps']['env']
child = dict(os.environ, ADO_ORG_URL=env['AZURE_DEVOPS_ORG_URL'],
             ADO_PROJECT=env['AZURE_DEVOPS_DEFAULT_PROJECT'], ADO_PAT=env['AZURE_DEVOPS_PAT'])
here = os.path.dirname(os.path.abspath(__file__))
for name in sys.argv[1:]:
    r = subprocess.run([sys.executable, os.path.join(here, name)], env=child, capture_output=True, text=True)
    print(f'{name:36s} {"ok" if r.returncode == 0 else "FAILED (" + str(r.returncode) + ")"}')
    if r.returncode != 0:
        print(r.stdout[-800:], r.stderr[-800:])
