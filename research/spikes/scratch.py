"""Guard for write spikes: everything targets the scratch project only."""
from lib import *

SCRATCH = 'DevOps Mobile App'
P = urllib.parse.quote(SCRATCH)
TEAM = 'DevOps Mobile App Team'
T = urllib.parse.quote(TEAM)


def wi_get(wid):
    return get(f'{ORG_URL}/{P}/_apis/wit/workitems/{wid}?api-version=7.1')


def wi_create(wtype, ops):
    url = f'{ORG_URL}/{P}/_apis/wit/workitems/${urllib.parse.quote(wtype)}?api-version=7.1'
    return call('POST', url, ops, headers={'Content-Type': 'application/json-patch+json'})


def wi_patch(wid, ops, extra=''):
    # work item PATCH is org-scoped by id; verify the item belongs to the scratch project first
    s, h, w = wi_get(wid)
    assert isinstance(w, dict) and w['fields']['System.TeamProject'] == SCRATCH, f'work item {wid} is not in the scratch project'
    return patch(f'{ORG_URL}/_apis/wit/workitems/{wid}?api-version=7.1{extra}', ops)


def fmt(w):
    if not isinstance(w, dict):
        return w
    f = w.get('fields', {})
    return {'id': w.get('id'), 'rev': w.get('rev'), 'state': f.get('System.State'), 'title': f.get('System.Title'),
            'description': (f.get('System.Description') or '')[:160], 'multilineFieldsFormat': w.get('multilineFieldsFormat')}
