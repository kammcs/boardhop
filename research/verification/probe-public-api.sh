#!/usr/bin/env bash
# Anonymous probes against PUBLIC Azure DevOps projects to verify REST API shapes
# relevant to a mobile client. No credentials required. Requires curl + python3.
# Run: bash research/verification/probe-public-api.sh > research/verification/probe-results.txt
set -u
API="api-version=7.1"
ORG="dnceng-public"; PROJ="public"; REPO="dotnet-public-wiki"
B="https://dev.azure.com/$ORG/$PROJ/_apis"
G="$B/git/repositories/$REPO"
py() { python -c "$1"; }

section() { echo; echo "##### $1"; }

section "1. Unauthenticated call to profile API -> 302 to sign-in, advertises Bearer (Entra) + Basic (PAT)"
curl -s -o /dev/null -D - "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?$API" | grep -iE "^HTTP|^WWW-Authenticate|^Location" | cut -c1-160

section "2. Repos in public project"
curl -s "$G?$API" | py "import sys,json; d=json.load(sys.stdin); print(json.dumps({k:d[k] for k in ['id','name','defaultBranch','size','webUrl']}, indent=1))"

section "3. Work item types + states (custom inherited process; note non-standard states)"
curl -s "https://dev.azure.com/dnceng/public/_apis/wit/workitemtypes?$API" | py "import sys,json; d=json.load(sys.stdin); print('types:',d['count']); [print(' ',t['name'],'|',[s['name'] for s in t.get('states',[])]) for t in d['value'][:8]]"

section "4. Pull request list (status=all)"
curl -s "$G/pullrequests?searchCriteria.status=all&\$top=5&$API" | py "import sys,json; d=json.load(sys.stdin); [print(' ',p['pullRequestId'],p['status'],p['title'][:50],'|',p['sourceRefName'],'->',p['targetRefName'],'| reviewers',len(p.get('reviewers',[]))) for p in d['value']]"

section "5. PR detail: merge commits, completionOptions, reviewer votes, avatar links"
curl -s "$G/pullrequests/5?$API" | py "import sys,json; p=json.load(sys.stdin); print(json.dumps({k:p.get(k) for k in ['status','mergeStatus','isDraft','completionOptions','supportsIterations']},indent=1)); print(' lastMergeSourceCommit',p['lastMergeSourceCommit']['commitId'][:8],' lastMergeTargetCommit',p['lastMergeTargetCommit']['commitId'][:8]); [print(' reviewer',r['displayName'],'vote',r['vote'],'avatar',r['_links']['avatar']['href'][:70]) for r in p['reviewers']]"

section "6. PR iterations list -> requires auth even on a public project (302). Iteration CHANGES is anonymous."
curl -s -o /dev/null -w "iterations: HTTP %{http_code}\n" "$G/pullrequests/5/iterations?$API"
curl -s "$G/pullrequests/5/iterations/1/changes?$API" | py "import sys,json; d=json.load(sys.stdin); [print(' change',c['changeTrackingId'],c['changeType'],c['item']['path'],'obj',c['item']['objectId'][:8]) for c in d['changeEntries']]"

section "7. Server-side diff LISTING between two commits (diffs/commits) - gives change list + counts, NOT line content"
curl -s "$G/diffs/commits?baseVersion=2adc745e20d7a07fb7f177853d3e78a95b007aef&baseVersionType=commit&targetVersion=3aae318f1661c50c34effbbf6882119ed161f2d6&targetVersionType=commit&$API" | py "import sys,json; d=json.load(sys.stdin); print(json.dumps({k:d.get(k) for k in ['allChangesIncluded','changeCounts','aheadCount','behindCount']})); [print(' ',c['changeType'],c['item'].get('gitObjectType'),c['item']['path']) for c in d['changes']]"

section "8. File content at a specific commit via Items API (fetch base + target, diff client-side)"
curl -s -H "Accept: application/json" "$G/items?path=/es-metadata.yml&versionDescriptor.version=3aae318f1661c50c34effbbf6882119ed161f2d6&versionDescriptor.versionType=commit&includeContent=true&$API" | py "import sys,json; d=json.load(sys.stdin); print(' objectId',d.get('objectId'),' bytes',len(d.get('content','')))"

section "9. PR threads: system events + text comments; threadContext is null for non-file comments; comment content is HTML/markdown mix"
curl -s "$G/pullrequests/5/threads?$API" | py "import sys,json; d=json.load(sys.stdin); print(' threads',d['count']); [print(' ',t['id'],t.get('status'),'| ctx',json.dumps(t.get('threadContext')),'|',[(c.get('commentType'),(c.get('content') or '')[:40]) for c in t['comments']][:2]) for t in d['value']]"

section "10. Builds, timeline (stages/jobs/tasks tree) and raw log lines - all anonymous on public projects"
curl -s "$B/build/builds?\$top=2&$API" | py "import sys,json; d=json.load(sys.stdin); [print(' build',b['id'],b['definition']['name'],b['status'],b.get('result'),b['sourceBranch']) for b in d['value']]"
BUILD=$(curl -s "$B/build/builds?\$top=1&$API" | py "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])")
curl -s "$B/build/builds/$BUILD/timeline?$API" | py "import sys,json; d=json.load(sys.stdin); r=d['records']; print(' timeline records',len(r),'types',sorted(set(x['type'] for x in r)))"
curl -s "$B/build/builds/$BUILD/logs?$API" | py "import sys,json; d=json.load(sys.stdin); print(' logs',d['count'])"
curl -s "$B/build/builds/$BUILD/logs/1?$API" | head -3 | sed 's/^/   /'

section "11. Response headers: X-RateLimit-Cost (TSTU) is returned per call; X-RateLimit-Remaining/Delay + Retry-After appear only when throttled"
curl -s -D - -o /dev/null "$G?$API" | grep -iE "^HTTP|x-ratelimit|retry-after|x-vss-e2eid|content-type" | cut -c1-120

section "12. connectionData (semi-official): identity GUID + deploymentType in one call; anonymous returns 'Anonymous'"
curl -s "https://dev.azure.com/$ORG/_apis/connectionData" | py "import sys,json; d=json.load(sys.stdin); print(json.dumps({'authenticatedUser':d['authenticatedUser'].get('providerDisplayName'),'deploymentType':d.get('deploymentType')}))"

section "13. ResourceAreas: per-service host routing (requires 7.1-preview.1; bare 7.1 is rejected with VssInvalidPreviewVersionException)"
curl -s "https://dev.azure.com/$ORG/_apis/ResourceAreas?api-version=7.1-preview.1" | py "
import sys,json; d=json.load(sys.stdin); hosts={}
for a in d['value']: hosts.setdefault(a['locationUrl'],[]).append(a['name'])
for h,n in sorted(hosts.items()): print(' ',h,'->',', '.join(sorted(n))[:120])"

section "14. Which api-version values are routable for wit/workitems (JSON TF401232 = routed; HTML 'Page not found' = version does not exist)"
for v in 7.1 7.2-preview.1 7.2-preview.2 7.2-preview.3 7.2-preview.4; do
  printf "  %-14s " "$v"; curl -s -o /dev/null -w "HTTP %{http_code} " "https://dev.azure.com/dnceng/public/_apis/wit/workitems?ids=1&fields=System.Id&api-version=$v"
  curl -s "https://dev.azure.com/dnceng/public/_apis/wit/workitems?ids=1&fields=System.Id&api-version=$v" | head -c 40 | tr -d '\r\n' | sed 's/<!DOCTYPE.*/<HTML Page not found>/'; echo
done

section "15. Org-level PR list ({org}/_apis/git/pullrequests) - undocumented; anonymous gets 302 so this needs an authenticated test"
curl -s -o /dev/null -w "  HTTP %{http_code}\n" "https://dev.azure.com/$ORG/_apis/git/pullrequests?searchCriteria.status=all&\$top=3&$API"
