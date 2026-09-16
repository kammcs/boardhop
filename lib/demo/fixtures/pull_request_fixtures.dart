import '../demo_backend.dart';
import '../demo_world.dart';
import 'pull_requests/pr_catalog.dart';

/// Pull request review: the inbox, one pull request's overview, files,
/// threads and checks, the file contents its diff reads, and the writes a
/// reviewer makes (vote, reply, resolve, complete), kept in memory for the
/// life of the backend so the screens answer the way the service does.
///
/// Also serves the Git reads PR review leans on — the repositories list,
/// branch stats, `items` at a commit or branch — plus `connectionData` and
/// `identities?identityIds=` (the signed-in id and `@<guid>` names), which
/// no other area registered.
void registerPullRequestFixtures(DemoBackend b) {
  final store = _PrStore();
  const host = r'dev\.azure\.com/' + DemoWorld.org;
  const project = '(?:/(?:${DemoWorld.project}|${DemoWorld.projectId}))?';
  const git = '$host$project/_apis/git';
  const prs = '[Pp]ull[Rr]equests';
  const repoPr = '$git/repositories/([^/]+)/$prs/(\\d+)';

  // --- Who is signed in, and names for identity GUIDs ----------------------

  b.get('$host/_apis/[Cc]onnection[Dd]ata', (_) {
    final me = _identityRow(DemoWorld.me);
    return {
      'authenticatedUser': me,
      'authorizedUser': me,
      'instanceId': DemoWorld.orgId,
      'locationServiceData': {'serviceOwner': DemoWorld.orgId},
    };
  });

  b.get('vssps\\.dev\\.azure\\.com/${DemoWorld.org}/_apis/identities', (r) {
    final ids = (r.query['identityIds'] ?? '')
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    final rows = [
      for (final p in DemoWorld.people)
        if (ids.contains(p.id)) _identityRow(p),
    ];
    return {'count': rows.length, 'value': rows};
  });

  // --- Repositories and branches --------------------------------------------

  b.get('$git/repositories', (_) {
    final rows = [for (final repo in DemoWorld.repos) _repoJson(repo)];
    return {'count': rows.length, 'value': rows};
  });

  b.get('$git/repositories/([^/]+)', (r) {
    final repo = _repo(r.group(1));
    return repo == null ? const DemoResponse(404) : _repoJson(repo);
  });

  b.get('$git/repositories/([^/]+)/stats/branches', (r) {
    final repo = _repo(r.group(1));
    if (repo == null) return const DemoResponse(404);
    final rows = store.branches(repo);
    final name = r.query['name'];
    if (name != null) {
      for (final row in rows) {
        if (row['name'] == name) return row;
      }
      return const DemoResponse(404);
    }
    return {'count': rows.length, 'value': rows};
  });

  b.get('$git/repositories/([^/]+)/items', (r) {
    final repo = _repo(r.group(1));
    final path = r.query['path'];
    if (repo == null || path == null) return const DemoResponse(404);
    final version = r.query['versionDescriptor.version'];
    final type = r.query['versionDescriptor.versionType'] ?? 'branch';
    final hit = store.file(repo, path, version, type);
    if (hit == null) {
      return DemoResponse(404, {
        'message': 'TF401174: The item \'$path\' could not be found.',
      });
    }
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    return {
      'objectId': _hex('blob:${hit.commit}:$path'),
      'gitObjectType': 'blob',
      'commitId': hit.commit,
      'path': path,
      'url': '${repo.url}/items?path=${Uri.encodeQueryComponent(path)}',
      'contentMetadata': {
        'encoding': 65001,
        'contentType': 'text/plain',
        'fileName': name,
        if (dot > 0) 'extension': name.substring(dot + 1),
      },
      if (r.query['includeContent'] == 'true') 'content': hit.text,
    };
  });

  // --- Lists ------------------------------------------------------------------

  Object list(DemoRequest r, {String? repositoryId}) {
    final status = r.query['searchCriteria.status'] ?? 'active';
    final reviewer = r.query['searchCriteria.reviewerId']?.toLowerCase();
    final creator = r.query['searchCriteria.creatorId']?.toLowerCase();
    final repo = repositoryId ?? r.query['searchCriteria.repositoryId'];
    final top = int.tryParse(r.query[r'$top'] ?? '') ?? 100;
    final rows = [
      for (final s in store.states)
        if ((status == 'all' || s.json['status'] == status) &&
            (repo == null || _sameRepo(s.spec.ref.repo, repo)) &&
            (creator == null || s.spec.ref.author.id == creator) &&
            (reviewer == null || s.hasReviewer(reviewer)))
          s.listJson(),
    ].take(top).toList();
    return {'count': rows.length, 'value': rows};
  }

  b.get('$git/$prs', list);
  b.get(
    '$git/repositories/([^/]+)/$prs',
    (r) => list(r, repositoryId: r.group(1)),
  );

  // --- One pull request -------------------------------------------------------

  Object withPr(DemoRequest r, Object? Function(_PrState s) read) {
    final s = store.byId(int.parse(r.group(r.match.groupCount)));
    if (s == null) {
      return const DemoResponse(404, {
        'message': 'TF401180: The requested pull request was not found.',
      });
    }
    return read(s) ?? const DemoResponse(404);
  }

  // Sub-resources carry the repository and the id as the last two groups.
  Object sub(DemoRequest r, Object? Function(_PrState s) read) {
    final s = store.byId(int.parse(r.group(2)));
    if (s == null || !_sameRepo(s.spec.ref.repo, r.group(1))) {
      return const DemoResponse(404, {
        'message': 'TF401180: The requested pull request was not found.',
      });
    }
    return read(s) ?? const DemoResponse(404);
  }

  b.get('$git/$prs/(\\d+)', (r) => withPr(r, (s) => s.detailJson()));
  b.get(repoPr, (r) => sub(r, (s) => s.detailJson()));
  b.get('$repoPr/reviewers', (r) => sub(r, (s) => _values(s.reviewers)));
  b.get('$repoPr/workitems', (r) => sub(r, (s) => _values(s.workItemRefs())));
  b.get('$repoPr/labels', (r) => sub(r, (s) => _values(s.labels)));
  b.get('$repoPr/iterations', (r) => sub(r, (s) => _values(s.iterations())));
  b.get(
    '$repoPr/iterations/(\\d+)',
    (r) => sub(r, (s) => s.iteration(int.parse(r.group(3)))),
  );
  b.get('$repoPr/iterations/(\\d+)/changes', (r) {
    return sub(r, (s) => s.changes(int.parse(r.group(3))));
  });
  b.get('$repoPr/threads', (r) => sub(r, (s) => _values(s.threads)));
  b.get(
    '$repoPr/threads/(\\d+)',
    (r) => sub(r, (s) => s.thread(int.parse(r.group(3)))),
  );
  b.get('$repoPr/statuses', (r) => sub(r, (s) => _values(s.statuses())));
  b.get('$repoPr/commits', (r) => sub(r, (s) => _values(s.commits())));
  b.get('$repoPr/conflicts', (r) => sub(r, (_) => _values(const [])));
  b.get('$repoPr/attachments', (r) => sub(r, (_) => _values(const [])));

  b.get('$host$project/_apis/policy/evaluations', (r) {
    final artifact = r.query['artifactId'] ?? '';
    final id = int.tryParse(artifact.substring(artifact.lastIndexOf('/') + 1));
    final s = id == null ? null : store.byId(id);
    return _values(s?.evaluations() ?? const []);
  });

  b.get('$git/policy/configurations', (r) {
    final repo = _repo(r.query['repositoryId'] ?? '') ?? DemoWorld.appRepo;
    final ref = r.query['refName'];
    final rows = ref == null || ref == 'refs/heads/main'
        ? [for (final p in DemoPolicies.all) _policyJson(p, repo)]
        : const <Map<String, dynamic>>[];
    return _values(rows);
  });

  // --- Writes -----------------------------------------------------------------

  b.patch(repoPr, (r) => sub(r, (s) => s.patch(_map(r.body))));

  b.put(
    '$repoPr/reviewers/([^/]+)',
    (r) => sub(r, (s) => s.putReviewer(r.group(3), _map(r.body))),
  );
  b.patch(
    '$repoPr/reviewers/([^/]+)',
    (r) => sub(r, (s) => s.patchReviewer(r.group(3), _map(r.body))),
  );
  b.patch('$repoPr/reviewers', (r) {
    return sub(r, (s) {
      for (final row in (r.body as List? ?? const []).whereType<Map>()) {
        s.patchReviewer('${row['id']}', row.cast<String, dynamic>());
      }
      return const DemoResponse(204);
    });
  });
  b.delete(
    '$repoPr/reviewers/([^/]+)',
    (r) => sub(r, (s) => s.removeReviewer(r.group(3))),
  );

  b.post('$repoPr/labels', (r) => sub(r, (s) => s.addLabel(_map(r.body))));
  b.delete(
    '$repoPr/labels/([^/]+)',
    (r) => sub(r, (s) => s.removeLabel(r.group(3))),
  );

  b.post('$repoPr/threads', (r) => sub(r, (s) => s.addThread(_map(r.body))));
  b.patch(
    '$repoPr/threads/(\\d+)',
    (r) => sub(r, (s) => s.patchThread(int.parse(r.group(3)), _map(r.body))),
  );
  b.post(
    '$repoPr/threads/(\\d+)/comments',
    (r) => sub(r, (s) => s.addComment(int.parse(r.group(3)), _map(r.body))),
  );
  b.patch(
    '$repoPr/threads/(\\d+)/comments/(\\d+)',
    (r) => sub(
      r,
      (s) => s.editComment(
        int.parse(r.group(3)),
        int.parse(r.group(4)),
        _map(r.body),
      ),
    ),
  );
  b.delete(
    '$repoPr/threads/(\\d+)/comments/(\\d+)',
    (r) => sub(
      r,
      (s) => s.deleteComment(int.parse(r.group(3)), int.parse(r.group(4))),
    ),
  );
  b.post(
    '$repoPr/threads/(\\d+)/comments/(\\d+)/likes',
    (r) => sub(
      r,
      (s) => s.like(int.parse(r.group(3)), int.parse(r.group(4)), true),
    ),
  );
  b.delete(
    '$repoPr/threads/(\\d+)/comments/(\\d+)/likes',
    (r) => sub(
      r,
      (s) => s.like(int.parse(r.group(3)), int.parse(r.group(4)), false),
    ),
  );
  b.post('$repoPr/share', (r) => sub(r, (_) => const DemoResponse(200)));
}

// -----------------------------------------------------------------------------

/// A file's text at a commit.
typedef _FileHit = ({String commit, String text});

class _PrStore {
  _PrStore()
    : states = [for (final spec in DemoPullRequests.all) _PrState(spec)];

  final List<_PrState> states;

  _PrState? byId(int id) {
    for (final s in states) {
      if (s.spec.ref.id == id) return s;
    }
    return null;
  }

  /// `main` and every source branch of the repository's pull requests.
  List<Map<String, dynamic>> branches(DemoRepo repo) {
    final mainTip = _hex('main:${repo.name}');
    return [
      _branchJson(
        'main',
        mainTip,
        DemoWorld.kelly,
        20,
        'Merge PR 403: '
            'Offline cache for boards',
        ahead: 0,
        behind: 0,
        base: true,
      ),
      for (final s in states)
        if (s.spec.ref.repo.id == repo.id)
          _branchJson(
            s.spec.ref.sourceBranch,
            s.sourceCommit(s.spec.pushes.length),
            s.spec.ref.author,
            s.spec.pushes.last,
            s.commits().first['comment'] as String,
            ahead: s.spec.pushes.length,
            behind: 2,
          ),
    ];
  }

  /// The text of [path] at a commit (a pull request's base or one of its
  /// iterations) or a branch (`main` has every base, a source branch its
  /// pull request's newest text).
  _FileHit? file(DemoRepo repo, String path, String? version, String type) {
    for (final s in states) {
      if (s.spec.ref.repo.id != repo.id) continue;
      for (final f in s.spec.files) {
        if (f.path != path) continue;
        if (type == 'commit') {
          if (version == s.baseCommit && f.changeType != 'add') {
            return (commit: version!, text: f.oldText);
          }
          for (var i = 1; i <= s.spec.pushes.length; i++) {
            if (version == s.sourceCommit(i) && f.changeType != 'delete') {
              return (commit: version!, text: f.newText);
            }
          }
        } else if (version == null || version == 'main') {
          if (f.changeType != 'add') {
            return (commit: _hex('main:${repo.name}'), text: f.oldText);
          }
        } else if (version == s.spec.ref.sourceBranch) {
          return (
            commit: s.sourceCommit(s.spec.pushes.length),
            text: f.newText,
          );
        }
      }
    }
    return null;
  }
}

/// One pull request as the service holds it: JSON built once from the
/// catalog, then changed in place by the writes.
class _PrState {
  _PrState(this.spec) {
    final ref = spec.ref;
    reviewers = [for (final r in spec.reviewers) _reviewerJson(r)];
    labels = [for (final l in spec.labels) _labelJson(l)];
    json = {
      'repository': _repoJson(ref.repo),
      'pullRequestId': ref.id,
      'codeReviewId': ref.id,
      'status': 'active',
      'createdBy': ref.author.identity(),
      'creationDate': _ago(ref.createdHoursAgo),
      'title': ref.title,
      'description': spec.description,
      'sourceRefName': 'refs/heads/${ref.sourceBranch}',
      'targetRefName': 'refs/heads/main',
      'mergeStatus': spec.mergeStatus,
      'isDraft': ref.isDraft,
      'mergeId': _hex('merge:${ref.id}'),
      'lastMergeSourceCommit': _commitRef(sourceCommit(spec.pushes.length)),
      'lastMergeTargetCommit': _commitRef(_hex('main:${ref.repo.name}')),
      'lastMergeCommit': _commitRef(_hex('mergecommit:${ref.id}')),
      'url':
          '${DemoWorld.projectUrl}/_apis/git/repositories/${ref.repo.id}'
          '/pullRequests/${ref.id}',
      'supportsIterations': true,
      if (spec.autoCompleteSetBy != null) ...{
        'autoCompleteSetBy': spec.autoCompleteSetBy!.identity(),
        'completionOptions': {
          'mergeStrategy': 'squash',
          'deleteSourceBranch': true,
          'transitionWorkItems': true,
          'mergeCommitMessage': 'Merged PR ${ref.id}: ${ref.title}',
        },
      },
    };
    var nextId = 1;
    for (final t in spec.threads) {
      threads.add(_threadJson(nextId++, t));
    }
    for (final e in spec.events) {
      threads.add(_eventJson(nextId++, e));
    }
    threads.sort(
      (a, b) => (a['publishedDate'] as String).compareTo(
        b['publishedDate'] as String,
      ),
    );
  }

  final DemoPullRequest spec;
  late final Map<String, dynamic> json;
  late final List<Map<String, dynamic>> reviewers;
  late final List<Map<String, dynamic>> labels;
  final List<Map<String, dynamic>> threads = [];

  String get baseCommit => _hex('base:${spec.ref.id}');
  String sourceCommit(int iteration) => _hex('src:${spec.ref.id}:$iteration');

  bool hasReviewer(String id) =>
      reviewers.any((r) => (r['id'] as String).toLowerCase() == id);

  /// The list shape: labels included, as every list route has them.
  Map<String, dynamic> listJson() => {
    ...json,
    'reviewers': reviewers,
    'labels': labels,
  };

  /// `GET pullRequests/{id}` never carries labels (spike s65).
  Map<String, dynamic> detailJson() => {...json, 'reviewers': reviewers};

  List<Map<String, dynamic>> workItemRefs() => [
    for (final id in spec.ref.workItems)
      {'id': '$id', 'url': '${DemoWorld.baseUrl}/_apis/wit/workItems/$id'},
  ];

  List<Map<String, dynamic>> iterations() => [
    for (var i = 1; i <= spec.pushes.length; i++) iteration(i)!,
  ];

  Map<String, dynamic>? iteration(int i) {
    if (i < 1 || i > spec.pushes.length) return null;
    final at = _ago(spec.pushes[i - 1]);
    return {
      'id': i,
      'description': i == 1 ? spec.ref.title : 'Address review comments',
      'author': spec.ref.author.identity(),
      'createdDate': at,
      'updatedDate': at,
      'sourceRefCommit': _commitRef(sourceCommit(i)),
      'targetRefCommit': _commitRef(_hex('main:${spec.ref.repo.name}')),
      'commonRefCommit': _commitRef(baseCommit),
      'hasMoreCommits': false,
      'reason': i == 1 ? 'create' : 'push',
      'push': {'pushId': 3000 + spec.ref.id * 10 + i, 'date': at},
    };
  }

  Map<String, dynamic>? changes(int iteration) {
    if (iteration < 1 || iteration > spec.pushes.length) return null;
    return {
      'changeEntries': [
        for (final (i, f) in spec.files.indexed)
          {
            'changeTrackingId': i + 1,
            'changeId': i + 1,
            'item': {
              'objectId': _hex('blob:new:${spec.ref.id}:${f.path}'),
              if (f.changeType != 'add')
                'originalObjectId': _hex('blob:old:${spec.ref.id}:${f.path}'),
              'path': f.path,
              'gitObjectType': 'blob',
            },
            'changeType': f.changeType,
          },
      ],
      'nextSkip': 0,
      'nextTop': 0,
    };
  }

  List<Map<String, dynamic>> commits() {
    final ref = spec.ref;
    return [
      for (var i = spec.pushes.length; i >= 1; i--)
        {
          'commitId': sourceCommit(i),
          'author': _signature(ref.author, spec.pushes[i - 1]),
          'committer': _signature(ref.author, spec.pushes[i - 1]),
          'comment': i == 1 ? ref.title : 'Address review comments',
          'url': '${ref.repo.url}/commit/${sourceCommit(i)}',
        },
    ];
  }

  List<Map<String, dynamic>> evaluations() => [
    for (final (i, c) in spec.checks.indexed)
      {
        'evaluationId': _guid('eval:${spec.ref.id}:$i'),
        'artifactId':
            'vstfs:///CodeReview/CodeReviewId/${DemoWorld.projectId}'
            '/${spec.ref.id}',
        'status': c.status,
        'startedDate': _ago(spec.pushes.last),
        if (c.status == 'approved' || c.status == 'rejected')
          'completedDate': _ago(spec.pushes.last * 0.9),
        'configuration': _policyJson(c.policy, spec.ref.repo),
        if (c.policy.id == DemoPolicies.build.id)
          'context': {
            'buildId': 20000 + spec.ref.id,
            'buildDefinitionId': 7,
            'buildDefinitionName': DemoPolicies.pipelineFor(spec.ref.repo),
            'buildIsNotCurrent': false,
            'buildStartedUtc': _ago(spec.pushes.last),
            'isExpired': false,
            'lastMergeCommitId': json['lastMergeCommit']['commitId'],
            'lastMergeSourceCommitId': sourceCommit(spec.pushes.length),
          },
      },
  ];

  List<Map<String, dynamic>> statuses() => [
    if (spec.coverage != null)
      {
        'id': 1,
        'iterationId': spec.pushes.length,
        'state': 'succeeded',
        'description': spec.coverage,
        'context': {'name': 'lcov', 'genre': 'coverage'},
        'creationDate': _ago(spec.pushes.last * 0.8),
        'createdBy': DemoWorld.jonah.identity(),
        'targetUrl':
            '${DemoWorld.baseUrl}/${DemoWorld.project}/_build/results'
            '?buildId=${20000 + spec.ref.id}&view=codecoverage-tab',
      },
  ];

  Map<String, dynamic>? thread(int id) {
    for (final t in threads) {
      if (t['id'] == id) return t;
    }
    return null;
  }

  // --- Writes ---------------------------------------------------------------

  Map<String, dynamic> patch(Map<String, dynamic> body) {
    for (final key in ['title', 'description', 'targetRefName', 'isDraft']) {
      if (body.containsKey(key)) json[key] = body[key];
    }
    if (body['isDraft'] == true) {
      for (final r in reviewers) {
        r['vote'] = 0;
      }
    }
    final options = body['completionOptions'];
    if (options is Map) json['completionOptions'] = options;
    final setBy = body['autoCompleteSetBy'];
    if (setBy is Map) {
      if (setBy['id'] == '00000000-0000-0000-0000-000000000000') {
        json.remove('autoCompleteSetBy');
      } else {
        json['autoCompleteSetBy'] = DemoWorld.person('${setBy['id']}')
            .identity();
      }
    }
    switch (body['status']) {
      case 'completed':
        json['status'] = 'completed';
        json['closedDate'] = DemoWorld.iso(DateTime.now().toUtc());
        json['closedBy'] = DemoWorld.me.identity();
        json['mergeStatus'] = 'succeeded';
        json.remove('autoCompleteSetBy');
      case 'abandoned':
        json['status'] = 'abandoned';
        json['closedDate'] = DemoWorld.iso(DateTime.now().toUtc());
        json['closedBy'] = DemoWorld.me.identity();
        json.remove('autoCompleteSetBy');
      case 'active':
        json['status'] = 'active';
        json.remove('closedDate');
        json.remove('closedBy');
    }
    if (body.containsKey('mergeOptions')) json['mergeStatus'] = 'succeeded';
    return detailJson();
  }

  Map<String, dynamic> putReviewer(String id, Map<String, dynamic> body) {
    final row = _findReviewer(id) ?? _addReviewer(id);
    if (body['vote'] is num) row['vote'] = (body['vote'] as num).toInt();
    if (body['isRequired'] == true) {
      row['isRequired'] = true;
    } else if (body.containsKey('isRequired')) {
      row.remove('isRequired');
    }
    if (id.toLowerCase() == DemoWorld.me.id && body['vote'] is num) {
      threads.add(
        _eventJson(
          _nextThreadId(),
          DemoEvent(
            'VoteUpdate',
            DemoWorld.me,
            '{1} voted ${row['vote']}',
            0,
            properties: {'CodeReviewVoteResult': '${row['vote']}'},
          ),
        ),
      );
    }
    return row;
  }

  Map<String, dynamic> patchReviewer(String id, Map<String, dynamic> body) {
    final row = _findReviewer(id) ?? _addReviewer(id);
    for (final key in ['vote', 'isFlagged', 'hasDeclined']) {
      if (body.containsKey(key)) row[key] = body[key];
    }
    return row;
  }

  DemoResponse removeReviewer(String id) {
    reviewers.removeWhere(
      (r) => (r['id'] as String).toLowerCase() == id.toLowerCase(),
    );
    return const DemoResponse(204);
  }

  Map<String, dynamic>? _findReviewer(String id) {
    for (final r in reviewers) {
      if ((r['id'] as String).toLowerCase() == id.toLowerCase()) return r;
    }
    return null;
  }

  Map<String, dynamic> _addReviewer(String id) {
    final row = _reviewerJson(DemoReviewer(DemoWorld.person(id)));
    reviewers.add(row);
    return row;
  }

  Map<String, dynamic> addLabel(Map<String, dynamic> body) {
    final name = '${body['name'] ?? ''}'.trim();
    for (final l in labels) {
      if ((l['name'] as String).toLowerCase() == name.toLowerCase()) return l;
    }
    final row = _labelJson(name);
    labels.add(row);
    return row;
  }

  DemoResponse removeLabel(String nameOrId) {
    labels.removeWhere(
      (l) =>
          (l['name'] as String).toLowerCase() == nameOrId.toLowerCase() ||
          l['id'] == nameOrId,
    );
    return const DemoResponse(204);
  }

  int _nextThreadId() =>
      threads.fold<int>(
        0,
        (m, t) => (t['id'] as int) > m ? t['id'] as int : m,
      ) +
      1;

  Map<String, dynamic> addThread(Map<String, dynamic> body) {
    final now = DemoWorld.iso(DateTime.now().toUtc());
    final first = ((body['comments'] as List?) ?? const [])
        .whereType<Map>()
        .firstOrNull;
    final row = <String, dynamic>{
      'id': _nextThreadId(),
      'publishedDate': now,
      'lastUpdatedDate': now,
      'status': _statusName(body['status']),
      'threadContext': ?body['threadContext'],
      'pullRequestThreadContext': ?body['pullRequestThreadContext'],
      'comments': [
        _commentJson(1, DemoWorld.me, '${first?['content'] ?? ''}', now),
      ],
      'properties': _markdownProperties,
      'isDeleted': false,
    };
    threads.add(row);
    return row;
  }

  Map<String, dynamic>? patchThread(int id, Map<String, dynamic> body) {
    final t = thread(id);
    if (t == null) return null;
    if (body.containsKey('status')) t['status'] = _statusName(body['status']);
    t['lastUpdatedDate'] = DemoWorld.iso(DateTime.now().toUtc());
    return t;
  }

  Map<String, dynamic>? addComment(int threadId, Map<String, dynamic> body) {
    final t = thread(threadId);
    if (t == null) return null;
    final comments = (t['comments'] as List).cast<Map<String, dynamic>>();
    final now = DemoWorld.iso(DateTime.now().toUtc());
    final row = _commentJson(
      comments.length + 1,
      DemoWorld.me,
      '${body['content'] ?? ''}',
      now,
      parent: (body['parentCommentId'] as num?)?.toInt() ?? 1,
    );
    comments.add(row);
    t['lastUpdatedDate'] = now;
    return row;
  }

  Map<String, dynamic>? _comment(int threadId, int commentId) {
    final t = thread(threadId);
    if (t == null) return null;
    for (final c in (t['comments'] as List).cast<Map<String, dynamic>>()) {
      if (c['id'] == commentId) return c;
    }
    return null;
  }

  Map<String, dynamic>? editComment(
    int threadId,
    int commentId,
    Map<String, dynamic> body,
  ) {
    final c = _comment(threadId, commentId);
    if (c == null) return null;
    final now = DemoWorld.iso(DateTime.now().toUtc());
    c['content'] = '${body['content'] ?? ''}';
    c['lastUpdatedDate'] = now;
    c['lastContentUpdatedDate'] = now;
    return c;
  }

  DemoResponse? deleteComment(int threadId, int commentId) {
    final c = _comment(threadId, commentId);
    if (c == null) return null;
    c['isDeleted'] = true;
    c.remove('content');
    return const DemoResponse(204);
  }

  DemoResponse? like(int threadId, int commentId, bool on) {
    final c = _comment(threadId, commentId);
    if (c == null) return null;
    final liked = (c['usersLiked'] as List).cast<Map<String, dynamic>>();
    liked.removeWhere((u) => u['id'] == DemoWorld.me.id);
    if (on) liked.add(DemoWorld.me.identity());
    return const DemoResponse(204);
  }

  // --- Builders -------------------------------------------------------------

  Map<String, dynamic> _threadJson(int id, DemoThread t) {
    final first = t.comments.first;
    final last = t.comments.last;
    Map<String, dynamic>? context;
    Map<String, dynamic>? prContext;
    final path = t.path;
    if (path != null) {
      final index = spec.files.indexWhere((f) => f.path == path);
      final file = spec.files[index];
      final anchor = t.anchor;
      context = {'filePath': path};
      if (anchor != null) {
        final text = t.leftSide ? file.oldText : file.newText;
        final line = _lineOf(text, anchor);
        final end = line + t.span - 1;
        final start = t.leftSide ? 'leftFileStart' : 'rightFileStart';
        final stop = t.leftSide ? 'leftFileEnd' : 'rightFileEnd';
        context[start] = {'line': line, 'offset': 1};
        context[stop] = {'line': end, 'offset': t.span > 1 ? 2147483647 : 1};
      }
      prContext = {
        'changeTrackingId': index + 1,
        'iterationContext': {
          'firstComparingIteration': 1,
          'secondComparingIteration': spec.pushes.length,
        },
      };
    }
    return {
      'id': id,
      'publishedDate': _ago(first.hoursAgo),
      'lastUpdatedDate': _ago(last.hoursAgo),
      'status': t.status,
      'threadContext': ?context,
      'pullRequestThreadContext': ?prContext,
      'comments': [
        for (final (i, c) in t.comments.indexed)
          _commentJson(
            i + 1,
            c.author,
            c.text,
            _ago(c.hoursAgo),
            parent: i == 0 ? 0 : 1,
            likedBy: c.likedBy,
          ),
      ],
      'properties': _markdownProperties,
      'identities': null,
      'isDeleted': false,
      '_links': {
        'self': {'href': '${json['url']}/threads/$id'},
      },
    };
  }

  Map<String, dynamic> _eventJson(int id, DemoEvent e) {
    final at = _ago(e.hoursAgo);
    return {
      'id': id,
      'publishedDate': at,
      'lastUpdatedDate': at,
      'comments': [
        {..._commentJson(1, e.actor, e.text, at), 'commentType': 'system'},
      ],
      'properties': {
        'CodeReviewThreadType': {r'$type': 'System.String', r'$value': e.kind},
        for (final p in e.properties.entries)
          p.key: {r'$type': 'System.String', r'$value': p.value},
      },
      'identities': {'1': e.actor.identity()},
      'isDeleted': false,
    };
  }
}

// --- Shapes -------------------------------------------------------------------

const _markdownProperties = {
  'Microsoft.TeamFoundation.Discussion.SupportsMarkdown': {
    r'$type': 'System.Int32',
    r'$value': 1,
  },
  'Microsoft.TeamFoundation.Discussion.UniqueID': {
    r'$type': 'System.String',
    r'$value': '5c3b1f9e-7a2d-4e68-b0c4-2d9f6a1e8b37',
  },
};

Map<String, dynamic> _values(List<Map<String, dynamic>> rows) => {
  'count': rows.length,
  'value': rows,
};

Map<String, dynamic> _map(Object? body) =>
    body is Map ? body.cast<String, dynamic>() : <String, dynamic>{};

String _ago(num hours) => DemoWorld.iso(DemoWorld.hoursAgo(hours));

String _statusName(Object? status) => switch (status) {
  1 || null => 'active',
  2 => 'fixed',
  3 => 'wontFix',
  4 => 'closed',
  5 => 'byDesign',
  6 => 'pending',
  final Object s => '$s',
};

DemoRepo? _repo(String idOrName) {
  for (final repo in DemoWorld.repos) {
    if (repo.id == idOrName.toLowerCase() || repo.name == idOrName) return repo;
  }
  return null;
}

bool _sameRepo(DemoRepo repo, String idOrName) =>
    repo.id == idOrName.toLowerCase() || repo.name == idOrName;

Map<String, dynamic> _repoJson(DemoRepo repo) => {
  'id': repo.id,
  'name': repo.name,
  'url': '${DemoWorld.projectUrl}/_apis/git/repositories/${repo.id}',
  'project': {
    'id': DemoWorld.projectId,
    'name': DemoWorld.project,
    'state': 'wellFormed',
    'visibility': 'private',
  },
  'defaultBranch': 'refs/heads/main',
  'size': switch (repo.name) {
    'boardhop' => 48213557,
    'boardhop-relay' => 3120442,
    _ => 1893310,
  },
  'remoteUrl':
      'https://${DemoWorld.org}@dev.azure.com/${DemoWorld.org}/'
      '${DemoWorld.project}/_git/${repo.name}',
  'webUrl': repo.url,
  'isDisabled': false,
  'isInMaintenance': false,
};

Map<String, dynamic> _identityRow(DemoPerson p) => {
  'id': p.id,
  'descriptor':
      'Microsoft.IdentityModel.Claims.ClaimsIdentity;'
      '${DemoWorld.tenantId}\\${p.email}',
  'subjectDescriptor': p.descriptor,
  'providerDisplayName': p.name,
  'isActive': true,
  'isContainer': false,
  'members': const <Object>[],
  'memberOf': const <Object>[],
  'memberIds': const <Object>[],
  'metaTypeId': 0,
  'properties': {
    'Account': {r'$type': 'System.String', r'$value': p.email},
    'Mail': {r'$type': 'System.String', r'$value': p.email},
    'SchemaClassName': {r'$type': 'System.String', r'$value': 'User'},
  },
};

Map<String, dynamic> _reviewerJson(DemoReviewer r) => {
  ...r.person.identity(),
  'reviewerUrl':
      '${DemoWorld.projectUrl}/_apis/git/repositories/reviewers/${r.person.id}',
  'vote': r.vote,
  'hasDeclined': false,
  if (r.isRequired) 'isRequired': true,
  'isFlagged': false,
};

Map<String, dynamic> _labelJson(String name) => {
  'id': _guid('label:$name'),
  'name': name,
  'active': true,
  'url': '${DemoWorld.projectUrl}/_apis/git/labels/${_guid('label:$name')}',
};

Map<String, dynamic> _commentJson(
  int id,
  DemoPerson author,
  String content,
  String at, {
  int parent = 0,
  List<DemoPerson> likedBy = const [],
}) => {
  'id': id,
  'parentCommentId': parent,
  'author': author.identity(),
  'content': content,
  'publishedDate': at,
  'lastUpdatedDate': at,
  'lastContentUpdatedDate': at,
  'commentType': 'text',
  'usersLiked': [for (final p in likedBy) p.identity()],
};

Map<String, dynamic> _commitRef(String id) => {
  'commitId': id,
  'url': '${DemoWorld.projectUrl}/_apis/git/commits/$id',
};

Map<String, dynamic> _signature(DemoPerson p, num hoursAgo) => {
  'name': p.name,
  'email': p.email,
  'date': _ago(hoursAgo),
};

Map<String, dynamic> _branchJson(
  String name,
  String commit,
  DemoPerson author,
  num hoursAgo,
  String comment, {
  required int ahead,
  required int behind,
  bool base = false,
}) => {
  'commit': {
    'commitId': commit,
    'author': _signature(author, hoursAgo),
    'committer': _signature(author, hoursAgo),
    'comment': comment,
  },
  'name': name,
  'aheadCount': ahead,
  'behindCount': behind,
  'isBaseVersion': base,
};

Map<String, dynamic> _policyJson(DemoPolicy p, DemoRepo repo) => {
  'id': p.id,
  'revision': 3,
  'isEnabled': true,
  'isBlocking': p.isBlocking,
  'isDeleted': false,
  'type': {
    'id': p.typeId,
    'displayName': p.displayName,
    'url': '${DemoWorld.projectUrl}/_apis/policy/types/${p.typeId}',
  },
  'settings': {
    ...p.settings,
    if (p.id == DemoPolicies.build.id)
      'displayName': DemoPolicies.pipelineFor(repo),
    'scope': [
      {
        'refName': 'refs/heads/main',
        'matchKind': 'exact',
        'repositoryId': repo.id,
      },
    ],
  },
  'createdBy': DemoWorld.kelly.identity(),
  'createdDate': _ago(24 * 60),
};

/// 1-based line of the first line of [text] containing [needle].
int _lineOf(String text, String needle) {
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains(needle)) return i + 1;
  }
  throw StateError('Demo thread anchor not found: $needle');
}

/// A stable 40-hex-digit id (commit, blob) from a seed.
String _hex(String seed, [int length = 40]) {
  final out = StringBuffer();
  var h = 0xcbf29ce484222325 & 0x7fffffffffffffff;
  var round = 0;
  while (out.length < length) {
    for (final unit in '$seed#$round'.codeUnits) {
      h ^= unit;
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    }
    out.write(h.toRadixString(16).padLeft(16, '0'));
    round++;
  }
  return out.toString().substring(0, length);
}

/// A stable GUID from a seed.
String _guid(String seed) {
  final h = _hex(seed, 32);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-'
      'a${h.substring(17, 20)}-${h.substring(20, 32)}';
}
