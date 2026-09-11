"""s16: read-only probe behind the organization and project tiles.

Findings (2026-09-11), all reproduced by `lib/core/util/ado_tiles.dart`:
* The web's project tile is `{org}/_apis/GraphProfile/MemberAvatars/
  {defaultTeamId}?overrideDisplayName={project}&size=2`: the default team's
  picture when one is set, otherwise a PNG the service generates from the
  override name. `projects/{id}/avatar` has no GET; the vssps Graph
  `Subjects/{descriptor}/avatars` route ignores `overrideDisplayName` (it
  returns the team's own initials) and rejects `scp.` project descriptors.
* Generated color = .NET Framework `string.GetHashCode()` of the name,
  absolute, modulo a 12-entry palette (verified on 70+ names, Unicode
  included); initials = first letter of first and last word after digits and
  punctuation are stripped, with parentheses handling checked separately.
* Organizations have no service-side image (`MemberAvatars/{accountId}` and
  `/{instanceId}` 404; `identityImage` returns a placeholder SVG); the web
  draws them client-side, so the app uses the azure-devops-ui Coin scheme.
* The default team id is only on the single-project GET (`defaultTeam.id`),
  not on the list.

Prints statuses, sizes and colors only. Sample PNGs go to $SPIKE_OUT when set
(a scratchpad), never to results/."""
import base64, os, struct, sys, urllib.parse, urllib.request, zlib

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import ORG_URL, ORG, get  # noqa: E402

VSSPS = f'https://vssps.dev.azure.com/{ORG}'
OUT = os.environ.get('SPIKE_OUT')
M32 = 0xFFFFFFFF
PALETTE = ['#da3a00', '#aa0000', '#5d005d', '#32105c', '#001e51', '#004b51',
           '#004c1a', '#b600a0', '#5c2893', '#0075da', '#008272', '#027d00']


def net_hash(s):
    h1 = h2 = 5381
    cs = [ord(c) for c in s]
    for i in range(0, len(cs), 2):
        h1 = (((h1 << 5) + h1) ^ cs[i]) & M32
        if i + 1 < len(cs):
            h2 = (((h2 << 5) + h2) ^ cs[i + 1]) & M32
    v = (h1 + h2 * 1566083941) & M32
    return v - (1 << 32) if v & 0x80000000 else v


def predicted(name):
    return PALETTE[abs(net_hash(name)) % 12]


def raw(url):
    req = urllib.request.Request(url, headers={'Authorization': lib._AUTH})
    try:
        r = urllib.request.urlopen(req)
        return r.status, r.headers.get('Content-Type'), r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get('Content-Type'), e.read()


def background(png):
    """First pixel of the first row is the raw value under every PNG filter."""
    pos, idat, plte, ctype = 8, b'', None, None
    while pos < len(png):
        n, = struct.unpack('>I', png[pos:pos + 4])
        tag, data = png[pos + 4:pos + 8], png[pos + 8:pos + 8 + n]
        if tag == b'IHDR':
            ctype = data[9]
        elif tag == b'PLTE':
            plte = data
        elif tag == b'IDAT':
            idat += data
        pos += 12 + n
    row = zlib.decompress(idat)
    if ctype == 3:
        i = row[1]
        return '#%02x%02x%02x' % tuple(plte[3 * i:3 * i + 3])
    return '#%02x%02x%02x' % tuple(row[1:4])


s, h, projects = get(f'{ORG_URL}/_apis/projects?api-version=7.1')
print('projects:', s, projects.get('count'))
team = None
for p in projects.get('value', []):
    s, h, single = get(f'{ORG_URL}/_apis/projects/{p["id"]}?api-version=7.1')
    team = (single.get('defaultTeam') or {}).get('id')
    print(f'\n[{p["name"]}] defaultTeam via single GET: {team}')
    if not team:
        continue
    url = (f'{ORG_URL}/_apis/GraphProfile/MemberAvatars/{team}'
           f'?overrideDisplayName={urllib.parse.quote(p["name"])}&size=2')
    s, ct, png = raw(url)
    color = background(png) if s == 200 else None
    print(f'   tile: {s} {ct} {len(png)} bytes, background {color}, predicted {predicted(p["name"])}')
    if OUT and s == 200:
        open(os.path.join(OUT, 'tile_' + p['name'].replace(' ', '_') + '.png'), 'wb').write(png)
    s, h, d = get(f'{VSSPS}/_apis/graph/descriptors/{p["id"]}?api-version=7.1-preview.1')
    desc = d.get('value') if isinstance(d, dict) else None
    s2, _, _ = get(f'{VSSPS}/_apis/graph/Subjects/{desc}/avatars?size=large&api-version=7.1-preview.1')
    print(f'   graph Subjects on project descriptor {desc}: {s2} (400 = unsupported)')

# hash verification on names the org does not have
if team:
    mismatches = 0
    for name in ['Boardhop Team', 'Émile Zola', 'CloudCover IoT, Inc.', 'x (y) z', '한글 이름', 'Team 42', 'A', 'H', 'Aa']:
        s, ct, png = raw(f'{ORG_URL}/_apis/GraphProfile/MemberAvatars/{team}'
                         f'?overrideDisplayName={urllib.parse.quote(name)}&size=0')
        actual = background(png) if s == 200 else None
        ok = actual == predicted(name)
        mismatches += not ok
        print(f'{name!r:26} actual {actual} predicted {predicted(name)} {"OK" if ok else "MISMATCH"}')
    print('hash mismatches:', mismatches)

# organizations: nothing server-side
s, h, conn = get(f'{ORG_URL}/_apis/connectionData?api-version=7.1-preview.1')
inst = conn.get('instanceId') if isinstance(conn, dict) else None
for url in (f'{ORG_URL}/_apis/GraphProfile/MemberAvatars/{inst}?size=2',
            f'{ORG_URL}/_api/_common/identityImage?id={inst}&size=2'):
    s, ct, b = raw(url)
    print('org:', s, ct, len(b), url.replace(ORG_URL, '{org}'))
