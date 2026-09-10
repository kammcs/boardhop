import '../../core/http/ado_client.dart';
import '../models/work_item.dart';

/// Read-only access to what the diff viewer needs from a pull request:
/// iterations, changed files, file content at a commit, and threads read for
/// the iteration pair on screen (research/00 §6a).
class PrRef {
  const PrRef({
    required this.org,
    required this.id,
    required this.projectId,
    required this.repositoryId,
    required this.title,
    required this.sourceBranch,
    required this.targetBranch,
  });

  final String org;
  final int id;
  final String projectId;
  final String repositoryId;
  final String title;
  final String sourceBranch;
  final String targetBranch;
}

class PrIteration {
  const PrIteration({
    required this.id,
    required this.sourceCommit,
    required this.commonCommit,
    required this.description,
    this.createdDate,
    this.author,
    this.reason,
  });

  factory PrIteration.fromJson(Map<String, dynamic> it) => PrIteration(
    id: it['id'] as int,
    sourceCommit:
        (it['sourceRefCommit'] as Map<String, dynamic>)['commitId'] as String,
    commonCommit:
        (it['commonRefCommit'] as Map<String, dynamic>)['commitId'] as String,
    description: it['description'] as String? ?? '',
    createdDate: DateTime.tryParse(it['createdDate'] as String? ?? ''),
    author: (it['author'] as Map?)?['displayName'] as String?,
    reason: it['reason'] as String?,
  );

  final int id;
  final String sourceCommit;

  /// Merge base with the target branch; the "old" side of the full PR diff.
  final String commonCommit;
  final String description;
  final DateTime? createdDate;
  final String? author;

  /// `push`, `retarget`, `resolveConflicts`, `forcePush`, `create`…
  final String? reason;
}

class PrFileChange {
  const PrFileChange({
    required this.path,
    required this.changeType,
    required this.changeTrackingId,
    this.originalPath,
  });

  final String path;
  final String changeType;
  final int changeTrackingId;
  final String? originalPath;

  bool get isAdd => changeType.contains('add');
  bool get isDelete => changeType.contains('delete');
}

class PrComment {
  const PrComment({
    required this.author,
    required this.content,
    this.id = 0,
    this.parentId = 0,
    this.identity,
    this.publishedDate,
  });

  factory PrComment.fromJson(Map<String, dynamic> c) {
    final identity = IdentityRef.fromField(c['author']);
    return PrComment(
      id: (c['id'] as num?)?.toInt() ?? 0,
      parentId: (c['parentCommentId'] as num?)?.toInt() ?? 0,
      author: identity?.displayName ?? '?',
      identity: identity,
      content: c['content'] as String? ?? '',
      publishedDate: DateTime.tryParse(c['publishedDate'] as String? ?? ''),
    );
  }

  final int id;
  final int parentId;
  final String author;
  final IdentityRef? identity;
  final String content;
  final DateTime? publishedDate;

  static final _suggestionFence = RegExp(
    r'```suggestion[^\n]*\r?\n([\s\S]*?)\r?\n?```',
  );

  /// Body of a ```` ```suggestion ```` fence in the comment (spike w03),
  /// without the trailing newline; null when the comment has none.
  String? get suggestion => _suggestionFence.firstMatch(content)?.group(1);
}

/// Thread statuses the service accepts on `PATCH threads/{id}`.
abstract final class PrThreadStatus {
  static const active = 'active';
  static const fixed = 'fixed';
  static const wontFix = 'wontFix';
  static const closed = 'closed';
  static const byDesign = 'byDesign';
  static const pending = 'pending';

  static String label(String status) => switch (status) {
    active => 'Active',
    fixed => 'Resolved',
    wontFix => "Won't fix",
    closed => 'Closed',
    byDesign => 'By design',
    pending => 'Pending',
    _ => status,
  };

  static bool isResolved(String status) =>
      status == fixed ||
      status == wontFix ||
      status == closed ||
      status == byDesign;
}

class PrThread {
  const PrThread({
    required this.id,
    required this.status,
    required this.filePath,
    required this.rightLine,
    required this.leftLine,
    required this.comments,
    required this.trackedFromLine,
    this.rightLineEnd,
  });

  /// Parses one thread of the Threads API; null for deleted threads and
  /// for those with only system comments (votes, reference updates).
  static PrThread? fromJson(Map<String, dynamic> t) {
    if (t['isDeleted'] == true) return null;
    final ctx = (t['threadContext'] as Map?)?.cast<String, dynamic>();
    final comments = ((t['comments'] as List?) ?? const [])
        .whereType<Map>()
        .map((c) => c.cast<String, dynamic>())
        .where((c) => c['isDeleted'] != true && c['commentType'] != 'system')
        .map(PrComment.fromJson)
        .toList();
    if (comments.isEmpty) return null;
    final tracking =
        ((t['pullRequestThreadContext'] as Map?)?['trackingCriteria'] as Map?)
            ?.cast<String, dynamic>();
    return PrThread(
      id: (t['id'] as num).toInt(),
      status: t['status'] as String? ?? 'unknown',
      filePath: ctx?['filePath'] as String?,
      rightLine: ((ctx?['rightFileStart'] as Map?)?['line'] as num?)?.toInt(),
      rightLineEnd: ((ctx?['rightFileEnd'] as Map?)?['line'] as num?)?.toInt(),
      leftLine: ((ctx?['leftFileStart'] as Map?)?['line'] as num?)?.toInt(),
      comments: comments,
      trackedFromLine:
          ((tracking?['origRightFileStart'] as Map?)?['line'] as num?)?.toInt(),
    );
  }

  final int id;
  final String status;
  final String? filePath;
  final int? rightLine;

  /// Last line of a multi-line anchor (`rightFileEnd`), else null.
  final int? rightLineEnd;
  final int? leftLine;
  final List<PrComment> comments;

  /// Line the thread was posted on, when the service moved it.
  final int? trackedFromLine;

  bool get isResolved => PrThreadStatus.isResolved(status);
  bool get isFileThread => filePath != null;
  DateTime? get lastActivity => comments.isEmpty
      ? null
      : comments
            .map((c) => c.publishedDate)
            .whereType<DateTime>()
            .fold(null, (DateTime? a, b) => a == null || b.isAfter(a) ? b : a);
}

class PrDiffSource {
  PrDiffSource(this._client);

  final AdoClient _client;

  Future<PrRef> pullRequest(String org, int id) async {
    final json = await _client.getJson(
      org: org,
      path: '_apis/git/pullrequests/$id',
      apiVersion: '7.1',
    );
    final repo = json['repository'] as Map<String, dynamic>;
    return PrRef(
      org: org,
      id: id,
      projectId: (repo['project'] as Map<String, dynamic>)['id'] as String,
      repositoryId: repo['id'] as String,
      title: json['title'] as String? ?? '',
      sourceBranch: json['sourceRefName'] as String? ?? '',
      targetBranch: json['targetRefName'] as String? ?? '',
    );
  }

  String _prPath(PrRef pr, String tail) =>
      '_apis/git/repositories/${pr.repositoryId}/pullRequests/${pr.id}/$tail';

  Future<List<PrIteration>> iterations(PrRef pr) async {
    final json = await _client.getJson(
      org: pr.org,
      project: pr.projectId,
      path: _prPath(pr, 'iterations'),
      apiVersion: '7.1',
    );
    final value = (json['value'] as List?) ?? const [];
    return [
      for (final it in value.cast<Map<String, dynamic>>())
        PrIteration.fromJson(it),
    ];
  }

  Future<List<PrFileChange>> changes(PrRef pr, int iteration) async {
    final json = await _client.getJson(
      org: pr.org,
      project: pr.projectId,
      path: _prPath(pr, 'iterations/$iteration/changes'),
      apiVersion: '7.1',
      query: {r'$top': '2000'},
    );
    final entries = (json['changeEntries'] as List?) ?? const [];
    return [
      for (final e in entries.cast<Map<String, dynamic>>())
        if (((e['item'] as Map<String, dynamic>?)?['gitObjectType'] ??
                'blob') ==
            'blob')
          PrFileChange(
            path: (e['item'] as Map<String, dynamic>)['path'] as String,
            changeType: e['changeType'] as String? ?? '',
            changeTrackingId: e['changeTrackingId'] as int? ?? 0,
            originalPath: e['originalPath'] as String?,
          ),
    ];
  }

  /// File content at a commit through the Items API (JSON with content).
  Future<String> fileAt(PrRef pr, String path, String commit) async {
    final json = await _client.getJson(
      org: pr.org,
      project: pr.projectId,
      path: '_apis/git/repositories/${pr.repositoryId}/items',
      apiVersion: '7.1',
      query: {
        'path': path,
        'versionDescriptor.version': commit,
        'versionDescriptor.versionType': 'commit',
        'includeContent': 'true',
      },
    );
    return json['content'] as String? ?? '';
  }

  /// Threads positioned for the diff between [baseIteration] and
  /// [iteration], which is the only read whose line numbers match what is
  /// on screen.
  Future<List<PrThread>> threads(
    PrRef pr, {
    required int iteration,
    required int baseIteration,
  }) async {
    final json = await _client.getJson(
      org: pr.org,
      project: pr.projectId,
      path: _prPath(pr, 'threads'),
      apiVersion: '7.1',
      query: {r'$iteration': '$iteration', r'$baseIteration': '$baseIteration'},
    );
    final value = (json['value'] as List?) ?? const [];
    return [
      for (final t in value.cast<Map<String, dynamic>>()) ?PrThread.fromJson(t),
    ];
  }
}
