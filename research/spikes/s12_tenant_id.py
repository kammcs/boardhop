"""Find the Entra tenant ID behind the puremedia org: Graph users carry the tenant ID as `domain` (aad origin)."""
from lib import *
import collections
out = ['# Spike 12 — Entra tenant behind the org', f'Org: {ORG_URL}', '']
s, h, users = get(f'https://vssps.dev.azure.com/{ORG}/_apis/graph/users?subjectTypes=aad&api-version=7.1-preview.1')
vals = users.get('value', []) if isinstance(users, dict) else []
doms = collections.Counter(u.get('domain') for u in vals)
out += [f'HTTP {s}; aad users: {len(vals)}', '| tenant id (domain) | users |', '|---|---|'] + [f'| {d} | {n} |' for d, n in doms.most_common()]
mine = [u for u in vals if u.get('principalName','').lower() == 'kkamm@cloudcover.it']
out.append(f'\nKelly\'s account: `{ {k: mine[0].get(k) for k in ["principalName","domain","origin","metaType"]} if mine else "not in list"}`')
s, h, cd = get(f'{ORG_URL}/_apis/connectionData')
out.append(f'connectionData authenticatedUser.properties: `{ {k: v.get("$value") if isinstance(v, dict) else v for k, v in cd["authenticatedUser"].get("properties", {}).items()} }`')
out.append(dump_costs())
write_result('s12_tenant_id.md', '\n'.join(out))
