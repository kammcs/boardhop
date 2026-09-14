"""s47 (read-only): does `vssps identities?identityIds={guid}` and `identities/{guid}` answer for
the PAT's own identity id, and with what shape? Feeds PeopleRepository.identityById (research/16 M9)."""
import json, os, sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, dump_costs, write_result  # noqa: E402

VSSPS = f'https://vssps.dev.azure.com/{ORG}'
out = []
st, _, me = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
mid = me['authenticatedUser']['id'] if st == 200 else None
out.append(f'connectionData {st}; have id: {bool(mid)}')
def keys(o):
    return sorted(o.keys()) if isinstance(o, dict) else type(o).__name__
def props(o):
    p = o.get('properties') if isinstance(o, dict) else None
    return sorted(p.keys()) if isinstance(p, dict) else None
for label, url in [
    ('batch', f'{VSSPS}/_apis/identities?identityIds={mid}&api-version=7.1-preview.1'),
    ('batch+props', f'{VSSPS}/_apis/identities?identityIds={mid}&queryMembership=None&api-version=7.1-preview.1'),
    ('single', f'{VSSPS}/_apis/identities/{mid}?api-version=7.1-preview.1'),
    ('batch-ga', f'{VSSPS}/_apis/identities?identityIds={mid}&api-version=7.1'),
]:
    st, _, body = get(url)
    rows = body.get('value') if isinstance(body, dict) and 'value' in body else body
    first = rows[0] if isinstance(rows, list) and rows else rows
    out.append(f'{label}: {st} count={len(rows) if isinstance(rows, list) else "-"} keys={keys(first)} props={props(first)}')
    if isinstance(first, dict):
        out.append(f'  id matches: {first.get("id") == mid}; providerDisplayName set: {bool(first.get("providerDisplayName"))}; customDisplayName set: {bool(first.get("customDisplayName"))}; subjectDescriptor set: {bool(first.get("subjectDescriptor"))}; descriptor set: {bool(first.get("descriptor"))}')
        p = first.get('properties') or {}
        out.append(f'  properties.Mail: {"Mail" in p}; Account: {"Account" in p}; shape of one: {type(next(iter(p.values()), None)).__name__}')
md = '# s47 identity by id\n\n' + '\n'.join(out) + '\n\n' + dump_costs()
print('\n'.join(out))
write_result('s47_identity_by_id', md)
