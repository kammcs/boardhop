"""w26: research/14 §9 R2.8 — provision the beta's service-hook subscriptions.

A thin wrapper around `relay/tool/hooks.dart`: it reads `RELAY_ADMIN_SECRET` off
the relay box over ssh (exactly the way w24 reads the capture secret), pins the
write guard to the scratch project, and runs the Dart tool with the command in
`W26_ARGS`.

    W26_ARGS="plan --org puremedia --project 'DevOps Mobile App'" \
        python research/spikes/_run_with_mcp_creds.py w26_provision_hooks.py

    W26_ARGS="secret --org puremedia --out .hooks-secret-puremedia" ...
    W26_ARGS="create --org puremedia --project 'DevOps Mobile App' \
              --secret-file .hooks-secret-puremedia" ...
    W26_ARGS="list   --org puremedia" ...
    W26_ARGS="delete --org puremedia --project 'DevOps Mobile App'" ...

Hard rule 1: `HOOKS_ALLOW_PROJECT` is set to `DevOps Mobile App` here and the
Dart tool refuses to create or delete anything in any other project, before it
makes a single network call. Nothing else about the command is rewritten.

Neither secret is printed: the admin secret goes only into the child process
environment, and the tool itself prints no secret (the hook secret lands in the
file `secret --out` names, which `.gitignore` covers as `.hooks-secret-*`).
"""
import os
import shlex
import shutil
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import write_result  # noqa: E402

RELAY_HOST = os.environ.get('RELAY_HOST', 'deploy@boardhop.relay.kammcs.com')
SCRATCH = 'DevOps Mobile App'
HERE = os.path.dirname(os.path.abspath(__file__))
RELAY_DIR = os.path.normpath(os.path.join(HERE, '..', '..', 'relay'))


def admin_secret():
    """Read RELAY_ADMIN_SECRET off the box over ssh. Never printed or written."""
    r = subprocess.run(['ssh', RELAY_HOST, 'grep ^RELAY_ADMIN_SECRET= /srv/relay/relay.env'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('could not read the admin secret over ssh; is the deploy key loaded?')
    line = r.stdout.strip()
    if not line.startswith('RELAY_ADMIN_SECRET='):
        sys.exit('unexpected relay.env content')
    value = line.split('=', 1)[1].strip()
    if not value:
        sys.exit('RELAY_ADMIN_SECRET is empty on the box')
    return value


args = shlex.split(os.environ.get('W26_ARGS', 'plan --org puremedia --project "DevOps Mobile App"'))
if not args:
    sys.exit('set W26_ARGS to the hooks.dart command, e.g. "list --org puremedia"')

secret = admin_secret()
child = dict(os.environ,
             HOOKS_ALLOW_PROJECT=SCRATCH,
             RELAY_ADMIN_SECRET=secret,
             RELAY_URL=os.environ.get('RELAY_URL', 'https://boardhop.relay.kammcs.com'))

# Resolve `dart` ourselves: on Windows it may be a .bat, which CreateProcess
# will not find, and shell=True would mangle "DevOps Mobile App".
dart = shutil.which('dart') or shutil.which('dart.bat')
if not dart:
    sys.exit('dart is not on PATH; the relay tool needs the Dart SDK')
cmd = [dart, 'run', 'tool/hooks.dart', *args]
print('running: dart run tool/hooks.dart', ' '.join(shlex.quote(a) for a in args))
proc = subprocess.run(cmd, cwd=RELAY_DIR, env=child, capture_output=True, text=True, encoding='utf-8')


def clean(text):
    """Belt and braces: the tool prints no secret, but nothing echoes one anyway."""
    return (text or '').replace(secret, '<RELAY_ADMIN_SECRET>')


print(clean(proc.stdout))
if proc.returncode != 0:
    print(clean(proc.stderr), file=sys.stderr)

out = [f'# Spike w26 — hooks provisioning (`{" ".join(args)}`)', '',
       f'Ran `dart run tool/hooks.dart {" ".join(shlex.quote(a) for a in args)}` in `relay/` with',
       f'`HOOKS_ALLOW_PROJECT={SCRATCH}` and `RELAY_ADMIN_SECRET` read over ssh.', '',
       f'Exit code **{proc.returncode}**.', '', '## stdout', '', '```', clean(proc.stdout).rstrip(), '```', '']
if proc.returncode != 0:
    out += ['## stderr', '', '```', clean(proc.stderr).rstrip(), '```', '']

write_result('w26_provision_hooks.md', '\n'.join(out))
sys.exit(proc.returncode)
