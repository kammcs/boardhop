"""Shared helper for Boardhop spikes against an Azure DevOps Services org.

Credentials come only from environment variables set by the user:
  ADO_ORG_URL   e.g. https://dev.azure.com/puremedia
  ADO_PROJECT   default project name for project-scoped spikes
  ADO_PAT       a personal access token (read scopes are enough for the read-only spikes)

The PAT is never written to disk or printed; every response body is redacted before
being echoed into a results file.
"""
import base64, json, os, sys, time, urllib.request, urllib.error, urllib.parse

ORG_URL = os.environ.get('ADO_ORG_URL', '').rstrip('/')
DEFAULT_PROJECT = os.environ.get('ADO_PROJECT')
_PAT = os.environ.get('ADO_PAT')
if not (ORG_URL and DEFAULT_PROJECT and _PAT):
    sys.exit('Set ADO_ORG_URL, ADO_PROJECT and ADO_PAT in the environment before running a spike.')
ORG = ORG_URL.rsplit('/', 1)[-1]
_AUTH = 'Basic ' + base64.b64encode((':' + _PAT).encode()).decode()

COST_LOG = []  # (method, url, status, cost, delay, seconds)


def redact(s):
    return s.replace(_PAT, '<PAT>') if isinstance(s, str) else s


def call(method, url, body=None, headers=None, raw=False):
    h = {'Authorization': _AUTH, 'Accept': 'application/json'}
    if headers:
        h.update(headers)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        h.setdefault('Content-Type', 'application/json')
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    t0 = time.time()
    try:
        resp = urllib.request.urlopen(req)
        status, hdrs, payload = resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e:
        status, hdrs, payload = e.code, dict(e.headers), e.read()
    dt = time.time() - t0
    COST_LOG.append((method, redact(url), status, hdrs.get('X-RateLimit-Cost'), hdrs.get('X-RateLimit-Delay'), round(dt, 2)))
    text = payload.decode('utf-8', 'replace')
    if raw:
        return status, hdrs, text
    try:
        return status, hdrs, json.loads(text) if 'json' in hdrs.get('Content-Type', '') else text
    except json.JSONDecodeError:
        return status, hdrs, text


def get(url, **kw):
    return call('GET', url, **kw)


def post(url, body, **kw):
    return call('POST', url, body, **kw)


def patch(url, body, **kw):
    kw.setdefault('headers', {})['Content-Type'] = 'application/json-patch+json'
    return call('PATCH', url, body, **kw)


def dump_costs(title='Rate-limit cost log'):
    lines = [f'\n### {title}', '', '| method | url | status | X-RateLimit-Cost | X-RateLimit-Delay | seconds |', '|---|---|---|---|---|---|']
    total = 0.0
    for m, u, s, c, d, t in COST_LOG:
        lines.append(f'| {m} | `{u.replace(ORG_URL, "{org}")}` | {s} | {c} | {d} | {t} |')
        if c:
            total += float(c)
    lines.append(f'\nTotal TSTU for this script: **{total:.4f}**')
    return '\n'.join(lines)


def write_result(name, md):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results', name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(redact(md))
    print('wrote', path)


def short(obj, n=1500):
    s = json.dumps(obj, indent=1) if not isinstance(obj, str) else obj
    return redact(s[:n] + ('\n…(truncated)' if len(s) > n else ''))
