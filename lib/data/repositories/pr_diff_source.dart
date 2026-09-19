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
    this.objectId,
  });

  final String path;
  final String changeType;
  final int changeTrackingId;
  final String? originalPath;

  /// Blob id of the file on the right side of this iteration; what a local
  /// viewed mark is keyed on so a later push clears it.
  final String? objectId;

  /// The blob entries of an iteration's `changeEntries`. A deleted file
  /// can come back with `item.path: null` and its path only in
  /// `originalPath` (seen on a client PR, 2026-09-19); an entry with
  /// neither is dropped rather than failing the whole page.
  static List<PrFileChange> listFrom(Object? entries) => [
    for (final e in (entries as List?)?.whereType<Map>() ?? const <Map>[])
      ?_fromEntry(e.cast<String, dynamic>()),
  ];

  static PrFileChange? _fromEntry(Map<String, dynamic> e) {
    final item = (e['item'] as Map?)?.cast<String, dynamic>() ?? const {};
    if ((item['gitObjectType'] ?? 'blob') != 'blob') return null;
    final originalPath = e['originalPath'] as String?;
    final path = item['path'] as String? ?? originalPath;
    if (path == null) return null;
    return PrFileChange(
      path: path,
      changeType: e['changeType'] as String? ?? '',
      changeTrackingId: (e['changeTrackingId'] as num?)?.toInt() ?? 0,
      originalPath: originalPath,
      objectId: item['objectId'] as String?,
    );
  }

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
    this.lastContentUpdatedDate,
    this.isDeleted = false,
    this.isSystem = false,
    this.usersLiked = const [],
  });

  factory PrComment.fromJson(Map<String, dynamic> c) {
    final identity = IdentityRef.fromField(c['author']);
    return PrComment(
      id: (c['id'] as num?)?.toInt() ?? 0,
      parentId: (c['parentCommentId'] as num?)?.toInt() ?? 0,
      author: identity?.displayName ?? '?',
      identity: identity,
      // A deleted comment answers `content: null` and `isDeleted: true`;
      // the web renders a stub in its place (spike w39 §4).
      content: c['content'] as String? ?? '',
      publishedDate: DateTime.tryParse(c['publishedDate'] as String? ?? ''),
      lastContentUpdatedDate: DateTime.tryParse(
        c['lastContentUpdatedDate'] as String? ?? '',
      ),
      isDeleted: c['isDeleted'] == true,
      isSystem: c['commentType'] == 'system',
      usersLiked: ((c['usersLiked'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => IdentityRef.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }

  final int id;
  final int parentId;
  final String author;
  final IdentityRef? identity;
  final String content;
  final DateTime? publishedDate;

  /// Moves when the content is edited (`PATCH …/comments/{id}`).
  final DateTime? lastContentUpdatedDate;
  final bool isDeleted;
  final bool isSystem;

  /// Everyone who liked the comment; present on every thread read.
  final List<IdentityRef> usersLiked;

  /// The content was changed after it was posted, so the card shows
  /// "edited" (R9). The service moves `lastContentUpdatedDate` by a few
  /// milliseconds on some writes that are not edits, so a second of
  /// slack keeps the marker honest.
  bool get isEdited {
    final edited = lastContentUpdatedDate;
    final published = publishedDate;
    if (edited == null || published == null) return false;
    return edited.difference(published).inSeconds >= 1;
  }

  bool likedBy(String? identityId) =>
      identityId != null && usersLiked.any((u) => u.id == identityId);

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
    this.leftLineEnd,
    this.isSystem = false,
    this.systemKind,
    this.systemText,
    this.publishedDate,
  });

  /// Parses one thread of the Threads API.
  ///
  /// By default this is the conversation's view: null for deleted threads,
  /// for system threads (votes, pushes, auto-complete) and for threads left
  /// with no comment. [includeSystem] keeps the system ones, resolved into
  /// [systemKind] and [systemText], for the Activity chip (R11);
  /// [includeDeleted] keeps deleted comments so the card can render the
  /// web's stub in their place (R9).
  static PrThread? fromJson(
    Map<String, dynamic> t, {
    bool includeSystem = false,
    bool includeDeleted = false,
  }) {
    if (t['isDeleted'] == true && !includeDeleted) return null;
    final ctx = (t['threadContext'] as Map?)?.cast<String, dynamic>();
    final properties =
        (t['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final systemKind = _property(properties, 'CodeReviewThreadType');
    final comments = ((t['comments'] as List?) ?? const [])
        .whereType<Map>()
        .map((c) => c.cast<String, dynamic>())
        .where(
          (c) =>
              (includeDeleted || c['isDeleted'] != true) &&
              (includeSystem || c['commentType'] != 'system'),
        )
        .map(PrComment.fromJson)
        .toList();
    final isSystem =
        systemKind != null ||
        (comments.isNotEmpty && comments.every((c) => c.isSystem));
    if (comments.isEmpty) return null;
    if (isSystem && !includeSystem) return null;
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
      leftLineEnd: ((ctx?['leftFileEnd'] as Map?)?['line'] as num?)?.toInt(),
      comments: comments,
      trackedFromLine:
          ((tracking?['origRightFileStart'] as Map?)?['line'] as num?)?.toInt(),
      isSystem: isSystem,
      systemKind: systemKind,
      systemText: isSystem
          ? substituteIdentities(
              comments.first.content,
              (t['identities'] as Map?)?.cast<String, dynamic>(),
            )
          : null,
      publishedDate: DateTime.tryParse(t['publishedDate'] as String? ?? ''),
    );
  }

  /// A thread property, which the service wraps as `{$type, $value}` on
  /// some routes and leaves bare on others.
  static String? _property(Map<String, dynamic> properties, String name) {
    final raw = properties[name];
    final value = raw is Map ? raw[r'$value'] : raw;
    if (value == null) return null;
    final text = '$value';
    return text.isEmpty ? null : text;
  }

  /// System thread contents are pre-rendered but may still carry `{n}`
  /// placeholders keyed into the thread's `identities` map (research/22 §1).
  static String substituteIdentities(
    String content,
    Map<String, dynamic>? identities,
  ) {
    if (identities == null || identities.isEmpty || !content.contains('{')) {
      return content;
    }
    return content.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final entry = identities[m.group(1)];
      final name = entry is Map ? entry['displayName'] as String? : null;
      return name ?? m.group(0)!;
    });
  }

  final int id;
  final String status;
  final String? filePath;
  final int? rightLine;

  /// Last line of a multi-line anchor (`rightFileEnd`), else null.
  final int? rightLineEnd;
  final int? leftLine;

  /// Last line of a multi-line anchor on the original side.
  final int? leftLineEnd;
  final List<PrComment> comments;

  /// Line the thread was posted on, when the service moved it.
  final int? trackedFromLine;

  /// A vote, push, status, reviewer or auto-complete event rather than a
  /// person's comment; only parsed with `includeSystem`.
  final bool isSystem;

  /// `VoteUpdate`, `StatusUpdate`, `RefUpdate`, `AutoCompleteUpdate`,
  /// `IsDraftUpdate`, `TargetChanged`, `ReviewersUpdate`,
  /// `ResetMultipleVotes`, `PolicyStatusUpdate`.
  final String? systemKind;

  /// The event's sentence, with `{n}` placeholders resolved.
  final String? systemText;
  final DateTime? publishedDate;

  bool get isResolved => PrThreadStatus.isResolved(status);

  /// A comment on the file as a whole: a `threadContext` with a path and no
  /// line on either side (spike w39 §4).
  bool get isFileLevel =>
      filePath != null && rightLine == null && leftLine == null;

  /// Anchored on the original (removed) side of the diff.
  bool get isLeftSide => leftLine != null;

  /// First line of the anchor on whichever side the thread lives.
  int? get anchorLine => rightLine ?? leftLine;

  /// Last line of the anchor, which equals [anchorLine] for a single line.
  int? get anchorLineEnd => rightLine != null
      ? (rightLineEnd ?? rightLine)
      : (leftLineEnd ?? leftLine);

  /// The anchor covers more than one line (R10's ranges).
  bool get isRange => (anchorLineEnd ?? 0) > (anchorLine ?? 0);

  /// Date of the first comment, which is when the thread was started.
  DateTime? get startedAt =>
      comments.isEmpty ? null : comments.first.publishedDate;
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
    return PrFileChange.listFrom(json['changeEntries']);
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
    bool includeSystem = false,
    bool includeDeleted = false,
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
      for (final t in value.cast<Map<String, dynamic>>())
        ?PrThread.fromJson(
          t,
          includeSystem: includeSystem,
          includeDeleted: includeDeleted,
        ),
    ];
  }
}
