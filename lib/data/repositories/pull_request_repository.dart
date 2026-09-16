import 'dart:typed_data';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/pr_check.dart';
import '../models/pull_request.dart';
import '../models/work_item_form.dart';
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
  PullRequestRepository(this._client, [AppDatabase? db, String? userId])
    : _cache = JsonCache(db, namespace: userId);

  final AdoClient _client;
  final JsonCache _cache;

  static const apiVersion = '7.1';
  static const policyApiVersion = '7.1-preview.1';

  /// Branch policies change rarely; the merge box reads them on every open.
  static const policiesTtl = Duration(hours: 1);

  final Map<String, String> _me = {};

  static String listKey(
    String org,
    String? project,
    PrListFilter filter, {
    String? repositoryId,
  }) => 'pr-list:$org:${project ?? '*'}:${repositoryId ?? '*'}:${filter.name}';

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
    String? repositoryId,
  }) async {
    final query = <String, String>{
      'searchCriteria.status': status,
      r'$top': '$top',
      'searchCriteria.repositoryId': ?repositoryId,
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
    if (status == 'active') {
      await _store(
        listKey(org, project, filter, repositoryId: repositoryId),
        raw,
      );
    }
    return raw.map(PullRequest.fromJson).toList();
  }

  /// The last active list fetched for this org/project/filter, if any.
  Future<PrListResult?> cachedList(
    String org, {
    String? project,
    PrListFilter filter = PrListFilter.toReview,
    String? repositoryId,
  }) async {
    final hit = await _cache.get(
      listKey(org, project, filter, repositoryId: repositoryId),
    );
    final decoded = hit?.json;
    if (hit == null || decoded is! List) return null;
    return (
      items: decoded
          .whereType<Map>()
          .map((m) => PullRequest.fromJson(m.cast<String, dynamic>()))
          .toList(),
      fetchedAt: hit.fetchedAt,
      fromCache: true,
    );
  }

  Future<void> _store(String key, Object json) => _cache.put(key, json);

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

  /// `PATCH {pr}` with whatever the caller changed. Every pull request
  /// write is online-only: nothing here goes through the [WriteQueue],
  /// because a merge, a vote or a reviewer change read back later would be
  /// a different answer than the one the user was shown (§4.1).
  Future<PullRequest> _patch(
    String org,
    PullRequest pr,
    Map<String, dynamic> body,
  ) async {
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: pr.projectId,
      path: '_apis/git/repositories/${pr.repositoryId}/pullRequests/${pr.id}',
      apiVersion: apiVersion,
      body: body,
    );
    return PullRequest.fromJson(json);
  }

  /// Completes the pull request now, with the sheet's choices.
  Future<PullRequest> complete(
    String org,
    PullRequest pr,
    PrCompletionOptions options,
  ) => _patch(org, pr, {
    'status': 'completed',
    if (pr.lastMergeSourceCommit != null)
      'lastMergeSourceCommit': {'commitId': pr.lastMergeSourceCommit},
    'completionOptions': options.toJson(),
  });

  /// Auto-complete: the service merges once every blocking policy passes.
  ///
  /// It is only offered when the target carries a blocking policy
  /// ([PrPolicySet.hasBlocking]) — without one the service merges the
  /// moment this lands, which is not what "auto-complete" reads as.
  Future<PullRequest> setAutoComplete(
    String org,
    PullRequest pr,
    PrCompletionOptions options,
  ) async {
    final me = await meId(org);
    return _patch(org, pr, {
      'autoCompleteSetBy': {'id': me},
      'completionOptions': options.toJson(),
    });
  }

  /// The null GUID is how auto-complete is cancelled; the options stay,
  /// which is what makes the sheet's choices sticky (spike w39 §2).
  static const nullGuid = '00000000-0000-0000-0000-000000000000';

  Future<PullRequest> cancelAutoComplete(String org, PullRequest pr) =>
      _patch(org, pr, {
        'autoCompleteSetBy': {'id': nullGuid},
      });

  /// Publish a draft (`false`) or mark an active pull request as a draft.
  /// Marking as draft clears the votes, which is what R4's confirm warns
  /// about.
  Future<PullRequest> setDraft(String org, PullRequest pr, bool isDraft) =>
      _patch(org, pr, {'isDraft': isDraft});

  /// Change the target branch; the service adds a `retarget` iteration with
  /// no files and re-queues the merge.
  Future<PullRequest> retarget(
    String org,
    PullRequest pr,
    String targetRefName,
  ) => _patch(org, pr, {'targetRefName': targetRefName});

  /// Re-runs the merge. There is no "restart merge" route: writing the
  /// default merge options is what the web does, and it moves the status
  /// back to `queued` (spike w39 §2).
  Future<PullRequest> restartMerge(String org, PullRequest pr) =>
      _patch(org, pr, {
        'mergeOptions': {
          'detectRenameFalsePositives': false,
          'disableRenames': false,
          'conflictAuthorshipCommits': false,
        },
      });

  Future<PullRequest> update(
    String org,
    PullRequest pr, {
    String? title,
    String? description,
  }) => _patch(org, pr, {'title': ?title, 'description': ?description});

  /// `PUT reviewers/{id}` adds the reviewer, or toggles required on one
  /// already there. `isRequired: false` is how the web makes a reviewer
  /// optional again (the field simply drops off the answer).
  Future<PrReviewer> addReviewer(
    String org,
    PullRequest pr,
    String identityId, {
    bool isRequired = false,
  }) async {
    final json = await _client.send(
      method: 'PUT',
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'reviewers/$identityId'),
      apiVersion: apiVersion,
      body: {'id': identityId, 'vote': 0, 'isRequired': isRequired},
    );
    return PrReviewer.fromJson(json);
  }

  Future<void> removeReviewer(String org, PullRequest pr, String identityId) =>
      _client.send(
        method: 'DELETE',
        org: org,
        project: pr.projectId,
        path: _prPath(pr, 'reviewers/$identityId'),
        apiVersion: apiVersion,
      );

  /// Required/optional without touching the vote: the same `PUT` as
  /// [addReviewer], which is idempotent for someone already a reviewer.
  Future<PrReviewer> setRequired(
    String org,
    PullRequest pr,
    String identityId,
    bool isRequired,
  ) => addReviewer(org, pr, identityId, isRequired: isRequired);

  /// The author resetting one reviewer's vote: the batch `PATCH reviewers`
  /// route, which answers 204 with no body. `PUT reviewers/{id}` with
  /// `vote: 0` would vote *as* that reviewer, which the service refuses.
  Future<void> resetVote(String org, PullRequest pr, String reviewerId) =>
      _client.send(
        method: 'PATCH',
        org: org,
        project: pr.projectId,
        path: _prPath(pr, 'reviewers'),
        apiVersion: apiVersion,
        body: [
          {'id': reviewerId, 'vote': 0},
        ],
      );

  /// Flag the pull request for the author's attention (R12).
  Future<PrReviewer> flag(
    String org,
    PullRequest pr,
    String reviewerId, {
    bool isFlagged = true,
  }) async {
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'reviewers/$reviewerId'),
      apiVersion: apiVersion,
      body: {'isFlagged': isFlagged},
    );
    return PrReviewer.fromJson(json);
  }

  /// Decline to review. The creator cannot decline their own pull request:
  /// the service answers HTTP 500, so the action is hidden for the author.
  Future<PrReviewer> decline(
    String org,
    PullRequest pr,
    String reviewerId, {
    bool hasDeclined = true,
  }) async {
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'reviewers/$reviewerId'),
      apiVersion: apiVersion,
      body: {'hasDeclined': hasDeclined},
    );
    return PrReviewer.fromJson(json);
  }

  /// Labels, which `GET pullRequests/{id}` never carries (spikes s65 §A,
  /// w40): the detail page merges this sub-resource into the pull request.
  Future<List<PrLabel>> labels(String org, PullRequest pr) async {
    final json = await _client.getJson(
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'labels'),
      apiVersion: apiVersion,
    );
    return PrLabel.listFrom(json['value']);
  }

  /// Adds a label by name; an existing one comes back unchanged.
  Future<PrLabel> addLabel(String org, PullRequest pr, String name) async {
    final json = await _client.send(
      method: 'POST',
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'labels'),
      apiVersion: apiVersion,
      body: {'name': name},
    );
    return PrLabel.fromJson(json);
  }

  /// Removes a label by name or id; a name goes in unencoded because
  /// [AdoClient.buildUri] encodes each path segment itself.
  Future<void> removeLabel(String org, PullRequest pr, String nameOrId) =>
      _client.send(
        method: 'DELETE',
        org: org,
        project: pr.projectId,
        path: _prPath(pr, 'labels/$nameOrId'),
        apiVersion: apiVersion,
      );

  /// Edits one comment in place; the service moves
  /// `lastContentUpdatedDate`, which is what renders the "edited" marker.
  Future<PrComment> editComment(
    String org,
    PullRequest pr,
    int threadId,
    int commentId,
    String content,
  ) async {
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'threads/$threadId/comments/$commentId'),
      apiVersion: apiVersion,
      body: {'content': content},
    );
    return PrComment.fromJson(json);
  }

  /// Deletes one comment. The comment stays in the thread with
  /// `isDeleted: true` and no content (the web's stub); deleting the last
  /// one deletes the thread with it.
  Future<void> deleteComment(
    String org,
    PullRequest pr,
    int threadId,
    int commentId,
  ) => _client.send(
    method: 'DELETE',
    org: org,
    project: pr.projectId,
    path: _prPath(pr, 'threads/$threadId/comments/$commentId'),
    apiVersion: apiVersion,
  );

  /// Both like routes are idempotent (spike w39 §4).
  Future<void> like(String org, PullRequest pr, int threadId, int commentId) =>
      _client.send(
        method: 'POST',
        org: org,
        project: pr.projectId,
        path: _prPath(pr, 'threads/$threadId/comments/$commentId/likes'),
        apiVersion: apiVersion,
      );

  Future<void> unlike(
    String org,
    PullRequest pr,
    int threadId,
    int commentId,
  ) => _client.send(
    method: 'DELETE',
    org: org,
    project: pr.projectId,
    path: _prPath(pr, 'threads/$threadId/comments/$commentId/likes'),
    apiVersion: apiVersion,
  );

  /// The merge conflicts behind `mergeStatus: conflicts` (undocumented but
  /// 7.1). Resolution stays out of v1: the list is read-only here.
  Future<List<PrConflict>> conflicts(
    String org,
    PullRequest pr, {
    bool excludeResolved = false,
    int top = 100,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'conflicts'),
      apiVersion: apiVersion,
      query: {if (excludeResolved) 'excludeResolved': 'true', r'$top': '$top'},
    );
    return ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => PrConflict.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// Mails the pull request to people (R2's Share).
  Future<void> share(
    String org,
    PullRequest pr,
    List<String> identityIds,
    String message,
  ) => _client.send(
    method: 'POST',
    org: org,
    project: pr.projectId,
    path: _prPath(pr, 'share'),
    apiVersion: apiVersion,
    body: {
      'receivers': [
        for (final id in identityIds) {'id': id},
      ],
      'message': message,
    },
  );

  static String policiesKey(String org, String repositoryId, String refName) =>
      'pr:policies:$org:$repositoryId:$refName';

  /// Branch policies on the pull request's target, which decide whether
  /// auto-complete is offered at all, which merge strategies the sheet may
  /// offer, and the required-reviewer names in Checks.
  ///
  /// Cached for an hour: policies change rarely and every merge box read
  /// would otherwise cost a call. A cached answer is filtered through
  /// [PrPolicySet.forTarget] again so a stale blob cannot leak another
  /// branch's rules.
  Future<PrPolicySet> policies(
    String org,
    String project,
    String repositoryId,
    String targetRefName, {
    bool refresh = false,
  }) async {
    final key = policiesKey(org, repositoryId, targetRefName);
    if (!refresh) {
      final hit = await _cache.get(key);
      if (hit != null &&
          DateTime.now().difference(hit.fetchedAt) < policiesTtl) {
        return PrPolicySet.fromJson(hit.json, targetRefName);
      }
    }
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/git/policy/configurations',
      apiVersion: apiVersion,
      query: {'repositoryId': repositoryId, 'refName': targetRefName},
    );
    final set = PrPolicySet.fromJson(json, targetRefName);
    await _store(key, set.toJson());
    return set;
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

  /// `offset: 2147483647` is how the service spells "end of line"; a range
  /// that covers whole lines ends there (research/22 §1).
  static const endOfLineOffset = 2147483647;

  /// Body for a new thread.
  ///
  /// Four shapes, all verified on the scratch pull request (spike w39 §4):
  /// a plain conversation comment (no [filePath]); a **file-level** comment
  /// ([fileLevel], a `threadContext` with the path and nothing else); a line
  /// comment on the right (new) side; and the same on the **left**
  /// (original) side with [leftSide], which is what the gutter of a removed
  /// line posts. [endLine] extends any of the line shapes into a range
  /// (R10). The iteration context carries the change's tracking id so the
  /// service moves the thread across later pushes (spike w03).
  static Map<String, dynamic> threadBody({
    required String content,
    String? filePath,
    int? line,
    int? endLine,
    bool leftSide = false,
    bool fileLevel = false,
    int? changeTrackingId,
    int? iteration,
  }) {
    final last = endLine == null || endLine < (line ?? 0) ? line : endLine;
    final isRange = line != null && last != null && last > line;
    final anchored = filePath != null && line != null && !fileLevel;
    final startKey = leftSide ? 'leftFileStart' : 'rightFileStart';
    final endKey = leftSide ? 'leftFileEnd' : 'rightFileEnd';
    final context = switch (filePath) {
      final String path when fileLevel => {'filePath': path},
      final String path when anchored => {
        'filePath': path,
        startKey: {'line': line, 'offset': 1},
        endKey: {'line': last, 'offset': isRange ? endOfLineOffset : 1},
      },
      _ => null,
    };
    return {
      'comments': [
        {'parentCommentId': 0, 'content': content, 'commentType': 1},
      ],
      'status': 1,
      'threadContext': ?context,
      if (filePath != null && iteration != null && (anchored || fileLevel))
        'pullRequestThreadContext': {
          'changeTrackingId': ?changeTrackingId,
          'iterationContext': {
            'firstComparingIteration': iteration,
            'secondComparingIteration': iteration,
          },
        },
    };
  }

  Future<int> addThread(
    String org,
    PullRequest pr, {
    required String content,
    String? filePath,
    int? line,
    int? endLine,
    bool leftSide = false,
    bool fileLevel = false,
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
        endLine: endLine,
        leftSide: leftSide,
        fileLevel: fileLevel,
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

  /// `POST …/pullRequests/{id}/attachments/{fileName}` with the bytes as
  /// the body (spike w32 §4, research/17 §1).
  ///
  /// Three things this store does not share with the work item one. The file
  /// name is the key and rides in the **path**, not a query; a name already
  /// in the pull request is HTTP 400 with no overwrite, so callers uniquify
  /// first (`uniqueAttachmentName`); and the name goes in unencoded, because
  /// [AdoClient.buildUri] percent-encodes every path segment itself and an
  /// already-encoded name would come out doubly escaped.
  ///
  /// `Content-Type` must be `application/octet-stream`: declaring the real
  /// type of the file is HTTP 400 on both stores.
  Future<AttachmentRef> uploadAttachment(
    String org,
    PullRequest pr,
    String fileName,
    Uint8List bytes,
  ) async {
    final json = await _client.send(
      method: 'POST',
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'attachments/$fileName'),
      apiVersion: apiVersion,
      body: bytes,
      contentType: 'application/octet-stream',
    );
    return AttachmentRef.fromJson(json, fileName: fileName);
  }

  /// Everything already uploaded to this pull request.
  Future<List<AttachmentRef>> listAttachments(
    String org,
    PullRequest pr,
  ) async {
    final json = await _client.getJson(
      org: org,
      project: pr.projectId,
      path: _prPath(pr, 'attachments'),
      apiVersion: apiVersion,
    );
    return ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => AttachmentRef.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// An attachment's bytes with the bearer token, the same as the work item
  /// side. Without the header the service answers HTTP 203 and a sign-in
  /// page rather than a 401, so no image loader can be left to fetch one
  /// itself (spike w32 §3).
  Future<Uint8List> attachmentBytes(String url) =>
      _client.getBytes(Uri.parse(url));

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
  /// Every thread a person wrote, file-anchored ones included, oldest
  /// first. Most reviews live entirely in the files (spike s22: 52 of 52
  /// threads on ServiceDelivery !8261), so the Conversation tab shows them
  /// all; system threads (votes, pushes) and deleted ones drop out in
  /// [PrThread.fromJson].
  ///
  /// [includeSystem] adds the votes, pushes and status changes as quiet
  /// rows for the Activity chip (R11); [includeDeleted] keeps the deleted
  /// stubs the web renders (R9). Both are off by default, so every existing
  /// caller reads the same list it always did.
  static List<PrThread> conversation(
    List<Map<String, dynamic>> raw, {
    bool includeSystem = false,
    bool includeDeleted = false,
  }) {
    final threads = [
      for (final t in raw)
        ?PrThread.fromJson(
          t,
          includeSystem: includeSystem,
          includeDeleted: includeDeleted,
        ),
    ];
    threads.sort((a, b) {
      final ta = a.startedAt?.millisecondsSinceEpoch ?? 0;
      final tb = b.startedAt?.millisecondsSinceEpoch ?? 0;
      if (ta != tb) return ta.compareTo(tb);
      return a.id.compareTo(b.id);
    });
    return threads;
  }

  /// The conversation narrowed to [filter].
  static List<PrThread> filterConversation(
    List<PrThread> threads,
    PrConversationFilter filter,
  ) => switch (filter) {
    PrConversationFilter.all => threads,
    PrConversationFilter.active => [
      for (final t in threads)
        if (!t.isResolved) t,
    ],
    PrConversationFilter.resolved => [
      for (final t in threads)
        if (t.isResolved) t,
    ],
  };
}

/// Conversation tab filter: everything, the threads still open, or the
/// ones settled (resolved, won't fix, closed, by design).
enum PrConversationFilter {
  all('All'),
  active('Active'),
  resolved('Resolved');

  const PrConversationFilter(this.label);

  final String label;
}
