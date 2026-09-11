"""s17: read-only look at everything a Repos tab would need: repository
fields, per-repo language metrics, favorites, branches with stats, tags,
commits, folder listing, file content, README, and code search. Prints
keys, counts and short values only; nothing is written to the service."""
import json, os, sys, urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ORG_URL, ORG, get, post  # noqa: E402

PROJECT = os.environ.get('SPIKE_PROJECT', 'CloudCover 2.0')
P = urllib.parse.quote(PROJECT)


def keys(d, n=40):
    return sorted(d.keys())[:n] if isinstance(d, dict) else type(d).__name__


s, h, repos = get(f'{ORG_URL}/{P}/_apis/git/repositories?api-version=7.1&includeLinks=true&includeAllUrls=true')
print('repositories:', s, repos.get('count'))
first = None
for r in repos.get('value', [])[:8]:
    print('  ', r['name'], '| default', r.get('defaultBranch'), '| size', r.get('size'), '| disabled', r.get('isDisabled'),
          '| fork', r.get('isFork'), '| keys', keys(r))
    if first is None and not r.get('isDisabled') and r.get('defaultBranch'):
        first = r
print('repo keys (full):', keys(first, 60))
rid, rname = first['id'], first['name']
branch = first['defaultBranch'].replace('refs/heads/', '')
base = f'{ORG_URL}/{P}/_apis/git/repositories/{rid}'

s, h, lang = get(f'{ORG_URL}/{P}/_apis/projectanalysis/languagemetrics?api-version=7.1-preview.1')
print('\nlanguagemetrics:', s, keys(lang))
if isinstance(lang, dict):
    for r in (lang.get('repositoryLanguageAnalytics') or [])[:5]:
        print('  ', r.get('name'), r.get('resultPhase'), [(l.get('name'), round(l.get('filesPercentage', 0), 1)) for l in (r.get('languageBreakdown') or [])[:4]])

s, h, fav = get(f'{ORG_URL}/_apis/Favorite/Favorites?artifactType=Microsoft.TeamFoundation.Git.Repository&artifactScopeType=Project&api-version=7.1-preview.1')
print('\nfavorites (repos):', s, keys(fav), (fav.get('count') if isinstance(fav, dict) else str(fav)[:120]))
for f in (fav.get('value') if isinstance(fav, dict) else []) or []:
    print('  ', f.get('artifactName'), f.get('artifactType'), f.get('artifactScopeType'), keys(f))
s, h, favall = get(f'{ORG_URL}/_apis/Favorite/Favorites?api-version=7.1-preview.1')
print('favorites (all):', s, favall.get('count') if isinstance(favall, dict) else str(favall)[:120],
      sorted({v.get('artifactType') for v in (favall.get('value') or [])}) if isinstance(favall, dict) else '')

s, h, refs = get(f'{base}/refs?filter=heads/&api-version=7.1&includeStatuses=true&latestStatusesOnly=true&$top=10')
print('\nbranches:', s, refs.get('count'), keys(refs.get('value', [{}])[0]) if refs.get('value') else '')
s, h, tags = get(f'{base}/refs?filter=tags/&api-version=7.1&peelTags=true&$top=5')
print('tags:', s, tags.get('count'), keys(tags.get('value', [{}])[0]) if tags.get('value') else '')
s, h, stats = get(f'{base}/stats/branches?api-version=7.1')
print('stats/branches:', s, stats.get('count'))
for b in (stats.get('value') or [])[:5]:
    c = b.get('commit') or {}
    print('  ', b.get('name'), 'ahead', b.get('aheadCount'), 'behind', b.get('behindCount'), 'base', b.get('isBaseVersion'),
          '| commit keys', keys(c), '| author', (c.get('author') or {}).get('name'), (c.get('author') or {}).get('date'))

s, h, commits = get(f'{base}/commits?searchCriteria.itemVersion.version={urllib.parse.quote(branch)}&searchCriteria.$top=5&api-version=7.1')
print('\ncommits:', s, commits.get('count'), keys(commits.get('value', [{}])[0]) if commits.get('value') else '')
cid = commits['value'][0]['commitId'] if commits.get('value') else None
if cid:
    s, h, commit = get(f'{base}/commits/{cid}?changeCount=10&api-version=7.1')
    print('commit:', s, keys(commit), 'changeCounts', commit.get('changeCounts'), 'parents', len(commit.get('parents') or []))
    s, h, changes = get(f'{base}/commits/{cid}/changes?top=5&api-version=7.1')
    print('commit changes:', s, changes.get('changeCounts'), [(c['item'].get('path'), c.get('changeType')) for c in (changes.get('changes') or [])[:5]])

s, h, items = get(f'{base}/items?scopePath=/&recursionLevel=OneLevel&includeContentMetadata=true&versionDescriptor.version={urllib.parse.quote(branch)}&versionDescriptor.versionType=branch&api-version=7.1')
print('\nroot items:', s, items.get('count'))
readme = None
for it in (items.get('value') or [])[:12]:
    print('  ', it.get('gitObjectType'), it.get('path'), '| keys', keys(it), '| meta', keys(it.get('contentMetadata') or {}))
    if it.get('path', '').lower() == '/readme.md':
        readme = it
if readme:
    s, h, text = get(f'{base}/items?path=/README.md&includeContent=true&versionDescriptor.version={urllib.parse.quote(branch)}&api-version=7.1', raw=True)
    print('README via includeContent:', s, h.get('Content-Type'), len(text), text[:80].replace('\n', ' '))
    s, h, text = get(f'{base}/items?path=/README.md&$format=text&versionDescriptor.version={urllib.parse.quote(branch)}&api-version=7.1', raw=True)
    print('README via $format=text:', s, h.get('Content-Type'), len(text))
else:
    print('no README.md at root of', rname)

s, h, search = post(f'https://almsearch.dev.azure.com/{ORG}/{P}/_apis/search/codesearchresults?api-version=7.1',
                    {'searchText': 'TODO', '$skip': 0, '$top': 3, 'filters': {'Repository': [rname]}, 'includeFacets': False})
print('\ncode search:', s, keys(search), search.get('count') if isinstance(search, dict) else str(search)[:160])
for r in (search.get('results') or [])[:3] if isinstance(search, dict) else []:
    print('  ', r.get('path'), r.get('repository', {}).get('name'), keys(r))
