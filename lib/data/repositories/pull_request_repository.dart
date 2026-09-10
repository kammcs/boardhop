import 'dart:convert';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../db/app_database.dart';
import '../models/pr_check.dart';
import '../models/pull_request.dart';
import 'pr_diff_source.dart';

enum PrListFilter { toReview, mine, all }

/// A pull request list with where it came from.
typedef PrListResult = ({
  List<PullRequest> items,
  DateTime fetchedAt,
  bool fromCache,
});

/// Pull request reads and the review writes: vote, complete, abandon, new
/// threads, replies and thread status. The list uses the org-level endpoint
/// verified by spike S4 (undocumented) and falls back to the project-level
/// one; each list is cached as one JSON blob so the inbox opens offline.
class PullRequestRepository {
  PullRequestRepository(this._client, [this._db]);

  final AdoClient _client;
  final AppDatabase? _db;

  static const apiVersion = '7.1';
  static const policyApiVersion = '7.1-preview.1';

  final Map<String, String> _me = {};

  static String listKey(String org, String? project, PrListFilter filter) =>
      'pr-list:$org:${project ?? '*'}:${filter.name}';

  /// Identity GUID of the signed-in user in this org (`connectionData`,
  /// semi-official), needed for `reviewerId` filters and voting.
  Future<String> meId(String org) async {
    final cached = _me[org];
    if (cached != null) return cached;
    // connectionData only answers with the preview flag on the version.
    final json = await _client.getJson(
      org: org,
      path: '_apis/connectionData',
      apiVersion: '7.1-preview',
    );
    final id =
        (json['authorizedUser'] as Map?)?['id'] as String? ??
        (json['authenticatedUser'] as Map?)?['id'] as String?;
    if (id == null) throw AdoServerException('connectionData has no user id');
    return _me[org] = id;
  }

  Future<List<PullRequest>> list(
    String org, {
    String? project,
    PrListFilter filter = PrListFilter.toReview,
    String status = 'active',
    int top = 100,
  }) async {
    final query = <String, String>{
      'searchCriteria.status': status,
      r'$top': '$top',
    };
    if (filter != PrListFilter.all) {
      final me = await meId(org);
      query[filter == PrListFilter.toReview
              ? 'searchCriteria.reviewerId'
              : 'searchCriteria.creatorId'] =
          me;
    }
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/git/pullrequests',
      apiVersion: apiVersion,
      query: query,
    );
    final raw = ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    if (status == 'active') await _store(listKey(org, project, filter), raw);
    return raw.map(PullRequest.fromJson).toList();
  }

  /// The last active list fetched for this org/project/filter, if any.
  Future<PrListResult?> cachedList(
    String org, {
    String? project,
    PrListFilter filter = PrListFilter.toReview,
  }) async {
    final db = _db;
    if (db == null) return null;
    final row =
        await (db.select(db.cacheEntries)
              ..where((t) => t.key.equals(listKey(org, project, filter))))
            .getSingleOrNull();
    if (row == null) return null;
    final decoded = jsonDecode(row.json);
    if (decoded is! List) return null;
    return (
      items: decoded
          .whereType<Map>()
          .map((m) => PullRequest.fromJson(m.cast<String, dynamic>()))
          .toList(),
      fetchedAt: row.fetchedAt,
      fromCache: true,
    );
  }

  Future<void> _store(String key, Object json) async {
    final db = _db;
    if (db == null) return;
    await db
        .into(db.cacheEntries)
        .insertOnConflictUpdate(
          CacheEntriesCompanion.insert(
            key: key,
            json: jsonEncode(json),
            fetchedAt: DateTime.now(),
          ),
        );
  }

  Future<PullRequest> get(String org, int id) async {
    final json = await _client.getJson(
      org: org,
      path: '_apis/git/pullrequests/$id',
      apiVersion: apiVersion,
    );
    return PullRequest.fromJson(json);
  }

  PrRef ref(String org, PullRequest pr) => PrRef(
    org: org,
    id: pr.id,
    projectId: pr.projectId,
    repositoryId: pr.repositoryId,
    title: pr.title,
    sourceBranch: pr.sourceRefName,
    targetBranch: pr.targetRefName,
  );

  String _prPath(PullRequest pr, String tail) =>
      '_apis/git/repositories/${pr.repositoryId}/pullRequests/${pr.id}/$tail';

  /// Ids of the work items linked to the pull request.
  Future<List<int>> workItemIds(String org, PullRequest pr) async {
    final json = await _client.getJson(
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'workitems'),
      apiVersion: apiVersion,
    );
    return ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => int.tryParse(m['id'].toString()) ?? 0)
        .where((id) => id > 0)
        .toList();
  }

  /// All threads, including system ones, without iteration positioning
  /// (the conversation tab); the diff page reads its own with
  /// `$iteration`/`$baseIteration` through [PrDiffSource].
  Future<List<Map<String, dynamic>>> rawThreads(
    String org,
    PullRequest pr,
  ) async {
    final json = await _client.getJson(
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'threads'),
      apiVersion: apiVersion,
    );
    return ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }

  /// Branch policy evaluations for the PR (spike s15: the artifact id is
  /// `vstfs:///CodeReview/CodeReviewId/{projectId}/{prId}`).
  Future<List<PrCheck>> policyEvaluations(String org, PullRequest pr) async {
    final json = await _client.getJson(
      org: org,
      project: pr.projectId,
      path: '_apis/policy/evaluations',
      apiVersion: policyApiVersion,
      query: {
        'artifactId':
            'vstfs:///CodeReview/CodeReviewId/${pr.projectId}/${pr.id}',
      },
    );
    return ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => PrCheck.fromEvaluation(m.cast<String, dynamic>()))
        .toList();
  }

  /// External statuses (coverage, bots) for the newest iteration.
  Future<List<PrCheck>> statuses(String org, PullRequest pr) async {
    final json = await _client.getJson(
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'statuses'),
      apiVersion: apiVersion,
    );
    return PrCheck.latestStatuses(
      ((json['value'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList(),
    );
  }

  /// Policies then statuses; either source failing (no policy permission,
  /// old server) leaves the other in place instead of failing the page.
  Future<List<PrCheck>> checks(String org, PullRequest pr) async {
    final out = <PrCheck>[];
    for (final read in [policyEvaluations, statuses]) {
      try {
        out.addAll(await read(org, pr));
      } on AdoAuthException {
        rethrow;
      } on AdoException {
        // Non-fatal: the section just lacks that source.
      }
    }
    return out;
  }

  /// `PUT reviewers/{me}` with the vote (also adds the reviewer).
  Future<PrReviewer> vote(String org, PullRequest pr, PrVote vote) async {
    final me = await meId(org);
    final json = await _client.send(
      method: 'PUT',
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'reviewers/$me'),
      apiVersion: apiVersion,
      body: {'vote': vote.value, 'id': me},
    );
    return PrReviewer.fromJson(json);
  }

  Future<PullRequest> complete(
    String org,
    PullRequest pr, {
    bool deleteSourceBranch = true,
    bool squash = false,
    String? commitMessage,
  }) async {
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: pr.projectId,
      path: '_apis/git/repositories/${pr.repositoryId}/pullRequests/${pr.id}',
      apiVersion: apiVersion,
      body: {
        'status': 'completed',
        if (pr.lastMergeSourceCommit != null)
          'lastMergeSourceCommit': {'commitId': pr.lastMergeSourceCommit},
        'completionOptions': {
          'deleteSourceBranch': deleteSourceBranch,
          'mergeStrategy': squash ? 'squash' : 'noFastForward',
          'mergeCommitMessage': ?commitMessage,
        },
      },
    );
    return PullRequest.fromJson(json);
  }

  Future<PullRequest> setStatus(
    String org,
    PullRequest pr,
    String status,
  ) async {
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: pr.projectId,
      path: '_apis/git/repositories/${pr.repositoryId}/pullRequests/${pr.id}',
      apiVersion: apiVersion,
      body: {'status': status},
    );
    return PullRequest.fromJson(json);
  }

  /// Body for a new thread: a plain conversation comment, or a line comment
  /// anchored on the right side of [iteration] with the change's tracking
  /// id so the service moves it across later pushes (spike w03).
  static Map<String, dynamic> threadBody({
    required String content,
    String? filePath,
    int? line,
    int? changeTrackingId,
    int? iteration,
  }) => {
    'comments': [
      {'parentCommentId': 0, 'content': content, 'commentType': 1},
    ],
    'status': 1,
    if (filePath != null && line != null)
      'threadContext': {
        'filePath': filePath,
        'rightFileStart': {'line': line, 'offset': 1},
        'rightFileEnd': {'line': line, 'offset': 1},
      },
    if (filePath != null && line != null && iteration != null)
      'pullRequestThreadContext': {
        'changeTrackingId': ?changeTrackingId,
        'iterationContext': {
          'firstComparingIteration': iteration,
          'secondComparingIteration': iteration,
        },
      },
  };

  Future<int> addThread(
    String org,
    PullRequest pr, {
    required String content,
    String? filePath,
    int? line,
    int? changeTrackingId,
    int? iteration,
  }) async {
    final json = await _client.send(
      method: 'POST',
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'threads'),
      apiVersion: apiVersion,
      body: threadBody(
        content: content,
        filePath: filePath,
        line: line,
        changeTrackingId: changeTrackingId,
        iteration: iteration,
      ),
    );
    return json['id'] as int? ?? 0;
  }

  /// Reply under the thread's root comment (what the web UI does: replies
  /// are flat, parented on comment 1).
  Future<void> reply(
    String org,
    PullRequest pr,
    int threadId,
    String content, {
    int parentCommentId = 1,
  }) => _client.send(
    method: 'POST',
    org: org,
    project: pr.projectId,
    path: _prPath(pr, 'threads/$threadId/comments'),
    apiVersion: apiVersion,
    body: {
      'parentCommentId': parentCommentId,
      'content': content,
      'commentType': 1,
    },
  );

  /// Resolve, reactivate, close… a thread ([PrThreadStatus] values).
  Future<void> setThreadStatus(
    String org,
    PullRequest pr,
    int threadId,
    String status,
  ) => _client.send(
    method: 'PATCH',
    org: org,
    project: pr.projectId,
    path: _prPath(pr, 'threads/$threadId'),
    apiVersion: apiVersion,
    body: {'status': status},
  );

  /// Commits one edited file to the PR's source branch through the Pushes
  /// API (`vso.code_write`), guarded by the branch tip the app last saw so a
  /// concurrent push fails instead of being overwritten. Returns the new
  /// commit id; the service adds an iteration to the PR.
  Future<String> pushEdit(
    String org,
    PullRequest pr, {
    required String path,
    required String content,
    required String message,
  }) async {
    final json = await _client.send(
      method: 'POST',
      org: org,
      project: pr.projectId,
      path: '_apis/git/repositories/${pr.repositoryId}/pushes',
      apiVersion: apiVersion,
      body: {
        'refUpdates': [
          {'name': pr.sourceRefName, 'oldObjectId': pr.lastMergeSourceCommit},
        ],
        'commits': [
          {
            'comment': message,
            'changes': [
              {
                'changeType': 'edit',
                'item': {'path': path},
                'newContent': {'content': content, 'contentType': 'rawtext'},
              },
            ],
          },
        ],
      },
    );
    final commits = json['commits'];
    if (commits is List && commits.isNotEmpty && commits.first is Map) {
      return (commits.first as Map)['commitId'] as String? ?? '';
    }
    return '';
  }

  /// Replaces lines [start]..[end] (1-based, inclusive) of [text] with
  /// [replacement], keeping the file's line ending style.
  static String applySuggestion(
    String text,
    int start,
    int end,
    String replacement,
  ) {
    final crlf = text.contains('\r\n');
    final eol = crlf ? '\r\n' : '\n';
    final lines = text.split(eol);
    final trailingNewline = lines.isNotEmpty && lines.last.isEmpty;
    if (trailingNewline) lines.removeLast();
    final from = (start - 1).clamp(0, lines.length);
    final to = end.clamp(from, lines.length);
    final body = replacement.replaceAll('\r\n', '\n');
    final inserted = body.isEmpty ? const <String>[] : body.split('\n');
    lines.replaceRange(from, to, inserted);
    return lines.join(eol) + (trailingNewline ? eol : '');
  }

  /// Conversation entries: non-system, non-file threads, oldest first.
  static List<PrThread> conversation(List<Map<String, dynamic>> raw) => [
    for (final t in raw)
      if (t['threadContext'] == null) ?PrThread.fromJson(t),
  ];
}
