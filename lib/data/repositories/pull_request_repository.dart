import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../models/pull_request.dart';
import 'pr_diff_source.dart';

enum PrListFilter { toReview, mine, all }

/// Pull request reads and the review writes: vote, complete, abandon, new
/// threads and replies. The list uses the org-level endpoint verified by
/// spike S4 (undocumented) and falls back to the project-level one.
class PullRequestRepository {
  PullRequestRepository(this._client);

  final AdoClient _client;

  static const apiVersion = '7.1';

  final Map<String, String> _me = {};

  /// Identity GUID of the signed-in user in this org (`connectionData`,
  /// semi-official), needed for `reviewerId` filters and voting.
  Future<String> meId(String org) async {
    final cached = _me[org];
    if (cached != null) return cached;
    final json = await _client.getJson(
      org: org,
      path: '_apis/connectionData',
      apiVersion: apiVersion,
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
    return ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => PullRequest.fromJson(m.cast<String, dynamic>()))
        .toList();
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

  Future<void> reply(
    String org,
    PullRequest pr,
    int threadId,
    String content,
  ) => _client.send(
    method: 'POST',
    org: org,
    project: pr.projectId,
    path: _prPath(pr, 'threads/$threadId/comments'),
    apiVersion: apiVersion,
    body: {'parentCommentId': 0, 'content': content, 'commentType': 1},
  );

  /// Conversation entries: non-system, non-file threads, oldest first.
  static List<PrThread> conversation(List<Map<String, dynamic>> raw) {
    final out = <PrThread>[];
    for (final t in raw) {
      if (t['isDeleted'] == true) continue;
      if (t['threadContext'] != null) continue;
      final comments = ((t['comments'] as List?) ?? const [])
          .whereType<Map>()
          .where((c) => c['isDeleted'] != true && c['commentType'] != 'system')
          .map(
            (c) => PrComment(
              author: ((c['author'] as Map?)?['displayName'] as String?) ?? '?',
              content: c['content'] as String? ?? '',
            ),
          )
          .toList();
      if (comments.isEmpty) continue;
      out.add(
        PrThread(
          id: t['id'] as int,
          status: t['status'] as String? ?? 'unknown',
          filePath: null,
          rightLine: null,
          leftLine: null,
          comments: comments,
          trackedFromLine: null,
        ),
      );
    }
    return out;
  }
}
