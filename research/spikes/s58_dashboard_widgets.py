"""s58 (read-only): the `settings` JSON of every widget on every puremedia
dashboard, redacted, plus the widget sub-resources and dashboard favorites
(NEXT-STEPS item 24, research/19).

Questions:

  A  what does each widget's `settings` string carry, per contributionId
     (keys and value types only; GUIDs and names replaced by placeholders)?
  B  do `dashboards/{id}/widgets` and `dashboards/{id}/widgets/{widgetId}`
     answer, at which api-version, and with which extra fields (eTag header)?
  C  does the project route `{project}/_apis/dashboard/dashboards/{id}` (no
     team segment) answer for a team dashboard?
  D  dashboard favorites: which artifactType string, and does the favorite
     carry a web `_links.page.href` (the deep-link form)?
  E  costs.

GETs only; nothing is written anywhere. Client project names, dashboard
names, query names and free text never reach the result file: only the
scratch project may be quoted.
"""
import json, os, re, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, get, dump_costs, write_result, short  # noqa: E402

OUT = []
SCRATCH = 'DevOps Mobile App'
API = 'api-version=7.1-preview.3'
GUID = re.compile(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')


def p(*a):
    line = ' '.join(str(x) for x in a)
    print(line)
    OUT.append(line)


def q(s):
    return urllib.parse.quote(str(s), safe='')


def shape(v, depth=0):
    """Redacted structural copy: keys kept, GUIDs -> <guid>, other strings ->
    '<str:N>' unless they look like enum-ish tokens (short, no spaces)."""
    if isinstance(v, dict):
        return {k: shape(x, depth + 1) for k, x in v.items()}
    if isinstance(v, list):
        return [shape(x, depth + 1) for x in v[:5]] + (['…'] if len(v) > 5 else [])
    if isinstance(v, str):
        if GUID.fullmatch(v):
            return '<guid>'
        if GUID.search(v):
            return GUID.sub('<guid>', v) if len(v) < 80 else f'<str:{len(v)}>'
        if re.fullmatch(r'[A-Za-z0-9_.:\-/]{0,40}', v) and not re.search(r'[a-z][A-Z]', v) is None:
            return v  # camelCase tokens (enum-like)
        if re.fullmatch(r'[A-Za-z0-9_.:\-/+]{0,40}', v):
            return v  # short tokens: field refs, ISO dates, numbers-as-strings, enum values
        return f'<str:{len(v)}>'
    return v


def widget_line(w, quote):
    name = w.get('name') if quote else '<name>'
    return (f"    widget id={'<guid>' if not quote else w.get('id')} name={name!r} "
            f"pos={w.get('position')} size={w.get('size')} contributionId={w.get('contributionId')} "
            f"typeId={w.get('typeId')} settingsVersion={w.get('settingsVersion')} eTag={w.get('eTag')} "
            f"isEnabled={w.get('isEnabled')} artifactId={'<guid>' if w.get('artifactId') else w.get('artifactId')} "
            f"configId={w.get('configurationContributionId')} loadingImageUrl={bool(w.get('loadingImageUrl'))} "
            f"allowedSizes={len(w.get('allowedSizes') or [])} lightbox={w.get('lightboxOptions')} "
            f"areSettingsBlockedForUser={w.get('areSettingsBlockedForUser')} keys={sorted(w.keys())}")


st, _, body = get(f'{ORG_URL}/_apis/projects?api-version=7.1')
projects = [(pr['id'], pr['name']) for pr in body.get('value', [])] if st == 200 else []

settings_by_cid = {}  # contributionId -> list of (project label, redacted settings)
raw_scratch = []

p('=== A  widgets and settings per dashboard ===')
for pid, pname in projects:
    quote = pname == SCRATCH
    label = pname if quote else f'<project {pid[:8]}>'
    st, _, body = get(f'{ORG_URL}/{q(pname)}/_apis/dashboard/dashboards?{API}')
    for d in (body.get('value') or []) if isinstance(body, dict) else []:
        did = d['id']
        # C: project route (no team segment) by id
        st_p, hdrs_p, full_p = get(f'{ORG_URL}/{q(pname)}/_apis/dashboard/dashboards/{did}?{API}')
        p(f'\n{label} dashboard {"<guid>" if not quote else did} name={d.get("name") if quote else "<name>"} scope={d.get("dashboardScope")} groupId={"set" if d.get("groupId") else None}')
        p(f'  C project-route GET by id: HTTP {st_p} ETag-header={hdrs_p.get("ETag")} widgets={len(full_p.get("widgets") or []) if isinstance(full_p, dict) else "-"}')
        team = d.get('groupId')
        if not team:
            continue
        st_t, hdrs_t, full = get(f'{ORG_URL}/{q(pname)}/{team}/_apis/dashboard/dashboards/{did}?{API}')
        p(f'  team-route GET by id: HTTP {st_t} ETag-header={hdrs_t.get("ETag")} body eTag={full.get("eTag") if isinstance(full, dict) else "-"} '
          f'description={"<str>" if full.get("description") else full.get("description")!r} refreshInterval={full.get("refreshInterval")} globalParametersConfig={full.get("globalParametersConfig")}')
        widgets = full.get('widgets') or []
        if quote:
            raw_scratch.append(full)
        # B: widgets sub-resource
        for api in ('7.1-preview.2', '7.1-preview.3', '7.1'):
            st_w, hdrs_w, wb = get(f'{ORG_URL}/{q(pname)}/{team}/_apis/dashboard/dashboards/{did}/widgets?api-version={api}')
            n = len(wb.get('value') or wb.get('widgets') or []) if isinstance(wb, dict) else '-'
            p(f'  B widgets list api-version={api}: HTTP {st_w} keys={sorted(wb.keys()) if isinstance(wb, dict) else "-"} n={n} ETag-header={hdrs_w.get("ETag")}')
        for w in widgets:
            p(widget_line(w, quote))
            s = w.get('settings')
            try:
                parsed = json.loads(s) if s else s
            except json.JSONDecodeError:
                parsed = f'<non-json:{len(s)}>'
            red = shape(parsed)
            settings_by_cid.setdefault(w.get('contributionId'), []).append((label, red, w.get('settingsVersion')))
            p('      settings(redacted):', json.dumps(red, sort_keys=True)[:1200])
        if widgets:
            w0 = widgets[0]
            st_1, hdrs_1, wb1 = get(f'{ORG_URL}/{q(pname)}/{team}/_apis/dashboard/dashboards/{did}/widgets/{w0["id"]}?api-version=7.1-preview.2')
            p(f'  B single widget GET: HTTP {st_1} keys={sorted(wb1.keys()) if isinstance(wb1, dict) else "-"} ETag-header={hdrs_1.get("ETag")} body eTag={wb1.get("eTag") if isinstance(wb1, dict) else "-"} dashboard-in-body={"dashboard" in wb1 if isinstance(wb1, dict) else "-"}')

p('\n=== A summary  settings shape per contributionId (redacted) ===')
for cid, rows in sorted(settings_by_cid.items()):
    p(f'\n{cid}  ({len(rows)} widget(s))')
    seen = set()
    for label, red, ver in rows:
        key = json.dumps(red, sort_keys=True)
        if key in seen:
            continue
        seen.add(key)
        p(f'  settingsVersion={ver}')
        p('  ' + json.dumps(red, indent=1, sort_keys=True).replace('\n', '\n  '))

p('\n=== D  dashboard favorites ===')
for at in ('Microsoft.TeamFoundation.Dashboards.Dashboard', 'Microsoft.TeamFoundation.Dashboard', 'Microsoft.VisualStudio.Dashboards.Dashboard'):
    st, _, body = get(f'{ORG_URL}/_apis/favorite/favorites?artifactType={at}&artifactScopeType=Project&api-version=7.1-preview.1')
    n = body.get('count') if isinstance(body, dict) else None
    p(f'  artifactType={at}: HTTP {st} count={n} {short(body, 300) if st != 200 else ""}')
    for f in (body.get('value') or []) if isinstance(body, dict) else []:
        p('    favorite keys:', sorted(f.keys()), 'artifactType=', f.get('artifactType'), 'scope=', f.get('artifactScope', {}).get('type'),
          'page-link=', GUID.sub('<guid>', re.sub(r'/[^/]+/_dashboards', '/<project>/_dashboards', f.get('_links', {}).get('page', {}).get('href', '') or '')),
          'props=', sorted((f.get('artifactProperties') or {}).keys()))
st, _, body = get(f'{ORG_URL}/_apis/favorite/favorites?api-version=7.1-preview.1')
types = {}
for f in (body.get('value') or []) if isinstance(body, dict) else []:
    types[f.get('artifactType')] = types.get(f.get('artifactType'), 0) + 1
p(f'  all favorites (no filter): HTTP {st} count={body.get("count") if isinstance(body, dict) else None} artifactTypes={types}')

p('\n=== scratch project dashboards, verbatim ===')
p(json.dumps(raw_scratch, indent=1))

write_result('s58_dashboard_widgets/s58_dashboard_widgets.md', '\n'.join(OUT) + dump_costs())
